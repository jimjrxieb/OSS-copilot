#!/usr/bin/env bash
# cleanup-orphaned-secrets.sh — Find and optionally delete secrets not mounted by any pod
#
# Usage:
#   bash cleanup-orphaned-secrets.sh                    # Audit mode (report only)
#   bash cleanup-orphaned-secrets.sh --delete           # Delete orphaned secrets
#   bash cleanup-orphaned-secrets.sh --namespace anthra # Single namespace
#
# What it checks:
#   - Secrets not mounted as volumes by any pod in the same namespace
#   - Secrets not referenced by any container envFrom/env.valueFrom
#   - Skips: service-account-token, helm.sh/release, TLS certs used by Ingress/Gateway

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DELETE_MODE=false
TARGET_NS=""
REPORT_FILE=""

for arg in "$@"; do
    case $arg in
        --delete)     DELETE_MODE=true ;;
        --namespace)  shift; TARGET_NS="$1" ;;
        --namespace=*) TARGET_NS="${arg#*=}" ;;
        --output)     shift; REPORT_FILE="$1" ;;
        --output=*)   REPORT_FILE="${arg#*=}" ;;
        -h|--help)    head -11 "$0" | tail -9; exit 0 ;;
    esac
    shift 2>/dev/null || true
done

ORPHANED_COUNT=0
TOTAL_SECRETS=0
DELETED_COUNT=0

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()  { echo -e "${RED}[ORPHAN]${NC}  $*"; }

# System namespaces to skip
SKIP_NS="kube-system kube-public kube-node-lease"

if [[ -n "$TARGET_NS" ]]; then
    NAMESPACES="$TARGET_NS"
else
    NAMESPACES=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
fi

echo ""
echo "=============================================="
echo "  Orphaned Secrets Audit"
echo "=============================================="
echo ""

REPORT_LINES=()
REPORT_LINES+=("# Orphaned Secrets Audit Report")
REPORT_LINES+=("Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')")
REPORT_LINES+=("")

for ns in $NAMESPACES; do
    # Skip system namespaces
    if echo "$SKIP_NS" | grep -qw "$ns"; then
        continue
    fi

    # Get all secrets in namespace
    SECRETS=$(kubectl get secrets -n "$ns" -o json 2>/dev/null)
    SECRET_NAMES=$(echo "$SECRETS" | jq -r '.items[].metadata.name' 2>/dev/null)

    if [[ -z "$SECRET_NAMES" ]]; then
        continue
    fi

    # Get all pod specs to find referenced secrets
    PODS=$(kubectl get pods -n "$ns" -o json 2>/dev/null)

    # Extract secrets referenced by pods (volumes, envFrom, env valueFrom)
    REFERENCED=$(echo "$PODS" | jq -r '
        [
            .items[].spec.volumes[]?.secret.secretName,
            .items[].spec.containers[].envFrom[]?.secretRef.name,
            .items[].spec.containers[].env[]?.valueFrom.secretKeyRef.name,
            .items[].spec.initContainers[]?.envFrom[]?.secretRef.name,
            .items[].spec.initContainers[]?.env[]?.valueFrom.secretKeyRef.name
        ] | map(select(. != null)) | unique | .[]
    ' 2>/dev/null)

    # Also check Ingress/Gateway TLS references
    TLS_SECRETS=$(kubectl get ingress,gateway -n "$ns" -o json 2>/dev/null | jq -r '
        [.items[].spec.tls[]?.secretName, .items[].spec.listeners[]?.tls.certificateRefs[]?.name] | map(select(. != null)) | unique | .[]
    ' 2>/dev/null)

    # Also check ExternalSecret targets
    ES_TARGETS=$(kubectl get externalsecrets -n "$ns" -o json 2>/dev/null | jq -r '
        [.items[].spec.target.name] | map(select(. != null)) | unique | .[]
    ' 2>/dev/null)

    ALL_REFERENCED=$(printf "%s\n%s\n%s" "$REFERENCED" "$TLS_SECRETS" "$ES_TARGETS" | sort -u)

    for secret in $SECRET_NAMES; do
        ((TOTAL_SECRETS++))

        # Skip service account tokens
        SECRET_TYPE=$(echo "$SECRETS" | jq -r ".items[] | select(.metadata.name==\"$secret\") | .type" 2>/dev/null)
        if [[ "$SECRET_TYPE" == "kubernetes.io/service-account-token" ]]; then
            continue
        fi

        # Skip Helm release secrets
        if [[ "$secret" == sh.helm.release.* ]]; then
            continue
        fi

        # Check if referenced
        if echo "$ALL_REFERENCED" | grep -qw "$secret"; then
            continue
        fi

        # This secret is orphaned
        ((ORPHANED_COUNT++))
        AGE=$(kubectl get secret "$secret" -n "$ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
        log_fail "$ns/$secret (type=$SECRET_TYPE, created=$AGE)"
        REPORT_LINES+=("- **ORPHANED**: \`$ns/$secret\` (type=$SECRET_TYPE, created=$AGE)")

        if $DELETE_MODE; then
            kubectl delete secret "$secret" -n "$ns" 2>&1
            if [[ $? -eq 0 ]]; then
                log_ok "Deleted $ns/$secret"
                ((DELETED_COUNT++))
                REPORT_LINES+=("  - **DELETED**")
            else
                log_warn "Failed to delete $ns/$secret"
            fi
        fi
    done
done

echo ""
echo "=============================================="
echo "  SUMMARY"
echo "=============================================="
echo ""
echo -e "  Total secrets scanned: ${BLUE}${TOTAL_SECRETS}${NC}"
echo -e "  Orphaned secrets:      ${YELLOW}${ORPHANED_COUNT}${NC}"
if $DELETE_MODE; then
    echo -e "  Deleted:               ${GREEN}${DELETED_COUNT}${NC}"
fi
echo ""

REPORT_LINES+=("")
REPORT_LINES+=("## Summary")
REPORT_LINES+=("- Total secrets scanned: $TOTAL_SECRETS")
REPORT_LINES+=("- Orphaned secrets: $ORPHANED_COUNT")
if $DELETE_MODE; then
    REPORT_LINES+=("- Deleted: $DELETED_COUNT")
fi

if [[ -n "$REPORT_FILE" ]]; then
    mkdir -p "$(dirname "$REPORT_FILE")"
    printf '%s\n' "${REPORT_LINES[@]}" > "$REPORT_FILE"
    log_ok "Report written to $REPORT_FILE"
fi

exit 0
