#!/usr/bin/env bash
# =============================================================================
# kill-pod.sh — Terminate a malicious pod (captures forensics first)
# =============================================================================
# Implements: CAPABILITIES.md Responder #4 (Pod Killer)
# Rank: C (JADE approval required when automated; manual use = human decision)
#
# ALWAYS captures forensic evidence before deleting the pod.
# Refuses to kill pods in kube-system or gp-security namespaces.
#
# Usage:
#   bash kill-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production
#   bash kill-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --force
#   bash kill-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --dry-run
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
FORCE=false
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Protected namespaces ---
PROTECTED_NAMESPACES=("kube-system" "gp-security")

# --- Usage ---
usage() {
    cat <<'USAGE'
Usage: kill-pod.sh --pod POD --namespace NS [--force] [--dry-run]

Options:
  --pod POD           Name of the pod to terminate
  --namespace NS      Namespace the pod is in
  --force             Skip confirmation + use force-delete (grace-period=0)
  --dry-run           Show what would happen without deleting
  -h, --help          Show this help

Safeguards:
  - Never kills pods in kube-system or gp-security
  - Always captures forensic evidence before deletion
  - Requires confirmation unless --force or --dry-run

Examples:
  bash kill-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production
  bash kill-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --force
  bash kill-pod.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --dry-run
USAGE
    exit "${1:-0}"
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pod)        POD="$2"; shift 2 ;;
        --namespace)  NAMESPACE="$2"; shift 2 ;;
        --force)      FORCE=true; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        -h|--help)    usage 0 ;;
        *)            echo -e "${RED}ERROR: Unknown option: $1${NC}"; usage 1 ;;
    esac
done

if [[ -z "$POD" || -z "$NAMESPACE" ]]; then
    echo -e "${RED}ERROR: --pod and --namespace are required${NC}"
    usage 1
fi

# --- Step 1: Verify pod exists ---
echo -e "${CYAN}[1/5] Verifying pod exists...${NC}"
if ! kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}ERROR: Pod '$POD' not found in namespace '$NAMESPACE'${NC}"
    exit 1
fi

POD_STATUS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
POD_NODE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "unknown")
echo -e "${GREEN}  Found: $POD (status: $POD_STATUS, node: $POD_NODE)${NC}"

# --- Step 2: Check protected namespaces ---
echo -e "${CYAN}[2/5] Checking namespace protection...${NC}"
for ns in "${PROTECTED_NAMESPACES[@]}"; do
    if [[ "$NAMESPACE" == "$ns" ]]; then
        echo -e "${RED}ERROR: Refusing to kill pod in protected namespace '$NAMESPACE'${NC}"
        echo -e "${RED}  Protected namespaces: ${PROTECTED_NAMESPACES[*]}${NC}"
        echo -e "${YELLOW}  If you really need to do this, use kubectl directly.${NC}"
        exit 1
    fi
done
echo -e "${GREEN}  Namespace '$NAMESPACE' is not protected${NC}"

# --- Step 3: Capture forensics ---
echo -e "${CYAN}[3/5] Capturing forensic evidence...${NC}"
FORENSICS_SCRIPT="${SCRIPT_DIR}/capture-forensics.sh"
if [[ ! -f "$FORENSICS_SCRIPT" ]]; then
    echo -e "${RED}ERROR: capture-forensics.sh not found at $FORENSICS_SCRIPT${NC}"
    exit 1
fi

FORENSICS_DIR=$(bash "$FORENSICS_SCRIPT" --pod "$POD" --namespace "$NAMESPACE" | tail -1)
echo -e "${GREEN}  Forensics saved to: $FORENSICS_DIR${NC}"

# --- Step 4: Confirmation ---
echo -e "${CYAN}[4/5] Confirmation...${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  DRY RUN — Pod would be deleted:${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo -e "  Pod:        $POD"
    echo -e "  Namespace:  $NAMESPACE"
    echo -e "  Status:     $POD_STATUS"
    echo -e "  Node:       $POD_NODE"
    echo -e "  Force:      $FORCE"
    echo -e "  Forensics:  $FORENSICS_DIR"
    echo -e "${YELLOW}  No changes made.${NC}"
    exit 0
fi

if [[ "$FORCE" != true ]]; then
    echo ""
    echo -e "${RED}  WARNING: This will DELETE pod '$POD' in namespace '$NAMESPACE'.${NC}"
    echo -e "  Forensic evidence has been captured to: $FORENSICS_DIR"
    echo ""
    read -rp "  Type 'yes' to confirm deletion: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        echo -e "${YELLOW}  Aborted. Pod not deleted.${NC}"
        exit 0
    fi
fi

# --- Step 5: Delete pod ---
echo -e "${CYAN}[5/5] Deleting pod...${NC}"
DELETE_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ "$FORCE" == true ]]; then
    kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force
    DELETE_METHOD="force-delete (grace-period=0)"
else
    kubectl delete pod "$POD" -n "$NAMESPACE"
    DELETE_METHOD="graceful delete"
fi

DELETE_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Incident summary ---
echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}  POD TERMINATED: $POD${NC}"
echo -e "${RED}============================================${NC}"
echo -e "  Namespace:      $NAMESPACE"
echo -e "  Status before:  $POD_STATUS"
echo -e "  Node:           $POD_NODE"
echo -e "  Method:         $DELETE_METHOD"
echo -e "  Deleted at:     $DELETE_START"
echo -e "  Forensics:      $FORENSICS_DIR"
echo ""

# Write incident report to forensics dir
INCIDENT_FILE="${FORENSICS_DIR}/incident-report.md"
cat > "$INCIDENT_FILE" <<REPORT
# Incident Report: Pod Termination

| Field | Value |
|-------|-------|
| Pod | \`${POD}\` |
| Namespace | \`${NAMESPACE}\` |
| Status before kill | ${POD_STATUS} |
| Node | ${POD_NODE} |
| Delete method | ${DELETE_METHOD} |
| Delete started | ${DELETE_START} |
| Delete completed | ${DELETE_END} |
| Forensics dir | \`${FORENSICS_DIR}\` |
| Killed by | \`kill-pod.sh\` (GP-Copilot) |

## Actions Taken

1. Verified pod exists (status: ${POD_STATUS})
2. Verified namespace '${NAMESPACE}' is not protected
3. Captured forensic evidence to \`${FORENSICS_DIR}\`
4. Deleted pod using ${DELETE_METHOD}

## Next Steps

1. Review forensic evidence in \`${FORENSICS_DIR}\`
2. Check if the pod's controller (Deployment/ReplicaSet) recreated it
3. If recreated, investigate the workload: \`kubectl get deploy -n ${NAMESPACE}\`
4. If malicious workload, delete the parent resource
5. Consider isolating the namespace: \`bash isolate-pod.sh --pod NEW_POD --namespace ${NAMESPACE}\`

---
*Generated by GP-Copilot kill-pod.sh*
REPORT

echo -e "${CYAN}Incident report: $INCIDENT_FILE${NC}"
echo ""
echo -e "${YELLOW}Check if pod was recreated by a controller:${NC}"
echo -e "  kubectl get pods -n $NAMESPACE | grep $(echo "$POD" | sed 's/-[a-z0-9]*$//')"
