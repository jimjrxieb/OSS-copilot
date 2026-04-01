#!/usr/bin/env bash
# deploy-dev.sh
# Deploy or upgrade a Helm release to the dev/ environment.
# Validates security posture before and after deploy.
#
# Usage:
#   bash deploy-dev.sh --chart ./helm --values ./helm/values-dev.yaml --release myapp --namespace dev
#   bash deploy-dev.sh --chart ./helm --release myapp --namespace dev --dry-run
#   bash deploy-dev.sh --generate-values --target-dir ./k8s/ --output ./helm/values-dev.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
CHART_PATH=""
VALUES_FILE=""
RELEASE_NAME=""
NAMESPACE="dev"
DRY_RUN=false
SKIP_SCAN=false
GENERATE_VALUES=false
TARGET_DIR=""
OUTPUT_FILE=""
TIMEOUT="5m"

usage() {
  cat <<EOF
Deploy Helm release to dev environment with security validation.

Usage: bash deploy-dev.sh [OPTIONS]

Deploy options:
  -c, --chart PATH        Helm chart directory (required for deploy)
  -f, --values FILE       Values file (default: <chart>/values-dev.yaml)
  -r, --release NAME      Helm release name (required for deploy)
  -n, --namespace NS      Target namespace (default: dev)
  --timeout DURATION       Helm wait timeout (default: 5m)
  --dry-run               Render and validate only, don't deploy
  --skip-scan             Skip post-deploy kubescape scan

Generate options:
  --generate-values       Generate a values-dev.yaml from existing K8s manifests
  --target-dir PATH       Directory with K8s manifests to read
  --output FILE           Output values file path

Examples:
  bash deploy-dev.sh --chart ./helm --release myapp --namespace dev
  bash deploy-dev.sh --chart ./helm --values ./helm/values-dev.yaml --release myapp -n dev --dry-run
  bash deploy-dev.sh --generate-values --target-dir ./k8s/ --output ./helm/values-dev.yaml
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--chart)           CHART_PATH="$2"; shift 2 ;;
    -f|--values)          VALUES_FILE="$2"; shift 2 ;;
    -r|--release)         RELEASE_NAME="$2"; shift 2 ;;
    -n|--namespace)       NAMESPACE="$2"; shift 2 ;;
    --timeout)            TIMEOUT="$2"; shift 2 ;;
    --dry-run)            DRY_RUN=true; shift ;;
    --skip-scan)          SKIP_SCAN=true; shift ;;
    --generate-values)    GENERATE_VALUES=true; shift ;;
    --target-dir)         TARGET_DIR="$2"; shift 2 ;;
    --output)             OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

# ── Generate values mode ─────────────────────────────────────────────────────
if [[ "$GENERATE_VALUES" == "true" ]]; then
  if [[ -z "$TARGET_DIR" || -z "$OUTPUT_FILE" ]]; then
    echo -e "${RED}ERROR: --generate-values requires --target-dir and --output${NC}"
    exit 1
  fi

  echo -e "${BLUE}=== Generating dev values from $TARGET_DIR ===${NC}"

  # Extract image from first Deployment found
  IMAGE=$(grep -rh 'image:' "$TARGET_DIR" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "your-registry/your-app:dev-latest")
  IMAGE_REPO=$(echo "$IMAGE" | cut -d: -f1)
  IMAGE_TAG=$(echo "$IMAGE" | cut -d: -f2)
  [[ "$IMAGE_TAG" == "$IMAGE_REPO" ]] && IMAGE_TAG="dev-latest"

  # Extract port from first containerPort found
  APP_PORT=$(grep -rh 'containerPort:' "$TARGET_DIR" 2>/dev/null | head -1 | awk '{print $2}' || echo "8080")

  cp "$PKG_DIR/tools/helm-values-dev.yaml" "$OUTPUT_FILE"
  sed -i "s|your-registry.example.com/your-app|$IMAGE_REPO|g" "$OUTPUT_FILE"
  sed -i "s|dev-latest|$IMAGE_TAG|g" "$OUTPUT_FILE"
  sed -i "s|containerPort: 8080|containerPort: $APP_PORT|g" "$OUTPUT_FILE"

  echo -e "${GREEN}Generated: $OUTPUT_FILE${NC}"
  echo -e "  Image: ${IMAGE_REPO}:${IMAGE_TAG}"
  echo -e "  Port:  ${APP_PORT}"
  echo -e "${YELLOW}Review and customize before deploying.${NC}"
  exit 0
fi

# ── Deploy mode ──────────────────────────────────────────────────────────────
if [[ -z "$CHART_PATH" || -z "$RELEASE_NAME" ]]; then
  echo -e "${RED}ERROR: --chart and --release are required${NC}"
  usage
  exit 1
fi

if [[ ! -d "$CHART_PATH" ]]; then
  echo -e "${RED}ERROR: Chart directory not found: $CHART_PATH${NC}"
  exit 1
fi

# Auto-detect values file
if [[ -z "$VALUES_FILE" ]]; then
  if [[ -f "$CHART_PATH/values-dev.yaml" ]]; then
    VALUES_FILE="$CHART_PATH/values-dev.yaml"
  elif [[ -f "$CHART_PATH/values.yaml" ]]; then
    VALUES_FILE="$CHART_PATH/values.yaml"
    echo -e "${YELLOW}WARNING: Using default values.yaml — consider creating values-dev.yaml${NC}"
  else
    echo -e "${RED}ERROR: No values file found. Use --values to specify.${NC}"
    exit 1
  fi
fi

echo ""
echo -e "${BLUE}=== Dev Environment Deployment ===${NC}"
echo "  Release   : $RELEASE_NAME"
echo "  Chart     : $CHART_PATH"
echo "  Values    : $VALUES_FILE"
echo "  Namespace : $NAMESPACE"
echo "  Dry run   : $DRY_RUN"
echo ""

# ── Pre-flight checks ────────────────────────────────────────────────────────
echo -e "${BLUE}[1/6] Pre-flight checks${NC}"

# Cluster access
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster. Check kubectl context.${NC}"
  exit 1
fi
CLUSTER_CTX=$(kubectl config current-context)
echo -e "  Cluster: ${GREEN}$CLUSTER_CTX${NC}"

# Helm version
HELM_VER=$(helm version --short 2>/dev/null | grep -oP 'v\d+\.\d+')
echo -e "  Helm:    ${GREEN}$(helm version --short)${NC}"

# Check ArgoCD ownership
ARGO_APP=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null || true)
if [[ -n "$ARGO_APP" ]]; then
  echo -e "${RED}ERROR: Namespace '$NAMESPACE' is managed by ArgoCD app '$ARGO_APP'.${NC}"
  echo -e "${RED}Deploy through git, not helm upgrade. See argocd-rules.md.${NC}"
  exit 1
fi

# ── Helm lint ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/6] Helm lint${NC}"
if helm lint "$CHART_PATH" -f "$VALUES_FILE" --namespace "$NAMESPACE"; then
  echo -e "  ${GREEN}Lint passed${NC}"
else
  echo -e "  ${RED}Lint failed — fix chart errors before deploying${NC}"
  exit 1
fi

# ── Template render + security scan ──────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/6] Render and scan${NC}"
RENDERED="/tmp/dev-rendered-${RELEASE_NAME}-$(date +%s).yaml"
helm template "$RELEASE_NAME" "$CHART_PATH" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  > "$RENDERED"
echo -e "  Rendered to: $RENDERED"

# Scan rendered manifests if checkov is available
if command -v checkov &>/dev/null; then
  echo -e "  Running checkov..."
  CHECKOV_FAILS=$(checkov -f "$RENDERED" --framework kubernetes --compact --quiet 2>/dev/null | grep -c "FAILED" || true)
  if [[ "$CHECKOV_FAILS" -gt 0 ]]; then
    echo -e "  ${YELLOW}WARNING: $CHECKOV_FAILS checkov findings in rendered manifests${NC}"
    echo -e "  ${YELLOW}Run: checkov -f $RENDERED --framework kubernetes${NC}"
  else
    echo -e "  ${GREEN}Checkov: 0 failures${NC}"
  fi
else
  echo -e "  ${YELLOW}checkov not installed — skipping pre-deploy scan${NC}"
fi

# ── Dry run or deploy ────────────────────────────────────────────────────────
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${BLUE}[4/6] Helm dry-run${NC}"
  helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --dry-run
  echo ""
  echo -e "${GREEN}Dry run complete. Review the output above.${NC}"
  echo -e "Remove --dry-run to deploy for real."
  rm -f "$RENDERED"
  exit 0
fi

echo -e "${BLUE}[4/6] Deploying${NC}"
helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout "$TIMEOUT"

echo -e "  ${GREEN}Helm release deployed${NC}"

# ── Post-deploy verification ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[5/6] Post-deploy verification${NC}"

# Wait for pods
echo -e "  Waiting for pods..."
kubectl wait --for=condition=ready pod \
  -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=120s 2>/dev/null || echo -e "  ${YELLOW}WARNING: Not all pods ready within 120s${NC}"

# Pod status
echo ""
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o wide

# Helm status
echo ""
helm list -n "$NAMESPACE" --filter "$RELEASE_NAME"

# Check for :latest tags
LATEST_COUNT=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | grep -cE ':latest$' || true)
if [[ "$LATEST_COUNT" -gt 0 ]]; then
  echo -e "  ${RED}FAIL: $LATEST_COUNT container(s) using :latest tag${NC}"
else
  echo -e "  ${GREEN}PASS: No :latest image tags${NC}"
fi

# Check security context
NONROOT=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{range .items[*].spec.securityContext}{.runAsNonRoot}{"\n"}{end}' 2>/dev/null | grep -c "true" || true)
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" --no-headers 2>/dev/null | wc -l || true)
if [[ "$NONROOT" -ge "$POD_COUNT" && "$POD_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}PASS: All pods runAsNonRoot${NC}"
else
  echo -e "  ${YELLOW}WARNING: Not all pods have runAsNonRoot set${NC}"
fi

# ── Post-deploy security scan ────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[6/6] Post-deploy security scan${NC}"

if [[ "$SKIP_SCAN" == "true" ]]; then
  echo -e "  ${YELLOW}Skipped (--skip-scan)${NC}"
elif command -v kubescape &>/dev/null; then
  echo -e "  Running kubescape on live namespace..."
  kubescape scan workload --namespace "$NAMESPACE" --format pretty-printer 2>/dev/null || true
else
  echo -e "  ${YELLOW}kubescape not installed — skipping live scan${NC}"
fi

# Cleanup
rm -f "$RENDERED"

echo ""
echo -e "${GREEN}=== Dev deployment complete ===${NC}"
echo "  Release:   $RELEASE_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Context:   $CLUSTER_CTX"
echo ""
echo "  Port-forward: kubectl port-forward svc/$RELEASE_NAME 8080:80 -n $NAMESPACE"
echo "  Rollback:     helm rollback $RELEASE_NAME -n $NAMESPACE"
echo "  Uninstall:    helm uninstall $RELEASE_NAME -n $NAMESPACE"
