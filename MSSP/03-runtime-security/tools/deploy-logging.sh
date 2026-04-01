#!/usr/bin/env bash
# deploy-logging.sh
# Deploy log aggregation: Fluent Bit (collector) + Loki (backend).
#
# Usage:
#   bash deploy-logging.sh                           # Fluent Bit + Loki (default)
#   bash deploy-logging.sh --backend loki            # Explicit backend
#   bash deploy-logging.sh --collector-only          # Fluent Bit only (BYO backend)
#   bash deploy-logging.sh --dry-run

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES="$PKG_DIR/03-templates/observability"
MONITORING="$PKG_DIR/04-monitoring"

BACKEND="loki"
COLLECTOR_ONLY=false
DRY_RUN=false
NAMESPACE="logging"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --backend <loki>       Log storage backend (default: loki)"
  echo "  --collector-only       Deploy Fluent Bit only (BYO backend)"
  echo "  --dry-run              Show what would be deployed"
  echo ""
  echo "Examples:"
  echo "  bash deploy-logging.sh                     # Full stack"
  echo "  bash deploy-logging.sh --collector-only    # Fluent Bit only (e.g., CloudWatch output)"
  echo "  bash deploy-logging.sh --dry-run           # Preview"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)        BACKEND="$2"; shift 2 ;;
    --collector-only) COLLECTOR_ONLY=true; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --help|-h)        usage; exit 0 ;;
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

if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster.${NC}"
  exit 1
fi

if ! command -v helm &>/dev/null; then
  echo -e "${RED}ERROR: helm required.${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Log Aggregation Deployment ===${NC}"
echo "  Collector      : Fluent Bit"
echo "  Backend        : $(if [[ "$COLLECTOR_ONLY" == "true" ]]; then echo "none (collector only)"; else echo "$BACKEND"; fi)"
echo "  Namespace      : $NAMESPACE"
echo "  Dry run        : $DRY_RUN"
echo "  Cluster        : $(kubectl config current-context)"
echo ""

STEP=1
TOTAL=4
if [[ "$COLLECTOR_ONLY" == "true" ]]; then TOTAL=3; fi

# ── Step 1: Create namespace ──────────────────────────────────────────
echo -e "${BLUE}[$STEP/$TOTAL]${NC} Creating namespace"
dry "kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
echo ""
STEP=$((STEP + 1))

# ── Step 2: Deploy Loki (backend) ─────────────────────────────────────
if [[ "$COLLECTOR_ONLY" == "false" ]]; then
  echo -e "${BLUE}[$STEP/$TOTAL]${NC} Deploying Loki"

  dry "helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true"
  dry "helm repo update grafana"

  if helm status loki -n "$NAMESPACE" &>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC}  Loki already installed — upgrading"
    dry "helm upgrade loki grafana/loki -n $NAMESPACE -f $TEMPLATES/loki-values.yaml"
  else
    dry "helm install loki grafana/loki -n $NAMESPACE -f $TEMPLATES/loki-values.yaml --wait --timeout 5m"
  fi

  if [[ "$DRY_RUN" == "false" ]]; then
    LOKI_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=loki --no-headers 2>/dev/null | grep -c Running || echo "0")
    echo -e "  ${GREEN}✓${NC}  Loki: $LOKI_PODS pod(s) Running"
  fi
  echo ""
  STEP=$((STEP + 1))
fi

# ── Step 3: Deploy Fluent Bit ─────────────────────────────────────────
echo -e "${BLUE}[$STEP/$TOTAL]${NC} Deploying Fluent Bit (DaemonSet)"

dry "helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null || true"
dry "helm repo update fluent"

if helm status fluent-bit -n "$NAMESPACE" &>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC}  Fluent Bit already installed — upgrading"
  dry "helm upgrade fluent-bit fluent/fluent-bit -n $NAMESPACE -f $TEMPLATES/fluent-bit-values.yaml"
else
  dry "helm install fluent-bit fluent/fluent-bit -n $NAMESPACE -f $TEMPLATES/fluent-bit-values.yaml --wait --timeout 3m"
fi

if [[ "$DRY_RUN" == "false" ]]; then
  FB_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit --no-headers 2>/dev/null | grep -c Running || echo "0")
  NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "?")
  echo -e "  ${GREEN}✓${NC}  Fluent Bit: $FB_PODS/$NODES pods Running"

  # Verify DaemonSet coverage
  DESIRED=$(kubectl get ds -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo "?")
  READY=$(kubectl get ds -n "$NAMESPACE" -l app.kubernetes.io/name=fluent-bit -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo "?")
  if [[ "$DESIRED" != "$READY" ]]; then
    echo -e "  ${YELLOW}⚠${NC}  DaemonSet: $READY/$DESIRED ready — some nodes missing coverage"
  fi
fi
echo ""
STEP=$((STEP + 1))

# ── Step 4: Deploy monitoring ─────────────────────────────────────────
echo -e "${BLUE}[$STEP/$TOTAL]${NC} Deploying log alerts and dashboard"

dry "kubectl apply -f $MONITORING/log-alerts.yaml"

dry "kubectl create configmap grafana-log-dashboard \
  --from-file=$MONITORING/log-dashboard.json \
  --namespace monitoring \
  --dry-run=client -o yaml | kubectl apply -f -"
dry "kubectl label configmap grafana-log-dashboard grafana_dashboard=1 --namespace monitoring --overwrite"

echo ""
echo -e "${GREEN}=== Log Aggregation Deployed ===${NC}"
echo ""
echo "Fluent Bit collects logs from:"
echo "  - All containers:  /var/log/containers/*.log"
echo "  - Falco events:    /var/log/falco/events.log"
echo ""
if [[ "$COLLECTOR_ONLY" == "false" ]]; then
  echo "Query logs in Grafana:"
  echo "  Add Loki datasource → http://loki.$NAMESPACE:3100"
  echo ""
  echo "LogQL examples:"
  echo "  {namespace=\"payments\"}                           # All logs from payments namespace"
  echo "  {namespace=\"payments\"} |= \"error\"                # Error logs"
  echo "  {source=\"falco\"} | json | priority=\"Critical\"    # Critical Falco events"
  echo "  rate({namespace=\"payments\"} |= \"error\" [5m])     # Error rate"
fi
echo ""
echo "Dashboard: Grafana → 'Log Aggregation Pipeline'"
echo ""
