#!/usr/bin/env bash
set -euo pipefail

# scan-cis.sh — CIS Kubernetes Benchmark with kube-bench and Kubescape
# Usage: ./scan-cis.sh
# Requires: kubectl access to a cluster

OUTPUT_DIR=".oss-copilot/cluster"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: CIS Kubernetes Benchmark ==="
echo ""

# --- kube-bench ---
if command -v kube-bench &>/dev/null; then
    echo "[*] Running kube-bench (CIS Benchmark)..."
    kube-bench run --json > "$OUTPUT_DIR/kube-bench-results.json" 2>/dev/null || true

    python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/kube-bench-results.json'))
    total_pass = sum(t.get('total_pass', 0) for t in data.get('Controls', []))
    total_fail = sum(t.get('total_fail', 0) for t in data.get('Controls', []))
    total_warn = sum(t.get('total_warn', 0) for t in data.get('Controls', []))
    print(f'    PASS: {total_pass}  FAIL: {total_fail}  WARN: {total_warn}')
except Exception as e:
    print(f'    Error parsing results: {e}')
" 2>/dev/null
    echo "    Results: $OUTPUT_DIR/kube-bench-results.json"
else
    echo "[!] kube-bench not found."
    echo "    Install: brew install kube-bench"
    echo "    Or run in-cluster: kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml"
fi

echo ""

# --- Kubescape ---
if command -v kubescape &>/dev/null; then
    echo "[*] Running Kubescape (NSA/CISA + CIS)..."
    kubescape scan framework cis-v1.23-t1.0.1 \
        --format json \
        --output "$OUTPUT_DIR/kubescape-cis-results.json" \
        2>/dev/null || true

    python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/kubescape-cis-results.json'))
    score = data.get('summaryDetails', {}).get('complianceScore', 'N/A')
    failed = data.get('summaryDetails', {}).get('failedResources', 0)
    print(f'    Compliance score: {score}%')
    print(f'    Failed resources: {failed}')
except Exception as e:
    print(f'    Error parsing results: {e}')
" 2>/dev/null
    echo "    Results: $OUTPUT_DIR/kubescape-cis-results.json"

    echo ""
    echo "[*] Running Kubescape (NSA hardening)..."
    kubescape scan framework nsa \
        --format json \
        --output "$OUTPUT_DIR/kubescape-nsa-results.json" \
        2>/dev/null || true
    echo "    Results: $OUTPUT_DIR/kubescape-nsa-results.json"
else
    echo "[!] Kubescape not found."
    echo "    Install: curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | bash"
fi

echo ""
echo "=== CIS scan complete ==="
echo ""
echo "Next steps:"
echo "  1. Fix FAIL items from kube-bench (these are CIS violations)"
echo "  2. Review WARN items (manual verification needed)"
echo "  3. Run ./scan-rbac.sh to check RBAC permissions"
