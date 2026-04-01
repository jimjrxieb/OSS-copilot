#!/usr/bin/env bash
# deploy.sh
# Deploy Falco + falco-exporter runtime security to a Kubernetes cluster.
# Falco-first by default. jsa-infrasec is opt-in via --with-jsa (package 05-JSA-AUTONOMOUS).
#
# Usage:
#   bash deploy.sh
#   bash deploy.sh --with-jsa
#   bash deploy.sh --with-jsa --values 03-templates/deployment-configs/aws-eks.yaml
#   bash deploy.sh --skip-falco        (jsa-infrasec only — requires --with-jsa)
#   bash deploy.sh --dry-run

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
AGENT_DIR="${JSA_AGENT_DIR:-$HOME/linkops-industries/GP-copilot/GP-BEDROCK-AGENTS/jsa-infrasec}"

VALUES_FILE="$PKG_DIR/03-templates/deployment-configs/minimal.yaml"
SKIP_FALCO=false
DEPLOY_JSA=false
DRY_RUN=false
NAMESPACE_JSA="jsa-infrasec"
NAMESPACE_FALCO="falco"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --with-jsa         Also deploy jsa-infrasec (package 05-JSA-AUTONOMOUS)"
  echo "  --values FILE      Helm values file for jsa-infrasec (default: 03-templates/deployment-configs/minimal.yaml)"
  echo "  --skip-falco       Deploy jsa-infrasec only, skip Falco install (requires --with-jsa)"
  echo "  --dry-run          Show what would be deployed, don't apply"
  echo ""
  echo "Examples:"
  echo "  bash deploy.sh                                                  # Falco + falco-exporter"
  echo "  bash deploy.sh --with-jsa                                       # Falco + exporter + jsa-infrasec"
  echo "  bash deploy.sh --with-jsa --values 03-templates/deployment-configs/aws-eks.yaml  # full AWS EKS"
  echo "  bash deploy.sh --dry-run                                        # preview only"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --values)      VALUES_FILE="$2"; shift 2 ;;
    --with-jsa)    DEPLOY_JSA=true; shift ;;
    --skip-falco)  SKIP_FALCO=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --help|-h)     usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

# --skip-falco without --with-jsa makes no sense
if [[ "$SKIP_FALCO" == "true" && "$DEPLOY_JSA" == "false" ]]; then
  echo -e "${RED}ERROR: --skip-falco requires --with-jsa (nothing to deploy otherwise)${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Runtime Security Deployment ===${NC}"
echo "  Falco        : $(if [[ "$SKIP_FALCO" == "false" ]]; then echo "yes"; else echo "skip"; fi)"
echo "  falco-exporter: $(if [[ "$SKIP_FALCO" == "false" ]]; then echo "yes"; else echo "skip"; fi)"
echo "  jsa-infrasec : $(if [[ "$DEPLOY_JSA" == "true" ]]; then echo "yes ($AGENT_DIR)"; else echo "no (use --with-jsa to enable)"; fi)"
echo "  Dry run      : $DRY_RUN"
echo ""

# Verify cluster access
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster. Check kubectl context.${NC}"
  exit 1
fi
CLUSTER_CTX=$(kubectl config current-context)
echo -e "${GREEN}Cluster:${NC} $CLUSTER_CTX"
echo ""

# Verify jsa-infrasec manifests exist (only if deploying jsa)
if [[ "$DEPLOY_JSA" == "true" ]]; then
  if [[ ! -f "$AGENT_DIR/jsa-infrasec-deployment.yaml" ]]; then
    echo -e "${RED}ERROR: jsa-infrasec deployment manifest not found at:${NC}"
    echo "  $AGENT_DIR/jsa-infrasec-deployment.yaml"
    echo ""
    echo "Clone GP-Copilot first:"
    echo "  git clone https://github.com/jimjrxieb/GP-Copilot ~/linkops-industries/GP-copilot"
    exit 1
  fi
fi

dry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} $*"
  else
    eval "$*"
  fi
}

# ── Step 1: Install Falco ──────────────────────────────────────────────────
if [[ "$SKIP_FALCO" == "false" ]]; then
  echo -e "${BLUE}[1/4]${NC} Installing Falco"

  if ! command -v helm &>/dev/null; then
    echo -e "${RED}ERROR: helm not found. Install: https://helm.sh/docs/intro/install/${NC}"
    exit 1
  fi

  # Build httpOutput flags based on whether jsa-infrasec is being deployed
  if [[ "$DEPLOY_JSA" == "true" ]]; then
    HTTP_OUTPUT_FLAGS="--set falco.httpOutput.enabled=true --set falco.httpOutput.url=http://jsa-infrasec.$NAMESPACE_JSA:8000/api/falco"
  else
    HTTP_OUTPUT_FLAGS="--set falco.httpOutput.enabled=false"
  fi

  # Check if already installed
  if helm status falco -n "$NAMESPACE_FALCO" &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  Falco already installed in namespace $NAMESPACE_FALCO — upgrading"
    dry "helm upgrade falco falcosecurity/falco \
      --namespace $NAMESPACE_FALCO \
      --reuse-values \
      --set falco.jsonOutput=true \
      $HTTP_OUTPUT_FLAGS"
  else
    echo -e "  Adding Falco helm repo..."
    dry "helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true"
    dry "helm repo update falcosecurity"

    echo -e "  Installing Falco (eBPF driver)..."
    dry "helm install falco falcosecurity/falco \
      --namespace $NAMESPACE_FALCO \
      --create-namespace \
      --set driver.kind=modern_ebpf \
      --set falco.jsonOutput=true \
      $HTTP_OUTPUT_FLAGS \
      --wait --timeout 5m"
  fi

  if [[ "$DRY_RUN" == "false" ]]; then
    FALCO_PODS=$(kubectl get pods -n "$NAMESPACE_FALCO" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo -e "  ${GREEN}✓${NC}  Falco: $FALCO_PODS pod(s) Running"
  fi
  echo ""

  # ── Step 2: Install falco-exporter ─────────────────────────────────────────
  echo -e "${BLUE}[2/4]${NC} Installing falco-exporter"

  if helm status falco-exporter -n "$NAMESPACE_FALCO" &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  falco-exporter already installed — upgrading"
    dry "helm upgrade falco-exporter falcosecurity/falco-exporter \
      --namespace $NAMESPACE_FALCO \
      --reuse-values"
  else
    echo -e "  Installing falco-exporter (exposes falco_alerts_total for Prometheus)..."
    dry "helm install falco-exporter falcosecurity/falco-exporter \
      --namespace $NAMESPACE_FALCO \
      --wait --timeout 3m"
  fi

  if [[ "$DRY_RUN" == "false" ]]; then
    EXPORTER_PODS=$(kubectl get pods -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco-exporter --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo -e "  ${GREEN}✓${NC}  falco-exporter: $EXPORTER_PODS pod(s) Running"
  fi
  echo ""
else
  echo -e "${BLUE}[1/4]${NC} Skipping Falco (--skip-falco)"
  echo -e "${BLUE}[2/4]${NC} Skipping falco-exporter (--skip-falco)"
  echo ""
fi

# ── Step 3: Deploy jsa-infrasec (opt-in) ─────────────────────────────────
if [[ "$DEPLOY_JSA" == "false" ]]; then
  echo -e "${BLUE}[3/4]${NC} Skipping jsa-infrasec (use --with-jsa to deploy)"
  echo ""
else
  echo -e "${BLUE}[3/4]${NC} Deploying jsa-infrasec"

  # Pick the right deployment YAML
  K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo "")
  DEPLOY_YAML="$AGENT_DIR/jsa-infrasec-deployment.yaml"
  echo -e "  Manifest: $DEPLOY_YAML"

  dry "kubectl apply -f $DEPLOY_YAML"

  if [[ "$DRY_RUN" == "false" ]]; then
    echo -e "  Waiting for jsa-infrasec pod to be ready..."
    kubectl wait pod \
      -n "$NAMESPACE_JSA" \
      -l app=jsa-infrasec \
      --for=condition=Ready \
      --timeout=120s 2>/dev/null || echo -e "  ${YELLOW}⚠${NC}  Pod not ready in 120s — check: kubectl get pods -n $NAMESPACE_JSA"

    JSA_PODS=$(kubectl get pods -n "$NAMESPACE_JSA" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    echo -e "  ${GREEN}✓${NC}  jsa-infrasec: $JSA_PODS pod(s) Running"
  fi
  echo ""
fi

# ── Step 4: Verify ─────────────────────────────────────────────────────────
echo -e "${BLUE}[4/4]${NC} Verification"

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "  ${YELLOW}[DRY RUN]${NC} would run health-check.sh"
else
  if [[ -x "$SCRIPT_DIR/health-check.sh" ]]; then
    bash "$SCRIPT_DIR/health-check.sh"
  else
    kubectl get pods -n "$NAMESPACE_FALCO" 2>/dev/null || true
    if [[ "$DEPLOY_JSA" == "true" ]]; then
      kubectl get pods -n "$NAMESPACE_JSA" 2>/dev/null || true
    fi
  fi
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Next steps:"
if [[ "$SKIP_FALCO" == "false" ]]; then
  echo "  1. Watch Falco logs:  kubectl logs -n $NAMESPACE_FALCO -l app.kubernetes.io/name=falco -f"
  echo "  2. Check health:      bash $(dirname "$0")/health-check.sh"
  echo "  3. After 1 week — tune Falco rules:"
  echo "     bash $(dirname "$0")/tune-falco.sh --add-allowlist $PKG_DIR/01-detection/falco-rules/allowlist.yaml"
fi
if [[ "$DEPLOY_JSA" == "true" ]]; then
  echo "  4. Watch jsa-infrasec: kubectl logs -n $NAMESPACE_JSA deploy/jsa-infrasec -f"
fi
if [[ "$DEPLOY_JSA" == "false" ]]; then
  echo ""
  echo "To add autonomous agent monitoring later:"
  echo "  bash $(dirname "$0")/deploy.sh --with-jsa"
fi
echo ""
