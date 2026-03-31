#!/usr/bin/env bash
set -euo pipefail

# scan-policies.sh — Admission control and policy posture
# Usage: ./scan-policies.sh
# Requires: kubectl access to a cluster

OUTPUT_DIR=".oss-copilot/cluster"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: Policy & Admission Control Scan ==="
echo ""

if ! command -v kubectl &>/dev/null; then
    echo "[!] kubectl not found. This script requires cluster access."
    exit 1
fi

# --- Pod Security Standards ---
echo "[*] Checking Pod Security Standards (PSA) labels..."
kubectl get namespaces -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
enforced = 0
not_enforced = 0
for ns in data.get('items', []):
    name = ns['metadata']['name']
    labels = ns['metadata'].get('labels', {})
    enforce = labels.get('pod-security.kubernetes.io/enforce', '')
    if enforce:
        enforced += 1
        print(f'  {name}: enforce={enforce}')
    else:
        if not name.startswith('kube-'):
            not_enforced += 1
            print(f'  {name}: NO PSA enforcement')
print(f'')
print(f'    Enforced: {enforced}  Not enforced: {not_enforced}')
" 2>/dev/null
echo ""

# --- Kyverno ---
echo "[*] Checking Kyverno policies..."
if kubectl api-resources 2>/dev/null | grep -q kyverno; then
    KYVERNO_POLICIES=$(kubectl get clusterpolicies,policies --all-namespaces --no-headers 2>/dev/null | wc -l)
    echo "    Kyverno policies deployed: $KYVERNO_POLICIES"
    kubectl get clusterpolicies --no-headers 2>/dev/null | while read -r line; do
        echo "    ClusterPolicy: $line"
    done
else
    echo "    Kyverno: NOT INSTALLED"
    echo "    Install: helm install kyverno kyverno/kyverno -n kyverno --create-namespace"
fi
echo ""

# --- Gatekeeper/OPA ---
echo "[*] Checking Gatekeeper/OPA..."
if kubectl api-resources 2>/dev/null | grep -q constraints.gatekeeper; then
    CONSTRAINTS=$(kubectl get constraints --no-headers 2>/dev/null | wc -l)
    TEMPLATES=$(kubectl get constrainttemplates --no-headers 2>/dev/null | wc -l)
    echo "    Gatekeeper templates: $TEMPLATES"
    echo "    Gatekeeper constraints: $CONSTRAINTS"

    # Check for violations
    echo "    Checking constraint violations..."
    kubectl get constraints -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
total_violations = 0
for item in data.get('items', []):
    name = item['metadata']['name']
    violations = item.get('status', {}).get('totalViolations', 0)
    if violations > 0:
        total_violations += violations
        print(f'      {name}: {violations} violations')
print(f'    Total violations: {total_violations}')
" 2>/dev/null
else
    echo "    Gatekeeper: NOT INSTALLED"
    echo "    Install: helm install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace"
fi
echo ""

# --- Polaris ---
if command -v polaris &>/dev/null; then
    echo "[*] Running Polaris audit..."
    polaris audit --format json > "$OUTPUT_DIR/polaris-results.json" 2>/dev/null || true

    python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/polaris-results.json'))
    score = data.get('ClusterInfo', {}).get('Score', 'N/A')
    print(f'    Polaris score: {score}/100')
except Exception as e:
    print(f'    Error: {e}')
" 2>/dev/null
    echo "    Results: $OUTPUT_DIR/polaris-results.json"
else
    echo "[*] Polaris not found. Install: brew install polaris"
fi

echo ""
echo "=== Policy scan complete ==="
echo ""
echo "Recommendations:"
echo "  1. Apply PSA labels to all non-system namespaces (at minimum: warn)"
echo "  2. Deploy Kyverno or Gatekeeper for admission control"
echo "  3. Start with 'audit' mode policies, then move to 'enforce'"
echo "  4. Target Polaris score >80 for production clusters"
