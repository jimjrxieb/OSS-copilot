#!/usr/bin/env bash
# deploy-argocd-hooks.sh
# Deploy ArgoCD integration: AppProject, Falco Application CRD, sync-fail alerts.
# Hook Jobs (PreSync/PostSync) are templates — they deploy WITH each Application.
#
# Usage:
#   bash deploy-argocd-hooks.sh                        # Full deployment
#   bash deploy-argocd-hooks.sh --skip-falco-app       # Skip Falco Application CRD
#   bash deploy-argocd-hooks.sh --dry-run
#   bash deploy-argocd-hooks.sh --policies-configmap    # Also create conftest policies ConfigMap

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
ARGOCD_TEMPLATES="$PKG_DIR/03-templates/argocd"
CONSULTING_DIR="$(dirname "$PKG_DIR")"

SKIP_FALCO_APP=false
DRY_RUN=false
DEPLOY_POLICIES_CM=false

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --skip-falco-app      Skip Falco Application CRD (Falco already managed by Helm)"
  echo "  --policies-configmap  Create conftest policies ConfigMap for PreSync gate"
  echo "  --dry-run             Show what would be deployed"
  echo ""
  echo "What gets deployed:"
  echo "  1. AppProject 'runtime-security' — scopes allowed namespaces and repos"
  echo "  2. Falco Application CRD — ArgoCD manages Falco lifecycle (sync wave -2)"
  echo "  3. falco-exporter Application CRD — Prometheus metrics (sync wave -1)"
  echo "  4. Sync failure PrometheusRule alerts — 6 alert rules"
  echo "  5. (optional) conftest policies ConfigMap — for PreSync security gate"
  echo ""
  echo "Note: PreSync and PostSync hook Jobs are templates, not standalone resources."
  echo "      Include them in your Application's manifest directory. See:"
  echo "      $ARGOCD_TEMPLATES/README.md"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-falco-app)      SKIP_FALCO_APP=true; shift ;;
    --policies-configmap)  DEPLOY_POLICIES_CM=true; shift ;;
    --dry-run)             DRY_RUN=true; shift ;;
    --help|-h)             usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

dry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} $*"
  else
    eval "$*"
  fi
}

# ── Preflight ───────────────────────────────────────────────────────────
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster.${NC}"
  exit 1
fi

# Verify ArgoCD is installed
if ! kubectl get namespace argocd &>/dev/null; then
  echo -e "${RED}ERROR: ArgoCD namespace not found.${NC}"
  echo "Install ArgoCD first:"
  echo "  bash 02-CLUSTER-HARDEN/tools/platform/setup-argocd.sh"
  exit 1
fi

ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c Running || echo "0")
if [[ "$ARGOCD_PODS" -lt 1 ]]; then
  echo -e "${RED}ERROR: No running ArgoCD pods found. Is ArgoCD healthy?${NC}"
  echo "  kubectl get pods -n argocd"
  exit 1
fi

echo ""
echo -e "${BLUE}=== ArgoCD Integration Deployment ===${NC}"
echo "  Falco Application : $(if [[ "$SKIP_FALCO_APP" == "false" ]]; then echo "yes"; else echo "skip"; fi)"
echo "  Policies ConfigMap: $(if [[ "$DEPLOY_POLICIES_CM" == "true" ]]; then echo "yes"; else echo "no"; fi)"
echo "  Dry run           : $DRY_RUN"
echo "  Cluster           : $(kubectl config current-context)"
echo "  ArgoCD pods       : $ARGOCD_PODS running"
echo ""

STEP=1
TOTAL=3
if [[ "$SKIP_FALCO_APP" == "false" ]]; then TOTAL=$((TOTAL + 1)); fi
if [[ "$DEPLOY_POLICIES_CM" == "true" ]]; then TOTAL=$((TOTAL + 1)); fi

# ── Step 1: Deploy AppProject ───────────────────────────────────────────
echo -e "${BLUE}[$STEP/$TOTAL]${NC} Creating AppProject 'runtime-security'"

if kubectl get appproject runtime-security -n argocd &>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC}  AppProject already exists — updating"
fi

dry "kubectl apply -f $ARGOCD_TEMPLATES/runtime-appproject.yaml"

if [[ "$DRY_RUN" == "false" ]]; then
  echo -e "  ${GREEN}✓${NC}  AppProject 'runtime-security' applied"
fi
echo ""
STEP=$((STEP + 1))

# ── Step 2: Deploy Falco Application CRD ────────────────────────────────
if [[ "$SKIP_FALCO_APP" == "false" ]]; then
  echo -e "${BLUE}[$STEP/$TOTAL]${NC} Deploying Falco Application CRD (sync wave -2)"

  if kubectl get application falco -n argocd &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  Falco Application already exists — updating"
  fi

  dry "kubectl apply -f $ARGOCD_TEMPLATES/falco-application.yaml"

  if [[ "$DRY_RUN" == "false" ]]; then
    echo -e "  ${GREEN}✓${NC}  Falco Application CRD applied"
    echo -e "  ${GREEN}✓${NC}  falco-exporter Application CRD applied"
    echo -e "  ArgoCD will now manage Falco lifecycle (self-heal + auto-prune)"
  fi
  echo ""
  STEP=$((STEP + 1))
fi

# ── Step 3: Deploy sync-fail alerts ────────────────────────────────────
echo -e "${BLUE}[$STEP/$TOTAL]${NC} Deploying ArgoCD sync-fail PrometheusRule alerts"

dry "kubectl apply -f $ARGOCD_TEMPLATES/sync-fail-alerts.yaml"

if [[ "$DRY_RUN" == "false" ]]; then
  echo -e "  ${GREEN}✓${NC}  6 alert rules deployed to monitoring namespace"
fi
echo ""
STEP=$((STEP + 1))

# ── Step 4: Create conftest policies ConfigMap (optional) ───────────────
if [[ "$DEPLOY_POLICIES_CM" == "true" ]]; then
  echo -e "${BLUE}[$STEP/$TOTAL]${NC} Creating conftest policies ConfigMap"

  CONFTEST_POLICY="$CONSULTING_DIR/01-APP-SEC/scanning-configs/conftest-policy.rego"

  if [[ ! -f "$CONFTEST_POLICY" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  conftest-policy.rego not found at $CONFTEST_POLICY — skipping"
  else
    dry "kubectl create configmap conftest-policies \
      --from-file=policy.rego=$CONFTEST_POLICY \
      --namespace argocd \
      --dry-run=client -o yaml | kubectl apply -f -"

    if [[ "$DRY_RUN" == "false" ]]; then
      echo -e "  ${GREEN}✓${NC}  conftest-policies ConfigMap created in argocd namespace"
    fi
  fi
  echo ""
  STEP=$((STEP + 1))
fi

# ── Step 5: Verify ──────────────────────────────────────────────────────
echo -e "${BLUE}[$STEP/$TOTAL]${NC} Verification"

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "  ${YELLOW}[DRY RUN]${NC} Would verify AppProject + Applications"
else
  echo ""
  echo "  AppProject:"
  kubectl get appproject runtime-security -n argocd -o jsonpath='    {.metadata.name} — {.spec.description}' 2>/dev/null && echo "" || echo "    Not found"

  if [[ "$SKIP_FALCO_APP" == "false" ]]; then
    echo ""
    echo "  Applications:"
    kubectl get application -n argocd -l managed-by=gp-copilot \
      -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,WAVE:.metadata.annotations.argocd\.argoproj\.io/sync-wave' 2>/dev/null || echo "    No applications found yet"
  fi

  echo ""
  echo "  Alert rules:"
  kubectl get prometheusrule argocd-sync-alerts -n monitoring --no-headers 2>/dev/null && echo "" || echo "    Not found (is prometheus-operator installed?)"
fi

echo ""
echo -e "${GREEN}=== ArgoCD Integration Deployed ===${NC}"
echo ""
echo "What's active now:"
echo "  - AppProject 'runtime-security' scopes namespaces: falco, jsa-infrasec, gp-security, monitoring"
if [[ "$SKIP_FALCO_APP" == "false" ]]; then
  echo "  - Falco managed by ArgoCD (sync wave -2, deploys before app workloads)"
  echo "  - falco-exporter managed by ArgoCD (sync wave -1)"
fi
echo "  - 6 Prometheus alerts for sync failures, stuck syncs, deploying without Falco"
echo ""
echo "To add PreSync/PostSync hooks to your Applications:"
echo "  1. Copy 03-templates/argocd/pre-sync-security-gate.yaml into your app's manifest dir"
echo "  2. Copy 03-templates/argocd/post-sync-runtime-verify.yaml into your app's manifest dir"
echo "  3. Replace {{ .Release.Namespace }} with your app's namespace"
echo "  4. ArgoCD picks up the hooks automatically via annotations"
echo ""
echo "See: $ARGOCD_TEMPLATES/README.md"
echo ""
