#!/usr/bin/env bash
set -euo pipefail

# scan-rbac.sh — RBAC analysis for Kubernetes
# Usage: ./scan-rbac.sh [namespace]
# Requires: kubectl access to a cluster

NAMESPACE="${1:---all-namespaces}"
OUTPUT_DIR=".oss-copilot/cluster"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: RBAC Security Scan ==="
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "[!] kubectl not found. This script requires cluster access."
    exit 1
fi

NS_FLAG="--all-namespaces"
if [ "$NAMESPACE" != "--all-namespaces" ]; then
    NS_FLAG="-n $NAMESPACE"
fi

# --- Cluster-admin bindings ---
echo "[*] Checking cluster-admin bindings..."
kubectl get clusterrolebindings -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
findings = []
for binding in data.get('items', []):
    role_ref = binding.get('roleRef', {})
    if role_ref.get('name') == 'cluster-admin':
        subjects = binding.get('subjects', [])
        for s in subjects:
            findings.append(f'  {s.get(\"kind\", \"?\")}:{s.get(\"namespace\", \"cluster\")}/{s.get(\"name\", \"?\")} -> cluster-admin via {binding[\"metadata\"][\"name\"]}')
print(f'    cluster-admin bindings: {len(findings)}')
for f in findings:
    print(f)
" 2>/dev/null
echo ""

# --- Service accounts with automounted tokens ---
echo "[*] Checking service account token automount..."
kubectl get pods $NS_FLAG -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    automount = pod['spec'].get('automountServiceAccountToken', True)
    if automount:
        sa = pod['spec'].get('serviceAccountName', 'default')
        if sa == 'default':
            count += 1
            print(f'  DEFAULT-SA+AUTOMOUNT: {ns}/{name}')
print(f'    Pods using default SA with automount: {count}')
" 2>/dev/null
echo ""

# --- Wildcard permissions ---
echo "[*] Checking for wildcard permissions in ClusterRoles..."
kubectl get clusterroles -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
findings = []
for role in data.get('items', []):
    name = role['metadata']['name']
    # Skip system roles
    if name.startswith('system:'):
        continue
    for rule in role.get('rules', []):
        verbs = rule.get('verbs', [])
        resources = rule.get('resources', [])
        api_groups = rule.get('apiGroups', [])
        if '*' in verbs or '*' in resources:
            findings.append(f'  {name}: verbs={verbs} resources={resources}')
print(f'    ClusterRoles with wildcards: {len(findings)}')
for f in findings[:20]:
    print(f)
if len(findings) > 20:
    print(f'    ... and {len(findings) - 20} more')
" 2>/dev/null
echo ""

# --- Save full RBAC dump ---
echo "[*] Saving full RBAC dump..."
kubectl get clusterroles,clusterrolebindings,roles,rolebindings $NS_FLAG -o json > "$OUTPUT_DIR/rbac-dump.json" 2>/dev/null || true
echo "    Full dump: $OUTPUT_DIR/rbac-dump.json"

echo ""
echo "=== RBAC scan complete ==="
echo ""
echo "Key risks to fix:"
echo "  1. Remove unnecessary cluster-admin bindings"
echo "  2. Set automountServiceAccountToken: false on pods that don't need API access"
echo "  3. Replace wildcard verbs/resources with specific permissions"
echo ""
echo "Note: Wiz's RBAC analysis connects over-permissioned SAs to the workloads"
echo "using them and the cloud resources they can reach. That graph view is the"
echo "20% open source can't replicate."
