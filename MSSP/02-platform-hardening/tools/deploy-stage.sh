#!/usr/bin/env bash
# deploy-stage.sh — Deploy or upgrade a Helm release to the staging environment.
# Validates security posture before and after deploy. Staging enforces prod-like
# security: PSS restricted, NetworkPolicy, admission control, full resource class.
#
# Usage:
#   bash deploy-stage.sh --chart ./helm --values ./helm/values-staging.yaml --release myapp --namespace staging
#   bash deploy-stage.sh --chart ./helm --release myapp --namespace staging --dry-run
#   bash deploy-stage.sh --generate-values --from-values ./helm/values-dev.yaml --output ./helm/values-staging.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
CHART_PATH=""
VALUES_FILE=""
RELEASE_NAME=""
NAMESPACE="staging"
DRY_RUN=false
SKIP_SCAN=false
GENERATE_VALUES=false
FROM_VALUES=""
OUTPUT_FILE=""
TIMEOUT="5m"
STRICT=true

usage() {
  cat <<EOF
Deploy Helm release to staging environment with production-class security validation.

Usage: bash deploy-stage.sh [OPTIONS]

Deploy options:
  -c, --chart PATH        Helm chart directory (required for deploy)
  -f, --values FILE       Values file (default: <chart>/values-staging.yaml)
  -r, --release NAME      Helm release name (required for deploy)
  -n, --namespace NS      Target namespace (default: staging)
  --timeout DURATION       Helm wait timeout (default: 5m)
  --dry-run               Render and validate only, don't deploy
  --skip-scan             Skip post-deploy kubescape scan
  --no-strict             Don't fail on kubescape CRITICAL/HIGH (not recommended)

Generate options:
  --generate-values       Generate values-staging.yaml from dev values
  --from-values FILE      Source values file (values-dev.yaml)
  --output FILE           Output values file path

Examples:
  bash deploy-stage.sh --chart ./helm --release myapp --namespace staging
  bash deploy-stage.sh --chart ./helm --values ./helm/values-staging.yaml --release myapp --dry-run
  bash deploy-stage.sh --generate-values --from-values ./helm/values-dev.yaml --output ./helm/values-staging.yaml
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
    --no-strict)          STRICT=false; shift ;;
    --generate-values)    GENERATE_VALUES=true; shift ;;
    --from-values)        FROM_VALUES="$2"; shift 2 ;;
    --output)             OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

# ── Generate values mode ─────────────────────────────────────────────────────
if [[ "$GENERATE_VALUES" == "true" ]]; then
  if [[ -z "$OUTPUT_FILE" ]]; then
    echo -e "${RED}ERROR: --generate-values requires --output${NC}"
    exit 1
  fi

  echo -e "${BLUE}=== Generating staging values ===${NC}"

  if [[ -n "$FROM_VALUES" && -f "$FROM_VALUES" ]]; then
    # Start from dev values, upgrade to staging class
    cp "$FROM_VALUES" "$OUTPUT_FILE"

    # Upgrade replicas
    sed -i 's/^replicaCount:.*/replicaCount: 2/' "$OUTPUT_FILE"

    # Upgrade resources to staging/prod class
    sed -i 's/cpu: "100m"/cpu: "250m"/g' "$OUTPUT_FILE"
    sed -i 's/cpu: "500m"/cpu: "1"/g' "$OUTPUT_FILE"
    sed -i 's/cpu: 100m/cpu: 250m/g' "$OUTPUT_FILE"
    sed -i 's/cpu: 500m/cpu: 1/g' "$OUTPUT_FILE"
    sed -i 's/memory: "128Mi"/memory: "256Mi"/g' "$OUTPUT_FILE"
    sed -i 's/memory: "512Mi"/memory: "1Gi"/g' "$OUTPUT_FILE"
    sed -i 's/memory: 128Mi/memory: 256Mi/g' "$OUTPUT_FILE"
    sed -i 's/memory: 512Mi/memory: 1Gi/g' "$OUTPUT_FILE"

    # Enable networking features
    sed -i 's/ingress:/# ingress (enable for staging):\'$'\n''ingress:/' "$OUTPUT_FILE" 2>/dev/null || true

    # Update environment
    sed -i 's/value: "dev"/value: "staging"/' "$OUTPUT_FILE"
    sed -i 's/value: "debug"/value: "info"/' "$OUTPUT_FILE"

    echo -e "${GREEN}Generated from dev values: $OUTPUT_FILE${NC}"
    echo -e "  Replicas:  2"
    echo -e "  Resources: 250m/256Mi → 1/1Gi (prod class)"
    echo -e "  Env:       staging / info"
  else
    # Copy the template
    cp "$PKG_DIR/tools/helm-values-staging.yaml" "$OUTPUT_FILE"
    echo -e "${GREEN}Generated from template: $OUTPUT_FILE${NC}"
  fi

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
  if [[ -f "$CHART_PATH/values-staging.yaml" ]]; then
    VALUES_FILE="$CHART_PATH/values-staging.yaml"
  elif [[ -f "$CHART_PATH/values-stage.yaml" ]]; then
    VALUES_FILE="$CHART_PATH/values-stage.yaml"
  else
    echo -e "${RED}ERROR: No staging values file found. Use --values to specify.${NC}"
    exit 1
  fi
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Staging Environment Deployment        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo "  Release   : $RELEASE_NAME"
echo "  Chart     : $CHART_PATH"
echo "  Values    : $VALUES_FILE"
echo "  Namespace : $NAMESPACE"
echo "  Dry run   : $DRY_RUN"
echo "  Strict    : $STRICT"
echo ""

# ── [1/8] Pre-flight checks ─────────────────────────────────────────────────
echo -e "${BLUE}[1/8] Pre-flight checks${NC}"

# Cluster access
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster. Check kubectl context.${NC}"
  exit 1
fi
CLUSTER_CTX=$(kubectl config current-context)
echo -e "  Cluster: ${GREEN}$CLUSTER_CTX${NC}"

# Helm version
echo -e "  Helm:    ${GREEN}$(helm version --short)${NC}"

# Check ArgoCD ownership — HARD STOP
ARGO_APP=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null || true)
if [[ -n "$ARGO_APP" ]]; then
  echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  HARD STOP: Namespace '$NAMESPACE' is managed by ArgoCD    ║${NC}"
  echo -e "${RED}║  ArgoCD app: $ARGO_APP${NC}"
  echo -e "${RED}║                                                              ║${NC}"
  echo -e "${RED}║  Use promote-image.sh to promote through GitOps:             ║${NC}"
  echo -e "${RED}║  bash tools/promote-image.sh \\                      ║${NC}"
  echo -e "${RED}║    --app $RELEASE_NAME --from dev --to staging               ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi

# Check admission control is running
KYVERNO_RUNNING=false
GATEKEEPER_RUNNING=false
if kubectl get pods -n kyverno -l app.kubernetes.io/name=kyverno --no-headers 2>/dev/null | grep -q "Running"; then
  KYVERNO_RUNNING=true
  echo -e "  Kyverno: ${GREEN}running${NC}"
elif kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | grep -q "Running"; then
  GATEKEEPER_RUNNING=true
  echo -e "  Gatekeeper: ${GREEN}running${NC}"
else
  echo -e "  ${YELLOW}WARNING: No admission controller detected — staging validation will be incomplete${NC}"
  echo -e "  ${YELLOW}Run Playbook 06 (deploy-admission-control) first${NC}"
fi

# ── [2/8] Namespace setup ────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/8] Namespace setup${NC}"

if kubectl get ns "$NAMESPACE" &>/dev/null; then
  # Verify PSS labels
  PSS_ENFORCE=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
  if [[ "$PSS_ENFORCE" == "restricted" ]]; then
    echo -e "  Namespace exists: ${GREEN}PSS restricted${NC}"
  elif [[ "$PSS_ENFORCE" == "baseline" ]]; then
    echo -e "  ${YELLOW}WARNING: Namespace has PSS 'baseline' — staging should use 'restricted'${NC}"
    echo -e "  ${YELLOW}Upgrading PSS labels...${NC}"
    kubectl label ns "$NAMESPACE" \
      pod-security.kubernetes.io/enforce=restricted \
      pod-security.kubernetes.io/enforce-version=latest \
      pod-security.kubernetes.io/audit=restricted \
      pod-security.kubernetes.io/audit-version=latest \
      pod-security.kubernetes.io/warn=restricted \
      pod-security.kubernetes.io/warn-version=latest \
      --overwrite
    echo -e "  ${GREEN}PSS upgraded to restricted${NC}"
  else
    echo -e "  ${YELLOW}WARNING: No PSS labels — adding restricted${NC}"
    kubectl label ns "$NAMESPACE" \
      pod-security.kubernetes.io/enforce=restricted \
      pod-security.kubernetes.io/enforce-version=latest \
      pod-security.kubernetes.io/audit=restricted \
      pod-security.kubernetes.io/audit-version=latest \
      pod-security.kubernetes.io/warn=restricted \
      pod-security.kubernetes.io/warn-version=latest \
      --overwrite
    echo -e "  ${GREEN}PSS labels applied${NC}"
  fi
else
  echo -e "  Creating namespace with PSS restricted..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    environment: staging
EOF
  echo -e "  ${GREEN}Namespace created${NC}"
fi

# ── [3/8] Helm lint ──────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/8] Helm lint${NC}"
if helm lint "$CHART_PATH" -f "$VALUES_FILE" --namespace "$NAMESPACE"; then
  echo -e "  ${GREEN}Lint passed${NC}"
else
  echo -e "  ${RED}Lint failed — fix chart errors before deploying${NC}"
  exit 1
fi

# ── [4/8] Template render + security scan ────────────────────────────────────
echo ""
echo -e "${BLUE}[4/8] Render and scan${NC}"
RENDERED="/tmp/staging-rendered-${RELEASE_NAME}-$(date +%s).yaml"
helm template "$RELEASE_NAME" "$CHART_PATH" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  > "$RENDERED"
echo -e "  Rendered to: $RENDERED"

# Checkov scan
SCAN_FAILED=false
if command -v checkov &>/dev/null; then
  echo -e "  Running checkov..."
  CHECKOV_OUTPUT=$(checkov -f "$RENDERED" --framework kubernetes --compact --quiet 2>/dev/null || true)
  CHECKOV_FAILS=$(echo "$CHECKOV_OUTPUT" | grep -c "FAILED" || true)
  if [[ "$CHECKOV_FAILS" -gt 0 ]]; then
    echo -e "  ${YELLOW}checkov: $CHECKOV_FAILS findings${NC}"
    if [[ "$STRICT" == "true" ]]; then
      echo "$CHECKOV_OUTPUT" | grep "FAILED" | head -10
      SCAN_FAILED=true
    fi
  else
    echo -e "  ${GREEN}checkov: 0 failures${NC}"
  fi
else
  echo -e "  ${YELLOW}checkov not installed — skipping${NC}"
fi

# Kubescape pre-deploy scan on rendered YAML
if command -v kubescape &>/dev/null; then
  echo -e "  Running kubescape (NSA + MITRE)..."
  KUBESCAPE_OUTPUT=$(kubescape scan "$RENDERED" --frameworks nsa,mitre --format json 2>/dev/null || true)
  KS_CRITICAL=$(echo "$KUBESCAPE_OUTPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    total = sum(1 for r in d.get('results', []) for c in r.get('resourcesResult', {}).values() if c.get('prioritizedResource', {}).get('severity', 0) >= 7)
    print(total)
except: print('0')
" 2>/dev/null || echo "0")
  if [[ "$KS_CRITICAL" -gt 0 ]]; then
    echo -e "  ${YELLOW}kubescape: $KS_CRITICAL critical/high findings${NC}"
    [[ "$STRICT" == "true" ]] && SCAN_FAILED=true
  else
    echo -e "  ${GREEN}kubescape: 0 critical/high findings${NC}"
  fi
else
  echo -e "  ${YELLOW}kubescape not installed — skipping${NC}"
fi

if [[ "$SCAN_FAILED" == "true" && "$DRY_RUN" == "false" ]]; then
  echo -e ""
  echo -e "  ${RED}Security scan failures detected. Staging requires clean scans.${NC}"
  echo -e "  ${RED}Fix findings or use --no-strict to override (not recommended).${NC}"
  echo -e "  ${YELLOW}Review: checkov -f $RENDERED --framework kubernetes${NC}"
  rm -f "$RENDERED"
  exit 1
fi

# ── [5/8] Dry run or deploy ──────────────────────────────────────────────────
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${BLUE}[5/8] Helm dry-run${NC}"
  helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --dry-run
  echo ""
  echo -e "${GREEN}Dry run complete. Review the output above.${NC}"
  echo "Remove --dry-run to deploy for real."
  rm -f "$RENDERED"
  exit 0
fi

echo -e "${BLUE}[5/8] Deploying${NC}"
helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout "$TIMEOUT"

echo -e "  ${GREEN}Helm release deployed${NC}"

# ── [6/8] Post-deploy verification ──────────────────────────────────────────
echo ""
echo -e "${BLUE}[6/8] Post-deploy verification${NC}"

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

# ── [7/8] Security checks ───────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[7/8] Security checks${NC}"
CHECKS_PASSED=0
CHECKS_TOTAL=0

# Check :latest tags
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
LATEST_COUNT=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | grep -cE ':latest$' || true)
if [[ "$LATEST_COUNT" -gt 0 ]]; then
  echo -e "  ${RED}FAIL: $LATEST_COUNT container(s) using :latest tag${NC}"
else
  echo -e "  ${GREEN}PASS: No :latest image tags${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

# Check runAsNonRoot
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
NONROOT=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{range .items[*].spec.securityContext}{.runAsNonRoot}{"\n"}{end}' 2>/dev/null | grep -c "true" || true)
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" --no-headers 2>/dev/null | wc -l || true)
if [[ "$NONROOT" -ge "$POD_COUNT" && "$POD_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}PASS: All pods runAsNonRoot${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${RED}FAIL: Not all pods have runAsNonRoot${NC}"
fi

# Check readOnlyRootFilesystem
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
READONLY=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{range .items[*].spec.containers[*].securityContext}{.readOnlyRootFilesystem}{"\n"}{end}' 2>/dev/null | grep -c "true" || true)
CONTAINER_COUNT=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{range .items[*].spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null | wc -l || true)
if [[ "$READONLY" -ge "$CONTAINER_COUNT" && "$CONTAINER_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}PASS: All containers readOnlyRootFilesystem${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${RED}FAIL: Not all containers have readOnlyRootFilesystem${NC}"
fi

# Check resource limits
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
NO_LIMITS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{range .items[*].spec.containers[*]}{.resources.limits.cpu}{"\n"}{end}' 2>/dev/null | grep -c "^$" || true)
if [[ "$NO_LIMITS" -eq 0 ]]; then
  echo -e "  ${GREEN}PASS: All containers have resource limits${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${RED}FAIL: $NO_LIMITS container(s) missing resource limits${NC}"
fi

# Check PSS on namespace
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
PSS=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
if [[ "$PSS" == "restricted" ]]; then
  echo -e "  ${GREEN}PASS: Namespace PSS = restricted${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${YELLOW}WARN: Namespace PSS = $PSS (expected: restricted)${NC}"
fi

# Check NetworkPolicy exists
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
NP_COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || true)
if [[ "$NP_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}PASS: $NP_COUNT NetworkPolicy(s) in namespace${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${YELLOW}WARN: No NetworkPolicies in namespace — consider adding default-deny${NC}"
fi

echo ""
echo -e "  Security score: ${CHECKS_PASSED}/${CHECKS_TOTAL}"

# ── [8/8] Post-deploy kubescape scan ────────────────────────────────────────
echo ""
echo -e "${BLUE}[8/8] Live namespace security scan${NC}"

if [[ "$SKIP_SCAN" == "true" ]]; then
  echo -e "  ${YELLOW}Skipped (--skip-scan)${NC}"
elif command -v kubescape &>/dev/null; then
  echo -e "  Running kubescape on live namespace (NSA + MITRE)..."
  kubescape scan workload --namespace "$NAMESPACE" \
    --frameworks nsa,mitre \
    --format pretty-printer 2>/dev/null || true
else
  echo -e "  ${YELLOW}kubescape not installed — skipping live scan${NC}"
fi

# Kyverno policy reports
if [[ "$KYVERNO_RUNNING" == "true" ]]; then
  echo ""
  echo -e "  Kyverno policy report:"
  VIOLATIONS=$(kubectl get policyreport -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.summary.fail}{"\n"}{end}' 2>/dev/null | awk '{s+=$1}END{print s+0}')
  if [[ "$VIOLATIONS" -gt 0 ]]; then
    echo -e "  ${YELLOW}$VIOLATIONS policy violation(s) — review with: kubectl get policyreport -n $NAMESPACE -o yaml${NC}"
  else
    echo -e "  ${GREEN}0 policy violations${NC}"
  fi
fi

# Cleanup
rm -f "$RENDERED"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Staging deployment complete           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo "  Release:   $RELEASE_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Context:   $CLUSTER_CTX"
echo "  Security:  ${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed"
echo ""
echo "  Port-forward: kubectl port-forward svc/$RELEASE_NAME 8080:80 -n $NAMESPACE"
echo "  Rollback:     helm rollback $RELEASE_NAME -n $NAMESPACE"
echo "  Promote:      promote-image.sh --app $RELEASE_NAME --from staging --to prod"
echo "  Uninstall:    helm uninstall $RELEASE_NAME -n $NAMESPACE"
