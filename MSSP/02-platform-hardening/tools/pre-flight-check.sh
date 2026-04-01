#!/usr/bin/env bash
# ============================================================================
# Pre-Flight Check — Run BEFORE any 02-CLUSTER-HARDENING playbook
#
# Detects platform, GitOps controllers, storage provisioners, and known
# conflicts BEFORE you start breaking things.
#
# Usage:
#   bash pre-flight-check.sh                    # Full check
#   bash pre-flight-check.sh --cluster-only     # Skip local tool checks
#
# Every issue we've ever hit in an engagement was detectable here.
# ============================================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ISSUES=0
WARNINGS=0

pass()  { echo -e "${GREEN}[PASS]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; ISSUES=$((ISSUES + 1)); }
info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }

echo "============================================"
echo "  Pre-Flight Check"
echo "  02-CLUSTER-HARDENING"
echo "============================================"
echo ""

# ─────────────────────────────────────────────────
# 1. Platform Detection
# ─────────────────────────────────────────────────
echo "--- Platform Detection ---"

K8S_VERSION=$(kubectl version -o json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])' 2>/dev/null)
if [[ -z "$K8S_VERSION" ]]; then
    fail "Cannot connect to cluster (kubectl version failed)"
    echo "Fix: configure kubeconfig or check VPN/SSH"
    exit 1
fi
pass "Cluster connected: ${K8S_VERSION}"

# Detect platform
if echo "$K8S_VERSION" | grep -q "k3s"; then
    PLATFORM="k3s"
    pass "Platform: k3s"
    info "IMPORTANT: k3s config is /etc/rancher/k3s/config.yaml (NOT KubeletConfiguration format)"
    info "IMPORTANT: kubelet args use 'kubelet-arg:' list, not systemd drop-ins"
    info "IMPORTANT: protect-kernel-defaults must be false on k3s"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null | grep -q "eks.amazonaws.com"; then
    PLATFORM="eks"
    pass "Platform: EKS"
    info "IMPORTANT: No control plane access. Skip CIS sections 1.x-3.x"
elif which kubeadm &>/dev/null; then
    PLATFORM="kubeadm"
    pass "Platform: kubeadm"
else
    PLATFORM="unknown"
    warn "Platform: unknown — check playbook 01a for quirks"
fi

echo ""

# ─────────────────────────────────────────────────
# 2. GitOps Controller Detection
# ─────────────────────────────────────────────────
echo "--- GitOps Controllers ---"

ARGOCD_APPS=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
if [[ "$ARGOCD_APPS" -gt 0 ]]; then
    warn "ArgoCD detected: ${ARGOCD_APPS} application(s)"
    info "HARD RULE: Never kubectl patch ArgoCD-managed resources. Fix in git."
    kubectl get applications -n argocd -o custom-columns='APP:.metadata.name,PATH:.spec.source.path' 2>/dev/null | while read line; do
        info "  $line"
    done
else
    pass "No ArgoCD applications found"
fi

FLUX=$(kubectl get kustomizations -A --no-headers 2>/dev/null | wc -l)
if [[ "$FLUX" -gt 0 ]]; then
    warn "Flux detected: ${FLUX} kustomization(s). Same rule — fix in git."
else
    pass "No Flux kustomizations found"
fi

echo ""

# ─────────────────────────────────────────────────
# 3. Storage Provisioner + PSA Conflict Check
# ─────────────────────────────────────────────────
echo "--- Storage + PSA Conflicts ---"

PROVISIONER=$(kubectl get sc -o jsonpath='{.items[0].provisioner}' 2>/dev/null)
info "Default StorageClass provisioner: ${PROVISIONER:-none}"

if [[ "$PROVISIONER" == "rancher.io/local-path" ]]; then
    warn "local-path-provisioner detected"
    info "KNOWN CONFLICT: Helper pods use hostPath. PSA baseline+ blocks them."
    info "FIX: Set PSA enforce=privileged on namespaces using local-path PVCs."
    info "     Use Gatekeeper/Kyverno for actual pod security enforcement."

    # Check which namespaces have PVCs
    PVC_NS=$(kubectl get pvc -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u)
    for ns in $PVC_NS; do
        PSA=$(kubectl get ns "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
        if [[ "$PSA" != "privileged" && -n "$PSA" ]]; then
            fail "Namespace '$ns' has PVCs but PSA enforce=${PSA} (not privileged). PVC provisioning will fail."
        fi
    done
fi

echo ""

# ─────────────────────────────────────────────────
# 4. Ansible Readiness
# ─────────────────────────────────────────────────
echo "--- Ansible Readiness ---"

if which ansible-playbook &>/dev/null; then
    pass "ansible-playbook found"
else
    warn "ansible-playbook not found. Install: pip install ansible"
fi

# Check SSH connectivity to nodes
NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
for node in $NODES; do
    if ssh -o ConnectTimeout=3 -o BatchMode=yes "$node" "true" 2>/dev/null; then
        pass "SSH to node $node: OK"
        # Check sudo
        if ssh -o ConnectTimeout=3 -o BatchMode=yes "$node" "sudo -n true" 2>/dev/null; then
            pass "Passwordless sudo on $node: OK"
        else
            warn "Node $node needs --ask-become-pass (-K) for Ansible"
        fi
    else
        warn "Cannot SSH to $node — check inventory file"
    fi
done

echo ""

# ─────────────────────────────────────────────────
# 5. Admission Control
# ─────────────────────────────────────────────────
echo "--- Admission Control ---"

GK_PODS=$(kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | wc -l)
KV_PODS=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | wc -l)

if [[ "$GK_PODS" -gt 0 ]]; then
    pass "Gatekeeper: ${GK_PODS} pods running"
    DENY_COUNT=$(kubectl get constraints -o json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(1 for i in d["items"] if i["spec"]["enforcementAction"]=="deny"))' 2>/dev/null)
    info "Constraints in deny mode: ${DENY_COUNT:-0}"
elif [[ "$KV_PODS" -gt 0 ]]; then
    pass "Kyverno: ${KV_PODS} pods running"
else
    info "No admission controller deployed — playbook 06 will install one"
fi

echo ""

# ─────────────────────────────────────────────────
# 6. Existing Hardening
# ─────────────────────────────────────────────────
echo "--- Existing Hardening ---"

NP_COUNT=$(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l)
LR_COUNT=$(kubectl get limitrange -A --no-headers 2>/dev/null | wc -l)
RQ_COUNT=$(kubectl get resourcequota -A --no-headers 2>/dev/null | wc -l)
NS_COUNT=$(kubectl get ns --no-headers 2>/dev/null | wc -l)
PSA_COUNT=$(kubectl get ns -o json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(sum(1 for n in d["items"] if "pod-security.kubernetes.io/enforce" in n["metadata"].get("labels",{})))' 2>/dev/null)

info "NetworkPolicies: ${NP_COUNT}"
info "LimitRanges: ${LR_COUNT}"
info "ResourceQuotas: ${RQ_COUNT}"
info "PSA-labeled namespaces: ${PSA_COUNT:-0}/${NS_COUNT}"

echo ""

# ─────────────────────────────────────────────────
# 7. Tools on cluster
# ─────────────────────────────────────────────────
echo "--- Scanner Tools ---"

for tool in kubescape kube-bench polaris; do
    if which $tool &>/dev/null 2>&1 || ssh -o ConnectTimeout=3 -o BatchMode=yes "${NODES%% *}" "which $tool" 2>/dev/null; then
        pass "$tool: installed"
    else
        info "$tool: not installed (playbook 03 will install)"
    fi
done

echo ""
echo "============================================"
echo "  Pre-Flight Summary"
echo "============================================"
echo "  Platform:  ${PLATFORM}"
echo "  Issues:    ${ISSUES}"
echo "  Warnings:  ${WARNINGS}"

if [[ "$ISSUES" -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}FIX ${ISSUES} ISSUE(S) BEFORE PROCEEDING${NC}"
fi

echo "============================================"
