#!/usr/bin/env bash
set -euo pipefail

# scan-runtime.sh — Container runtime security checks
# Usage: ./scan-runtime.sh [namespace]
# Requires: kubectl access to a cluster

NAMESPACE="${1:---all-namespaces}"
OUTPUT_DIR=".oss-copilot/container"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: Container Runtime Security ==="
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "[!] kubectl not found. This script requires cluster access."
    exit 1
fi

NS_FLAG="--all-namespaces"
if [ "$NAMESPACE" != "--all-namespaces" ]; then
    NS_FLAG="-n $NAMESPACE"
fi

# --- Privileged containers ---
echo "[*] Checking for privileged containers..."
PRIVILEGED=$(kubectl get pods $NS_FLAG -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
findings = []
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        sc = c.get('securityContext', {})
        if sc.get('privileged'):
            findings.append(f'  PRIVILEGED: {ns}/{name}/{c[\"name\"]}')
        if sc.get('runAsUser') == 0 or (not sc.get('runAsNonRoot') and not sc.get('runAsUser')):
            findings.append(f'  ROOT-RISK:  {ns}/{name}/{c[\"name\"]}')
        if not sc.get('readOnlyRootFilesystem'):
            findings.append(f'  RW-ROOTFS:  {ns}/{name}/{c[\"name\"]}')
        if not sc.get('capabilities', {}).get('drop'):
            findings.append(f'  NO-CAP-DROP: {ns}/{name}/{c[\"name\"]}')
print('\n'.join(findings) if findings else 'None found')
print(f'TOTAL:{len(findings)}')
" 2>/dev/null)
echo "$PRIVILEGED"
echo ""

# --- Containers without resource limits ---
echo "[*] Checking for missing resource limits..."
kubectl get pods $NS_FLAG -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        resources = c.get('resources', {})
        if not resources.get('limits'):
            print(f'  NO-LIMITS: {ns}/{name}/{c[\"name\"]}')
            count += 1
print(f'TOTAL:{count}')
"
echo ""

# --- Falco check ---
echo "[*] Checking Falco deployment..."
if kubectl get pods $NS_FLAG -l app.kubernetes.io/name=falco 2>/dev/null | grep -q Running; then
    echo "    Falco: DEPLOYED and running"
    FALCO_ALERTS=$(kubectl logs -l app.kubernetes.io/name=falco --tail=50 $NS_FLAG 2>/dev/null | grep -c "Warning\|Error\|Critical" || echo "0")
    echo "    Recent alerts (last 50 lines): $FALCO_ALERTS"
else
    echo "    Falco: NOT DEPLOYED"
    echo "    Install: helm install falco falcosecurity/falco -n falco-system --create-namespace"
fi

echo ""
echo "=== Runtime scan complete ==="
echo ""
echo "Results saved to: $OUTPUT_DIR/"
echo ""
echo "Note: Falco provides runtime detection (alerting on suspicious syscalls)."
echo "For runtime BLOCKING (auto-kill malicious containers), you need"
echo "Prisma Cloud CWPP or Sysdig Secure."
