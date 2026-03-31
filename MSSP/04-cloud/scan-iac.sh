#!/usr/bin/env bash
set -euo pipefail

# scan-iac.sh — Infrastructure-as-Code security scanning
# Usage: ./scan-iac.sh /path/to/terraform
# Usage: ./scan-iac.sh /path/to/cloudformation

TARGET="${1:-.}"
OUTPUT_DIR=".oss-copilot/cloud"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: IaC Security Scan ==="
echo "Target: $TARGET"
echo "Output: $OUTPUT_DIR"
echo ""

# --- Checkov ---
if command -v checkov &>/dev/null; then
    echo "[*] Running Checkov (multi-framework IaC scan)..."
    checkov \
        --directory "$TARGET" \
        --output json \
        --output-file-path "$OUTPUT_DIR" \
        --quiet \
        2>/dev/null || true

    if [ -f "$OUTPUT_DIR/results_json.json" ]; then
        python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/results_json.json'))
    if isinstance(data, list):
        for check_type in data:
            passed = check_type.get('summary', {}).get('passed', 0)
            failed = check_type.get('summary', {}).get('failed', 0)
            ct = check_type.get('check_type', 'unknown')
            print(f'    {ct}: PASS={passed} FAIL={failed}')
    else:
        passed = data.get('summary', {}).get('passed', 0)
        failed = data.get('summary', {}).get('failed', 0)
        print(f'    PASS: {passed}  FAIL: {failed}')
except Exception as e:
    print(f'    Error: {e}')
" 2>/dev/null
    fi
    echo "    Results: $OUTPUT_DIR/"
else
    echo "[!] Checkov not found. Install: pip install checkov"
fi

echo ""

# --- tfsec ---
if command -v tfsec &>/dev/null; then
    if ls "$TARGET"/*.tf 1>/dev/null 2>&1 || find "$TARGET" -name "*.tf" -print -quit 2>/dev/null | grep -q .; then
        echo "[*] Running tfsec (Terraform-specific)..."
        tfsec "$TARGET" \
            --format json \
            --out "$OUTPUT_DIR/tfsec-results.json" \
            2>/dev/null || true

        TFSEC_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/tfsec-results.json'))
    print(len(data.get('results', [])))
except: print('0')
" 2>/dev/null)
        echo "    tfsec findings: $TFSEC_COUNT"
        echo "    Results: $OUTPUT_DIR/tfsec-results.json"
    else
        echo "[*] tfsec: No Terraform files found, skipping."
    fi
else
    echo "[!] tfsec not found. Install: brew install tfsec"
fi

echo ""

# --- Trivy config ---
if command -v trivy &>/dev/null; then
    echo "[*] Running Trivy config scan..."
    trivy config \
        --format json \
        --output "$OUTPUT_DIR/trivy-iac-results.json" \
        "$TARGET" 2>/dev/null || true

    TRIVY_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/trivy-iac-results.json'))
    total = sum(len(r.get('Misconfigurations', [])) for r in data.get('Results', []))
    print(total)
except: print('0')
" 2>/dev/null)
    echo "    Trivy misconfigurations: $TRIVY_COUNT"
    echo "    Results: $OUTPUT_DIR/trivy-iac-results.json"
fi

echo ""
echo "=== IaC scan complete ==="
echo ""
echo "Next steps:"
echo "  1. Fix findings before applying Terraform (shift-left)"
echo "  2. Add Checkov/tfsec to CI pipeline to prevent misconfigs from merging"
echo "  3. For drift detection (applied infra vs IaC), you need Wiz or Prisma Cloud"
