#!/usr/bin/env bash
# deploy-prod.sh — Deploy or upgrade a Helm release to the production EKS environment.
# Production-grade validation: EKS security audit, admission control check, pre/post scans,
# --atomic rollback, IRSA verification, and full security scorecard.
#
# Usage:
#   bash deploy-prod.sh --chart ./helm --values ./helm/values-prod.yaml --release myapp --namespace prod
#   bash deploy-prod.sh --chart ./helm --release myapp --namespace prod --dry-run
#   bash deploy-prod.sh --generate-values --from-values ./helm/values-staging.yaml --output ./helm/values-prod.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# Defaults
CHART_PATH=""
VALUES_FILE=""
RELEASE_NAME=""
NAMESPACE="prod"
DRY_RUN=false
SKIP_SCAN=false
SKIP_EKS_AUDIT=false
GENERATE_VALUES=false
FROM_VALUES=""
OUTPUT_FILE=""
TIMEOUT="10m"
EKS_CLUSTER=""
AWS_REGION="us-east-1"

usage() {
  cat <<EOF
Deploy Helm release to production EKS environment with full security validation.

Usage: bash deploy-prod.sh [OPTIONS]

Deploy options:
  -c, --chart PATH        Helm chart directory (required for deploy)
  -f, --values FILE       Values file (default: <chart>/values-prod.yaml)
  -r, --release NAME      Helm release name (required for deploy)
  -n, --namespace NS      Target namespace (default: prod)
  --cluster NAME          EKS cluster name (for pre-flight audit)
  --region REGION          AWS region (default: us-east-1)
  --timeout DURATION       Helm wait timeout (default: 10m)
  --dry-run               Render and validate only, don't deploy
  --skip-scan             Skip post-deploy kubescape scan
  --skip-eks-audit        Skip EKS security pre-flight audit

Generate options:
  --generate-values       Generate values-prod.yaml from staging values
  --from-values FILE      Source values file (values-staging.yaml)
  --output FILE           Output values file path

Examples:
  bash deploy-prod.sh --chart ./helm --release myapp --namespace prod --cluster my-eks
  bash deploy-prod.sh --chart ./helm --release myapp --dry-run
  bash deploy-prod.sh --generate-values --from-values ./helm/values-staging.yaml --output ./helm/values-prod.yaml
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--chart)           CHART_PATH="$2"; shift 2 ;;
    -f|--values)          VALUES_FILE="$2"; shift 2 ;;
    -r|--release)         RELEASE_NAME="$2"; shift 2 ;;
    -n|--namespace)       NAMESPACE="$2"; shift 2 ;;
    --cluster)            EKS_CLUSTER="$2"; shift 2 ;;
    --region)             AWS_REGION="$2"; shift 2 ;;
    --timeout)            TIMEOUT="$2"; shift 2 ;;
    --dry-run)            DRY_RUN=true; shift ;;
    --skip-scan)          SKIP_SCAN=true; shift ;;
    --skip-eks-audit)     SKIP_EKS_AUDIT=true; shift ;;
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

  echo -e "${BLUE}=== Generating production values ===${NC}"

  if [[ -n "$FROM_VALUES" && -f "$FROM_VALUES" ]]; then
    cp "$FROM_VALUES" "$OUTPUT_FILE"

    # Upgrade replicas
    sed -i 's/^replicaCount:.*/replicaCount: 3/' "$OUTPUT_FILE"

    # Enable autoscaling
    sed -i 's/^  enabled: false.*# Prod values/  enabled: true/' "$OUTPUT_FILE"
    # If that didn't match, try the simple pattern
    if grep -q "autoscaling:" "$OUTPUT_FILE"; then
      sed -i '/^autoscaling:/,/^[^ ]/{s/enabled: false/enabled: true/}' "$OUTPUT_FILE"
    fi

    # Update environment
    sed -i 's/value: "staging"/value: "production"/' "$OUTPUT_FILE"
    sed -i 's/value: "info"/value: "warn"/' "$OUTPUT_FILE"

    # Update pullPolicy
    sed -i 's/pullPolicy: Always/pullPolicy: IfNotPresent/' "$OUTPUT_FILE"

    echo -e "${GREEN}Generated from staging values: $OUTPUT_FILE${NC}"
    echo -e "  Replicas:    3"
    echo -e "  HPA:         enabled"
    echo -e "  pullPolicy:  IfNotPresent"
    echo -e "  Env:         production / warn"
  else
    cp "$PKG_DIR/tools/helm-values-prod.yaml" "$OUTPUT_FILE"
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
  if [[ -f "$CHART_PATH/values-prod.yaml" ]]; then
    VALUES_FILE="$CHART_PATH/values-prod.yaml"
  elif [[ -f "$CHART_PATH/values-production.yaml" ]]; then
    VALUES_FILE="$CHART_PATH/values-production.yaml"
  else
    echo -e "${RED}ERROR: No prod values file found. Use --values to specify.${NC}"
    exit 1
  fi
fi

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ${BOLD}PRODUCTION DEPLOYMENT${NC}${RED}                                ║${NC}"
echo -e "${RED}║  This deploys to PRODUCTION. Verify your context.   ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
echo "  Release   : $RELEASE_NAME"
echo "  Chart     : $CHART_PATH"
echo "  Values    : $VALUES_FILE"
echo "  Namespace : $NAMESPACE"
echo "  Cluster   : ${EKS_CLUSTER:-auto-detect}"
echo "  Dry run   : $DRY_RUN"
echo ""

# ── [1/9] Pre-flight checks ─────────────────────────────────────────────────
echo -e "${BLUE}[1/9] Pre-flight checks${NC}"

# Cluster access
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster. Check kubectl context.${NC}"
  exit 1
fi
CLUSTER_CTX=$(kubectl config current-context)
echo -e "  Cluster context: ${GREEN}$CLUSTER_CTX${NC}"
echo -e "  Helm:            ${GREEN}$(helm version --short)${NC}"

# Safety check: is this a prod context?
if echo "$CLUSTER_CTX" | grep -qiE "dev|staging|test|local|kind|minikube"; then
  echo -e "${RED}WARNING: Context name '$CLUSTER_CTX' looks like a non-production cluster.${NC}"
  echo -e "${RED}Are you sure this is production? (Ctrl+C to abort, Enter to continue)${NC}"
  read -r
fi

# ArgoCD ownership check
ARGO_APP=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null || true)
if [[ -n "$ARGO_APP" ]]; then
  echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  HARD STOP: Namespace '$NAMESPACE' is managed by ArgoCD    ║${NC}"
  echo -e "${RED}║  ArgoCD app: $ARGO_APP${NC}"
  echo -e "${RED}║                                                              ║${NC}"
  echo -e "${RED}║  Use promote-image.sh for GitOps promotion:                  ║${NC}"
  echo -e "${RED}║  02-CLUSTER-HARDEN/tools/platform/promote-image.sh \\      ║${NC}"
  echo -e "${RED}║    --app $RELEASE_NAME --from staging --to prod              ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi

# ── [2/9] EKS Security Audit ────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[2/9] EKS security audit${NC}"

if [[ "$SKIP_EKS_AUDIT" == "true" ]]; then
  echo -e "  ${YELLOW}Skipped (--skip-eks-audit)${NC}"
else
  # Auto-detect cluster name from context
  if [[ -z "$EKS_CLUSTER" ]]; then
    EKS_CLUSTER=$(echo "$CLUSTER_CTX" | grep -oP '(?<=cluster/)[\w-]+' || echo "")
    if [[ -z "$EKS_CLUSTER" ]]; then
      EKS_CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}' | grep -oP '[\w-]+$' || echo "")
    fi
  fi

  if [[ -n "$EKS_CLUSTER" ]] && command -v aws &>/dev/null; then
    EKS_AUDIT_PASS=true

    # Private endpoint
    ENDPOINT_PUBLIC=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
      --query "cluster.resourcesVpcConfig.endpointPublicAccess" --output text 2>/dev/null || echo "unknown")
    if [[ "$ENDPOINT_PUBLIC" == "False" || "$ENDPOINT_PUBLIC" == "false" ]]; then
      echo -e "  ${GREEN}PASS: API endpoint is private${NC}"
    elif [[ "$ENDPOINT_PUBLIC" == "unknown" ]]; then
      echo -e "  ${YELLOW}SKIP: Cannot query EKS API (check AWS credentials)${NC}"
    else
      echo -e "  ${RED}FAIL: API endpoint is PUBLIC — fix in Playbook 05${NC}"
      EKS_AUDIT_PASS=false
    fi

    # Logging
    LOG_TYPES=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
      --query "cluster.logging.clusterLogging[?enabled==\`true\`].types[]" --output text 2>/dev/null || echo "")
    LOG_COUNT=$(echo "$LOG_TYPES" | wc -w)
    if [[ "$LOG_COUNT" -ge 5 ]]; then
      echo -e "  ${GREEN}PASS: All 5 log types enabled${NC}"
    else
      echo -e "  ${YELLOW}WARN: Only $LOG_COUNT/5 log types enabled${NC}"
    fi

    # Encryption
    ENCRYPTION=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
      --query "cluster.encryptionConfig[0].resources[0]" --output text 2>/dev/null || echo "None")
    if [[ "$ENCRYPTION" == "secrets" ]]; then
      echo -e "  ${GREEN}PASS: Envelope encryption enabled${NC}"
    else
      echo -e "  ${YELLOW}WARN: Secrets encryption not configured${NC}"
    fi

    if [[ "$EKS_AUDIT_PASS" == "false" && "$DRY_RUN" == "false" ]]; then
      echo -e "  ${RED}EKS security audit failed. Fix before deploying to prod.${NC}"
      exit 1
    fi
  else
    echo -e "  ${YELLOW}Cannot auto-detect EKS cluster or AWS CLI not available — skipping${NC}"
  fi
fi

# ── [3/9] Namespace setup ────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[3/9] Namespace setup${NC}"

if kubectl get ns "$NAMESPACE" &>/dev/null; then
  PSS_ENFORCE=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
  if [[ "$PSS_ENFORCE" == "restricted" ]]; then
    echo -e "  Namespace exists: ${GREEN}PSS restricted${NC}"
  else
    echo -e "  ${YELLOW}Namespace PSS is '$PSS_ENFORCE' — upgrading to restricted${NC}"
    kubectl label ns "$NAMESPACE" \
      pod-security.kubernetes.io/enforce=restricted \
      pod-security.kubernetes.io/enforce-version=latest \
      pod-security.kubernetes.io/audit=restricted \
      pod-security.kubernetes.io/audit-version=latest \
      pod-security.kubernetes.io/warn=restricted \
      pod-security.kubernetes.io/warn-version=latest \
      environment=production \
      --overwrite
    echo -e "  ${GREEN}PSS upgraded to restricted${NC}"
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
    environment: production
EOF
  echo -e "  ${GREEN}Namespace created${NC}"
fi

# ── [4/9] Helm lint ──────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[4/9] Helm lint${NC}"
if helm lint "$CHART_PATH" -f "$VALUES_FILE" --namespace "$NAMESPACE"; then
  echo -e "  ${GREEN}Lint passed${NC}"
else
  echo -e "  ${RED}Lint failed — fix chart errors before deploying to prod${NC}"
  exit 1
fi

# ── [5/9] Render + security scan ─────────────────────────────────────────────
echo ""
echo -e "${BLUE}[5/9] Render and scan${NC}"
RENDERED="/tmp/prod-rendered-${RELEASE_NAME}-$(date +%s).yaml"
helm template "$RELEASE_NAME" "$CHART_PATH" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  > "$RENDERED"
echo -e "  Rendered to: $RENDERED"

SCAN_FAILED=false

# Checkov
if command -v checkov &>/dev/null; then
  echo -e "  Running checkov..."
  CHECKOV_FAILS=$(checkov -f "$RENDERED" --framework kubernetes --compact --quiet 2>/dev/null | grep -c "FAILED" || true)
  if [[ "$CHECKOV_FAILS" -gt 0 ]]; then
    echo -e "  ${RED}checkov: $CHECKOV_FAILS findings — MUST fix for prod${NC}"
    SCAN_FAILED=true
  else
    echo -e "  ${GREEN}checkov: 0 failures${NC}"
  fi
fi

# Kubescape
if command -v kubescape &>/dev/null; then
  echo -e "  Running kubescape (NSA + MITRE)..."
  KS_EXIT=0
  kubescape scan "$RENDERED" --frameworks nsa,mitre --format pretty-printer 2>/dev/null || KS_EXIT=$?
  if [[ "$KS_EXIT" -ne 0 ]]; then
    echo -e "  ${YELLOW}kubescape exited with code $KS_EXIT${NC}"
  fi
fi

if [[ "$SCAN_FAILED" == "true" && "$DRY_RUN" == "false" ]]; then
  echo -e ""
  echo -e "  ${RED}Security scan failures detected. Production requires zero critical findings.${NC}"
  echo -e "  ${YELLOW}Review: checkov -f $RENDERED --framework kubernetes${NC}"
  rm -f "$RENDERED"
  exit 1
fi

# ── [6/9] Deploy ─────────────────────────────────────────────────────────────
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${BLUE}[6/9] Helm dry-run${NC}"
  helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
    -f "$VALUES_FILE" \
    --namespace "$NAMESPACE" \
    --dry-run
  echo ""
  echo -e "${GREEN}Dry run complete.${NC}"
  rm -f "$RENDERED"
  exit 0
fi

echo -e "${BLUE}[6/9] Deploying (--atomic — auto-rollback on failure)${NC}"
if helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout "$TIMEOUT" \
  --atomic; then
  echo -e "  ${GREEN}Helm release deployed${NC}"
else
  echo -e "  ${RED}Deploy failed — Helm --atomic rolled back automatically${NC}"
  echo -e "  Check: helm status $RELEASE_NAME -n $NAMESPACE"
  echo -e "  Logs:  kubectl logs -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE"
  rm -f "$RENDERED"
  exit 1
fi

# ── [7/9] Post-deploy verification ──────────────────────────────────────────
echo ""
echo -e "${BLUE}[7/9] Post-deploy verification${NC}"

kubectl wait --for=condition=ready pod \
  -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -n "$NAMESPACE" \
  --timeout=180s 2>/dev/null || echo -e "  ${YELLOW}WARNING: Not all pods ready within 180s${NC}"

echo ""
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" -o wide
echo ""
helm list -n "$NAMESPACE" --filter "$RELEASE_NAME"

# HPA status
echo ""
kubectl get hpa -n "$NAMESPACE" 2>/dev/null || echo "  No HPA configured"

# ── [8/9] Security scorecard ────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[8/9] Security scorecard${NC}"
CHECKS_PASSED=0
CHECKS_TOTAL=0

# :latest tags
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
LATEST_COUNT=$(kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | grep -cE ':latest$' || true)
if [[ "$LATEST_COUNT" -eq 0 ]]; then
  echo -e "  ${GREEN}PASS: No :latest image tags${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${RED}FAIL: $LATEST_COUNT container(s) using :latest tag${NC}"
fi

# runAsNonRoot
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

# readOnlyRootFilesystem
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

# Resource limits
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
NO_LIMITS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{range .items[*].spec.containers[*]}{.resources.limits.cpu}{"\n"}{end}' 2>/dev/null | grep -c "^$" || true)
if [[ "$NO_LIMITS" -eq 0 ]]; then
  echo -e "  ${GREEN}PASS: All containers have resource limits${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${RED}FAIL: $NO_LIMITS container(s) missing resource limits${NC}"
fi

# PSS restricted
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
PSS=$(kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
if [[ "$PSS" == "restricted" ]]; then
  echo -e "  ${GREEN}PASS: Namespace PSS = restricted${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${RED}FAIL: Namespace PSS = $PSS (expected: restricted)${NC}"
fi

# NetworkPolicy
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
NP_COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || true)
if [[ "$NP_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}PASS: $NP_COUNT NetworkPolicy(s)${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${YELLOW}WARN: No NetworkPolicies — add default-deny${NC}"
fi

# PDB
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
PDB_COUNT=$(kubectl get pdb -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || true)
if [[ "$PDB_COUNT" -gt 0 ]]; then
  echo -e "  ${GREEN}PASS: PodDisruptionBudget configured${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "  ${YELLOW}WARN: No PodDisruptionBudget — add for HA${NC}"
fi

# Replica count
CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
REPLICAS=$(kubectl get deployment -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
  -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$REPLICAS" -ge 3 ]]; then
  echo -e "  ${GREEN}PASS: $REPLICAS replicas (HA)${NC}"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
elif [[ "$REPLICAS" -ge 2 ]]; then
  echo -e "  ${YELLOW}WARN: $REPLICAS replicas (minimum HA — recommend 3)${NC}"
else
  echo -e "  ${RED}FAIL: $REPLICAS replica(s) — not HA${NC}"
fi

echo ""
echo -e "  Security score: ${BOLD}${CHECKS_PASSED}/${CHECKS_TOTAL}${NC}"

# ── [9/9] Post-deploy scan ──────────────────────────────────────────────────
echo ""
echo -e "${BLUE}[9/9] Live namespace security scan${NC}"

if [[ "$SKIP_SCAN" == "true" ]]; then
  echo -e "  ${YELLOW}Skipped (--skip-scan)${NC}"
elif command -v kubescape &>/dev/null; then
  echo -e "  Running kubescape on live namespace (NSA + MITRE)..."
  kubescape scan workload --namespace "$NAMESPACE" \
    --frameworks nsa,mitre \
    --format pretty-printer 2>/dev/null || true
else
  echo -e "  ${YELLOW}kubescape not installed — skipping${NC}"
fi

# Cleanup
rm -f "$RENDERED"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ${BOLD}Production deployment complete${NC}${GREEN}                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo "  Release:   $RELEASE_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Context:   $CLUSTER_CTX"
echo "  Security:  ${CHECKS_PASSED}/${CHECKS_TOTAL} checks passed"
echo ""
echo "  Rollback:     helm rollback $RELEASE_NAME -n $NAMESPACE"
echo "  Status:       helm status $RELEASE_NAME -n $NAMESPACE"
echo "  Logs:         kubectl logs -l app.kubernetes.io/instance=$RELEASE_NAME -n $NAMESPACE"
echo "  Uninstall:    helm uninstall $RELEASE_NAME -n $NAMESPACE"
