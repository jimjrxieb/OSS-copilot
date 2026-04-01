#!/usr/bin/env bash
# =============================================================================
# isolate-pod.sh — Quarantine a potentially compromised pod
# =============================================================================
# Implements: CAPABILITIES.md Responder #3 (Pod Isolator)
# Rank: C (JADE approval required when automated; manual use = human decision)
#
# Applies a deny-all NetworkPolicy targeting the pod, blocking ALL ingress
# and egress traffic. Labels the pod with gp-copilot/isolated: "true".
#
# Usage:
#   bash isolate-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production
#   bash isolate-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --dry-run
#   bash isolate-pod.sh --undo --pod nginx-7f9d8c6b4-x2z1q --namespace production
# =============================================================================
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Defaults ---
POD=""
NAMESPACE=""
DRY_RUN=false
UNDO=false

# --- Usage ---
usage() {
    cat <<'USAGE'
Usage: isolate-pod.sh --pod POD --namespace NS [--dry-run] [--undo]

Options:
  --pod POD           Name of the pod to isolate
  --namespace NS      Namespace the pod is in
  --dry-run           Show what would happen without applying
  --undo              Remove isolation (delete NetworkPolicy + remove label)
  -h, --help          Show this help

Examples:
  # Isolate a pod
  bash isolate-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production

  # Dry run (preview only)
  bash isolate-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --dry-run

  # Remove isolation
  bash isolate-pod.sh --undo --pod nginx-7f9d8c6b4-x2z1q --namespace production
USAGE
    exit "${1:-0}"
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pod)        POD="$2"; shift 2 ;;
        --namespace)  NAMESPACE="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --undo)       UNDO=true; shift ;;
        -h|--help)    usage 0 ;;
        *)            echo -e "${RED}ERROR: Unknown option: $1${NC}"; usage 1 ;;
    esac
done

if [[ -z "$POD" || -z "$NAMESPACE" ]]; then
    echo -e "${RED}ERROR: --pod and --namespace are required${NC}"
    usage 1
fi

POLICY_NAME="gp-isolate-${POD}"

# --- Verify pod exists ---
echo -e "${CYAN}[1/4] Verifying pod exists...${NC}"
if ! kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}ERROR: Pod '$POD' not found in namespace '$NAMESPACE'${NC}"
    exit 1
fi
echo -e "${GREEN}  Pod found: $POD in $NAMESPACE${NC}"

# --- Undo mode ---
if [[ "$UNDO" == true ]]; then
    echo -e "${CYAN}[UNDO] Removing isolation from $POD...${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}  DRY RUN: Would delete NetworkPolicy '$POLICY_NAME' in $NAMESPACE${NC}"
        echo -e "${YELLOW}  DRY RUN: Would remove label gp-copilot/isolated from $POD${NC}"
        exit 0
    fi

    # Delete the NetworkPolicy
    if kubectl get networkpolicy "$POLICY_NAME" -n "$NAMESPACE" &>/dev/null; then
        kubectl delete networkpolicy "$POLICY_NAME" -n "$NAMESPACE"
        echo -e "${GREEN}  Deleted NetworkPolicy: $POLICY_NAME${NC}"
    else
        echo -e "${YELLOW}  NetworkPolicy '$POLICY_NAME' not found (already removed?)${NC}"
    fi

    # Remove isolation label
    kubectl label pod "$POD" -n "$NAMESPACE" gp-copilot/isolated- 2>/dev/null || true
    echo -e "${GREEN}  Removed isolation label from $POD${NC}"

    echo ""
    echo -e "${GREEN}=== Pod $POD is no longer isolated ===${NC}"
    exit 0
fi

# --- Capture pod labels ---
echo -e "${CYAN}[2/4] Capturing pod labels...${NC}"
POD_LABELS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json | python3 -c "
import sys, json
pod = json.load(sys.stdin)
labels = pod.get('metadata', {}).get('labels', {})
for k, v in labels.items():
    print(f'  {k}: {v}')
")
echo "$POD_LABELS"

# --- Label pod as isolated ---
echo -e "${CYAN}[3/4] Labeling pod as isolated...${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}  DRY RUN: Would label $POD with gp-copilot/isolated=true${NC}"
else
    kubectl label pod "$POD" -n "$NAMESPACE" gp-copilot/isolated=true --overwrite
    echo -e "${GREEN}  Labeled $POD with gp-copilot/isolated=true${NC}"
fi

# --- Generate and apply deny-all NetworkPolicy ---
echo -e "${CYAN}[4/4] Applying deny-all NetworkPolicy...${NC}"

NETPOL_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${POLICY_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    gp-copilot/responder: pod-isolator
  annotations:
    gp-copilot/isolated-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    gp-copilot/isolated-pod: "${POD}"
spec:
  podSelector:
    matchLabels:
      gp-copilot/isolated: "true"
  policyTypes:
    - Ingress
    - Egress
  # No ingress/egress rules = deny all traffic
EOF
)

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}  DRY RUN: Would apply the following NetworkPolicy:${NC}"
    echo ""
    echo "$NETPOL_YAML"
    echo ""
    echo -e "${YELLOW}  DRY RUN: No changes made.${NC}"
    exit 0
fi

echo "$NETPOL_YAML" | kubectl apply -f -
echo -e "${GREEN}  Applied NetworkPolicy: $POLICY_NAME${NC}"

# --- Summary ---
echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}  POD ISOLATED: $POD${NC}"
echo -e "${RED}============================================${NC}"
echo -e "  Namespace:      $NAMESPACE"
echo -e "  NetworkPolicy:  $POLICY_NAME"
echo -e "  Traffic:        ${RED}ALL ingress + egress BLOCKED${NC}"
echo -e "  Timestamp:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""
echo -e "${CYAN}To undo isolation:${NC}"
echo -e "  bash $(dirname "$0")/isolate-pod.sh --undo --pod $POD --namespace $NAMESPACE"
echo ""
echo -e "${CYAN}To capture forensics before investigating:${NC}"
echo -e "  bash $(dirname "$0")/capture-forensics.sh --pod $POD --namespace $NAMESPACE"
