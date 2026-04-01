#!/usr/bin/env bash
# =============================================================================
# capture-forensics.sh — Capture forensic evidence from a pod
# =============================================================================
# Implements: CAPABILITIES.md Responders #14 (Log Capturer), #15 (Snapshot
# Creator), #16 (Evidence Preserver)
# Rank: E (always auto-approved — read-only, non-destructive)
#
# Captures pod describe, logs, YAML, events, processes, network connections,
# env vars (redacted), and filesystem changes. Saves to a timestamped dir.
#
# Usage:
#   bash capture-forensics.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production
#   bash capture-forensics.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --output-dir /tmp/forensics
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
OUTPUT_DIR=""
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)

# --- Usage ---
usage() {
    cat <<'USAGE'
Usage: capture-forensics.sh --pod POD --namespace NS [--output-dir DIR]

Options:
  --pod POD           Name of the pod to capture forensics from
  --namespace NS      Namespace the pod is in
  --output-dir DIR    Directory to save forensics (default: ./forensics-POD-TIMESTAMP/)
  -h, --help          Show this help

Examples:
  bash capture-forensics.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production
  bash capture-forensics.sh --pod nginx-7f9d8c6b4-x2z1q --namespace production --output-dir /tmp/forensics
USAGE
    exit "${1:-0}"
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pod)         POD="$2"; shift 2 ;;
        --namespace)   NAMESPACE="$2"; shift 2 ;;
        --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)     usage 0 ;;
        *)             echo -e "${RED}ERROR: Unknown option: $1${NC}"; usage 1 ;;
    esac
done

if [[ -z "$POD" || -z "$NAMESPACE" ]]; then
    echo -e "${RED}ERROR: --pod and --namespace are required${NC}"
    usage 1
fi

# --- Verify pod exists ---
echo -e "${CYAN}[PRE] Verifying pod exists...${NC}"
if ! kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}ERROR: Pod '$POD' not found in namespace '$NAMESPACE'${NC}"
    exit 1
fi

# --- Set up output directory ---
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="./forensics-${POD}-${TIMESTAMP}"
fi
mkdir -p "$OUTPUT_DIR"
OUTDIR=$(cd "$OUTPUT_DIR" && pwd)

CAPTURED=()
FAILED=()

capture() {
    local label="$1"
    local file="$2"
    shift 2
    echo -ne "  ${label}... "
    if "$@" > "${OUTDIR}/${file}" 2>&1; then
        echo -e "${GREEN}OK${NC}"
        CAPTURED+=("$file")
    else
        echo -e "${YELLOW}FAILED (non-fatal)${NC}"
        echo "# CAPTURE FAILED: $label" > "${OUTDIR}/${file}"
        echo "# Command: $*" >> "${OUTDIR}/${file}"
        echo "# This is expected if the container has no shell, read-only fs, or restricted exec." >> "${OUTDIR}/${file}"
        FAILED+=("$file")
    fi
}

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  FORENSIC CAPTURE: $POD${NC}"
echo -e "${CYAN}  Namespace: $NAMESPACE${NC}"
echo -e "${CYAN}  Output: $OUTDIR${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# --- 1. Pod describe ---
echo -e "${CYAN}[1/8] Pod describe${NC}"
capture "Full describe" "01-pod-describe.txt" kubectl describe pod "$POD" -n "$NAMESPACE"

# --- 2. Pod logs ---
echo -e "${CYAN}[2/8] Pod logs${NC}"
# Get container names
CONTAINERS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")
INIT_CONTAINERS=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || echo "")

for CONTAINER in $CONTAINERS; do
    capture "Logs ($CONTAINER, current)" "02-logs-${CONTAINER}-current.txt" kubectl logs "$POD" -n "$NAMESPACE" -c "$CONTAINER"
    capture "Logs ($CONTAINER, previous)" "02-logs-${CONTAINER}-previous.txt" kubectl logs "$POD" -n "$NAMESPACE" -c "$CONTAINER" --previous
done
for CONTAINER in $INIT_CONTAINERS; do
    capture "Logs (init: $CONTAINER)" "02-logs-init-${CONTAINER}.txt" kubectl logs "$POD" -n "$NAMESPACE" -c "$CONTAINER"
done

# --- 3. Pod YAML spec ---
echo -e "${CYAN}[3/8] Pod YAML spec${NC}"
capture "Full YAML" "03-pod-spec.yaml" kubectl get pod "$POD" -n "$NAMESPACE" -o yaml

# --- 4. Events ---
echo -e "${CYAN}[4/8] Related events${NC}"
capture "Pod events" "04-events.txt" kubectl get events -n "$NAMESPACE" --field-selector "involvedObject.name=$POD" --sort-by='.lastTimestamp'

# --- 5. Processes ---
echo -e "${CYAN}[5/8] Container processes${NC}"
for CONTAINER in $CONTAINERS; do
    capture "Processes ($CONTAINER)" "05-processes-${CONTAINER}.txt" kubectl exec "$POD" -n "$NAMESPACE" -c "$CONTAINER" -- ps aux
done

# --- 6. Network connections ---
echo -e "${CYAN}[6/8] Network connections${NC}"
for CONTAINER in $CONTAINERS; do
    # Try ss first, fall back to netstat
    echo -ne "  Network ($CONTAINER)... "
    if kubectl exec "$POD" -n "$NAMESPACE" -c "$CONTAINER" -- ss -tlnp > "${OUTDIR}/06-network-${CONTAINER}.txt" 2>&1; then
        echo -e "${GREEN}OK (ss)${NC}"
        CAPTURED+=("06-network-${CONTAINER}.txt")
    elif kubectl exec "$POD" -n "$NAMESPACE" -c "$CONTAINER" -- netstat -tlnp > "${OUTDIR}/06-network-${CONTAINER}.txt" 2>&1; then
        echo -e "${GREEN}OK (netstat)${NC}"
        CAPTURED+=("06-network-${CONTAINER}.txt")
    else
        echo -e "${YELLOW}FAILED (non-fatal)${NC}"
        echo "# CAPTURE FAILED: Network connections for $CONTAINER" > "${OUTDIR}/06-network-${CONTAINER}.txt"
        echo "# Neither ss nor netstat available in container." >> "${OUTDIR}/06-network-${CONTAINER}.txt"
        FAILED+=("06-network-${CONTAINER}.txt")
    fi
done

# --- 7. Environment variables (redacted) ---
echo -e "${CYAN}[7/8] Environment variables (redacted)${NC}"
for CONTAINER in $CONTAINERS; do
    echo -ne "  Env vars ($CONTAINER)... "
    RAW_ENV=$(kubectl exec "$POD" -n "$NAMESPACE" -c "$CONTAINER" -- env 2>&1) && {
        echo "$RAW_ENV" | python3 -c "
import sys
sensitive = ['password', 'secret', 'key', 'token', 'credential', 'api_key', 'apikey', 'auth']
for line in sys.stdin:
    line = line.rstrip()
    if '=' in line:
        name, _, value = line.partition('=')
        if any(s in name.lower() for s in sensitive):
            print(f'{name}=*** REDACTED ***')
        else:
            print(line)
    else:
        print(line)
" > "${OUTDIR}/07-env-${CONTAINER}.txt"
        echo -e "${GREEN}OK (redacted)${NC}"
        CAPTURED+=("07-env-${CONTAINER}.txt")
    } || {
        echo -e "${YELLOW}FAILED (non-fatal)${NC}"
        echo "# CAPTURE FAILED: Environment variables for $CONTAINER" > "${OUTDIR}/07-env-${CONTAINER}.txt"
        FAILED+=("07-env-${CONTAINER}.txt")
    }
done

# --- 8. Filesystem changes ---
echo -e "${CYAN}[8/8] Filesystem changes (/tmp)${NC}"
for CONTAINER in $CONTAINERS; do
    capture "Filesystem /tmp ($CONTAINER)" "08-filesystem-${CONTAINER}.txt" kubectl exec "$POD" -n "$NAMESPACE" -c "$CONTAINER" -- find /tmp -type f
done

# --- Generate summary ---
echo ""
echo -e "${CYAN}Generating summary...${NC}"

SUMMARY_FILE="${OUTDIR}/summary.md"
cat > "$SUMMARY_FILE" <<SUMMARY
# Forensic Capture Summary

| Field | Value |
|-------|-------|
| Pod | \`${POD}\` |
| Namespace | \`${NAMESPACE}\` |
| Timestamp | ${TIMESTAMP} |
| Captured by | \`capture-forensics.sh\` (GP-Copilot) |
| Output dir | \`${OUTDIR}\` |

## Captured Files

| # | File | Status |
|---|------|--------|
SUMMARY

# List all files in the output dir
for f in $(ls "$OUTDIR" | sort); do
    [[ "$f" == "summary.md" ]] && continue
    STATUS="OK"
    for failed in "${FAILED[@]+"${FAILED[@]}"}"; do
        if [[ "$failed" == "$f" ]]; then
            STATUS="FAILED"
            break
        fi
    done
    echo "| | \`${f}\` | ${STATUS} |" >> "$SUMMARY_FILE"
done

cat >> "$SUMMARY_FILE" <<SUMMARY

## Failed Captures

SUMMARY

if [[ ${#FAILED[@]} -eq 0 ]]; then
    echo "None. All captures succeeded." >> "$SUMMARY_FILE"
else
    for f in "${FAILED[@]}"; do
        echo "- \`${f}\` — likely no shell or restricted exec in container" >> "$SUMMARY_FILE"
    done
fi

cat >> "$SUMMARY_FILE" <<SUMMARY

## Next Steps

1. Review captured evidence in \`${OUTDIR}/\`
2. If pod is malicious: \`bash kill-pod.sh --pod ${POD} --namespace ${NAMESPACE}\`
3. If pod needs isolation: \`bash isolate-pod.sh --pod ${POD} --namespace ${NAMESPACE}\`

---
*Generated by GP-Copilot capture-forensics.sh*
SUMMARY

# --- Final report ---
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  FORENSIC CAPTURE COMPLETE${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "  Pod:        $POD"
echo -e "  Namespace:  $NAMESPACE"
echo -e "  Output:     $OUTDIR"
echo -e "  Captured:   ${GREEN}${#CAPTURED[@]} files${NC}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "  Failed:     ${YELLOW}${#FAILED[@]} files (non-fatal)${NC}"
fi
echo -e "  Summary:    $OUTDIR/summary.md"
echo ""

# Print the output dir path for callers to capture
echo "$OUTDIR"
