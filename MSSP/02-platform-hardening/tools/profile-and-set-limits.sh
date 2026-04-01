#!/usr/bin/env bash
# ============================================================================
# Profile Pod Resource Usage and Apply Right-Sized Limits
#
# This script:
#   1. Profiles actual CPU/memory usage from metrics-server (kubectl top)
#   2. Calculates right-sized requests (actual) and limits (2x headroom)
#   3. Applies LimitRange to namespaces without one
#   4. Patches deployments/statefulsets/daemonsets that have no resource limits
#
# Usage:
#   bash profile-and-set-limits.sh                    # Profile + apply
#   bash profile-and-set-limits.sh --dry-run          # Profile only, no changes
#   bash profile-and-set-limits.sh --namespace vault   # Single namespace
#   bash profile-and-set-limits.sh --headroom 3       # 3x headroom (default 2x)
#
# Prerequisites:
#   - kubectl access to the cluster
#   - metrics-server running (kubectl top pods must work)
#
# NIST 800-53: CM-6 (Configuration Settings), SC-6 (Resource Availability)
# CIS K8s: 5.7.3 (Apply Security Context: resource requests/limits)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE="${PKG_DIR}/02-hardening/remediation/resource-management.yaml"
DRY_RUN=false
NAMESPACE=""
HEADROOM=2
SKIP_SYSTEM=true

# System namespaces — never patch these workloads directly
SYSTEM_NS="kube-system kube-public kube-node-lease gatekeeper-system"

# Minimum sane values (don't set limits below these)
MIN_CPU_REQUEST="50m"
MIN_MEM_REQUEST="64Mi"
MIN_CPU_LIMIT="100m"
MIN_MEM_LIMIT="128Mi"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run         Profile only, no changes"
    echo "  --namespace NS    Target a single namespace"
    echo "  --headroom N      Limit multiplier over observed usage (default: 2)"
    echo "  --include-system  Also profile system namespaces (default: skip)"
    echo "  -h, --help        Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)     DRY_RUN=true; shift ;;
        --namespace)   NAMESPACE="$2"; shift 2 ;;
        --headroom)    HEADROOM="$2"; shift 2 ;;
        --include-system) SKIP_SYSTEM=false; shift ;;
        -h|--help)     usage ;;
        *)             echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "============================================"
echo "  Resource Profiler + Limit Setter"
echo "============================================"
echo "Dry run:   ${DRY_RUN}"
echo "Headroom:  ${HEADROOM}x observed usage"
echo "Namespace: ${NAMESPACE:-all}"
echo ""

# Verify metrics-server
if ! kubectl top pods -A --no-headers &>/dev/null; then
    echo "ERROR: metrics-server not available (kubectl top pods failed)"
    echo "Install: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    exit 1
fi

# ─────────────────────────────────────────────────────
# Phase 1: Profile actual usage
# ─────────────────────────────────────────────────────
echo "--- Phase 1: Profiling actual resource usage ---"
echo ""

# Get all namespaces or specific one
if [[ -n "$NAMESPACE" ]]; then
    NAMESPACES="$NAMESPACE"
else
    NAMESPACES=$(kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
fi

# Collect usage data
PROFILE_DATA=$(mktemp)
trap "rm -f $PROFILE_DATA" EXIT

printf "%-50s %-10s %-12s %-10s %-12s\n" "POD" "CPU_NOW" "MEM_NOW" "CPU_LIM" "MEM_LIM"
printf "%-50s %-10s %-12s %-10s %-12s\n" "---" "-------" "-------" "-------" "-------"

for ns in $NAMESPACES; do
    # Skip system namespaces unless --include-system
    if $SKIP_SYSTEM; then
        skip=false
        for sys_ns in $SYSTEM_NS; do
            [[ "$ns" == "$sys_ns" ]] && skip=true && break
        done
        $skip && continue
    fi

    # Get current usage
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        pod=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        mem=$(echo "$line" | awk '{print $3}')

        # Get current limits
        limits=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].resources.limits.cpu}/{.spec.containers[0].resources.limits.memory}' 2>/dev/null)
        cpu_lim=$(echo "$limits" | cut -d/ -f1)
        mem_lim=$(echo "$limits" | cut -d/ -f2)
        [[ -z "$cpu_lim" ]] && cpu_lim="NONE"
        [[ -z "$mem_lim" ]] && mem_lim="NONE"

        printf "%-50s %-10s %-12s %-10s %-12s\n" "${ns}/${pod}" "$cpu" "$mem" "$cpu_lim" "$mem_lim"
        echo "${ns}|${pod}|${cpu}|${mem}|${cpu_lim}|${mem_lim}" >> "$PROFILE_DATA"
    done < <(kubectl top pods -n "$ns" --no-headers 2>/dev/null)
done

echo ""
TOTAL=$(wc -l < "$PROFILE_DATA")
NO_LIMITS=$(grep "|NONE|" "$PROFILE_DATA" | wc -l)
echo "Total pods profiled: ${TOTAL}"
echo "Pods without limits: ${NO_LIMITS}"
echo ""

if $DRY_RUN; then
    echo "[DRY RUN] Would apply LimitRange + patch ${NO_LIMITS} workloads."
    echo "[DRY RUN] Run without --dry-run to apply changes."
    exit 0
fi

if [[ "$NO_LIMITS" -eq 0 ]]; then
    echo "All pods have resource limits. Nothing to do."
    exit 0
fi

# ─────────────────────────────────────────────────────
# Phase 2: Apply LimitRange to namespaces without one
# ─────────────────────────────────────────────────────
echo "--- Phase 2: Applying LimitRange to namespaces ---"
echo ""

# Extract unique namespaces from pods without limits
NS_TO_FIX=$(grep "|NONE|" "$PROFILE_DATA" | cut -d'|' -f1 | sort -u)

for ns in $NS_TO_FIX; do
    # Check if LimitRange already exists
    existing=$(kubectl get limitrange -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$existing" -gt 0 ]]; then
        echo "  ${ns}: LimitRange already exists, skipping"
        continue
    fi

    # Apply LimitRange only (not ResourceQuota — that needs sizing per namespace)
    echo "  ${ns}: Applying LimitRange (default: 500m/512Mi)"
    kubectl apply -f - <<LIMITEOF
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: ${ns}
  annotations:
    security.ghostprotocol.io/control: "CKA-resource-management"
    security.ghostprotocol.io/applied-by: "profile-and-set-limits.sh"
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "4"
      memory: "4Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
LIMITEOF
done

echo ""

# ─────────────────────────────────────────────────────
# Phase 3: Patch workloads with right-sized limits
# ─────────────────────────────────────────────────────
echo "--- Phase 3: Patching workloads without resource limits ---"
echo ""

# Helper: convert CPU string to millicores integer
cpu_to_milli() {
    local val="$1"
    if [[ "$val" == *m ]]; then
        echo "${val%m}"
    else
        echo $(( ${val} * 1000 ))
    fi
}

# Helper: convert memory string to Mi integer
mem_to_mi() {
    local val="$1"
    if [[ "$val" == *Gi ]]; then
        echo $(( ${val%Gi} * 1024 ))
    elif [[ "$val" == *Mi ]]; then
        echo "${val%Mi}"
    elif [[ "$val" == *Ki ]]; then
        echo $(( ${val%Ki} / 1024 ))
    else
        echo "$val"
    fi
}

# Helper: find the owner workload of a pod
get_owner() {
    local ns="$1" pod="$2"
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}' 2>/dev/null
}

PATCHED=0
SKIPPED=0
FAILED=0

# Process each pod without limits
while IFS='|' read -r ns pod cpu_now mem_now cpu_lim mem_lim; do
    # Skip if has limits
    [[ "$cpu_lim" != "NONE" && "$mem_lim" != "NONE" ]] && continue

    # Get owner workload
    owner=$(get_owner "$ns" "$pod")
    kind=$(echo "$owner" | cut -d/ -f1)
    name=$(echo "$owner" | cut -d/ -f2)

    # ReplicaSet → find the Deployment
    if [[ "$kind" == "ReplicaSet" ]]; then
        deploy=$(kubectl get rs "$name" -n "$ns" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
        if [[ -n "$deploy" ]]; then
            kind="Deployment"
            name="$deploy"
        fi
    fi

    # Only patch Deployment, StatefulSet, DaemonSet
    case "$kind" in
        Deployment|StatefulSet|DaemonSet) ;;
        *)
            echo "  SKIP ${ns}/${pod}: owner is ${kind}/${name} (not patchable)"
            SKIPPED=$((SKIPPED + 1))
            continue
            ;;
    esac

    # Calculate right-sized limits
    cpu_milli=$(cpu_to_milli "$cpu_now")
    mem_mi=$(mem_to_mi "$mem_now")

    # Request = max(observed, minimum)
    req_cpu=$(( cpu_milli > 50 ? cpu_milli : 50 ))
    req_mem=$(( mem_mi > 64 ? mem_mi : 64 ))

    # Limit = headroom * observed, with minimum floor
    lim_cpu=$(( cpu_milli * HEADROOM ))
    lim_mem=$(( mem_mi * HEADROOM ))
    [[ $lim_cpu -lt 100 ]] && lim_cpu=100
    [[ $lim_mem -lt 128 ]] && lim_mem=128

    echo "  PATCH ${kind}/${name} in ${ns}: requests=${req_cpu}m/${req_mem}Mi limits=${lim_cpu}m/${lim_mem}Mi (observed: ${cpu_now}/${mem_now})"

    # Apply the patch
    if kubectl patch "$kind" "$name" -n "$ns" --type=strategic -p "{
        \"spec\":{\"template\":{\"spec\":{\"containers\":[{
            \"name\":\"$(kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)\",
            \"resources\":{
                \"requests\":{\"cpu\":\"${req_cpu}m\",\"memory\":\"${req_mem}Mi\"},
                \"limits\":{\"cpu\":\"${lim_cpu}m\",\"memory\":\"${lim_mem}Mi\"}
            }
        }]}}}
    }" 2>/dev/null; then
        PATCHED=$((PATCHED + 1))
    else
        echo "    FAILED to patch ${kind}/${name}"
        FAILED=$((FAILED + 1))
    fi

done < "$PROFILE_DATA"

echo ""
echo "============================================"
echo "  Resource Limits Applied"
echo "============================================"
echo "  Patched:  ${PATCHED}"
echo "  Skipped:  ${SKIPPED}"
echo "  Failed:   ${FAILED}"
echo ""
echo "  Next steps:"
echo "  1. Verify: kubectl top pods -A"
echo "  2. Re-scan: kubescape scan framework nsa"
echo "  3. Monitor: watch for OOMKilled events"
echo "     kubectl get events -A --field-selector reason=OOMKilling"
echo "============================================"
