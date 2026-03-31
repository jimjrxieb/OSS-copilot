#!/usr/bin/env bash
set -euo pipefail

# scan-dependencies.sh — Dependency CVE scanning with Trivy and Grype
# Usage: ./scan-dependencies.sh /path/to/repo [--output /path/to/output]

TARGET="${1:-.}"
OUTPUT_DIR=""

# Parse --output flag
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        *) shift ;;
    esac
done

OUTPUT_DIR="${OUTPUT_DIR:-${TARGET}/.oss-copilot/code}"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: Dependency Security Scan ==="
echo "Target: $TARGET"
echo "Output: $OUTPUT_DIR"
echo ""

# --- Trivy filesystem scan ---
if command -v trivy &>/dev/null; then
    echo "[*] Running Trivy (dependency CVEs)..."
    trivy fs \
        --format json \
        --output "$OUTPUT_DIR/trivy-deps-results.json" \
        --severity HIGH,CRITICAL \
        --skip-dirs .oss-copilot \
        --skip-dirs node_modules \
        --skip-dirs .terraform \
        --skip-dirs vendor \
        "$TARGET" 2>/dev/null || true

    TRIVY_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OUTPUT_DIR/trivy-deps-results.json'))
    total = sum(len(r.get('Vulnerabilities', [])) for r in data.get('Results', []))
    print(total)
except: print('0')
" 2>/dev/null)
    echo "    Trivy findings (HIGH+CRITICAL): $TRIVY_COUNT"
    echo "    Results: $OUTPUT_DIR/trivy-deps-results.json"
else
    echo "[!] Trivy not found. Install: brew install trivy"
fi

echo ""

# --- Grype ---
if command -v grype &>/dev/null; then
    echo "[*] Running Grype (dependency CVEs)..."
    grype "dir:$TARGET" \
        --output json \
        --file "$OUTPUT_DIR/grype-results.json" \
        --only-fixed \
        2>/dev/null || true

    GRYPE_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OUTPUT_DIR/grype-results.json'))
    print(len(data.get('matches', [])))
except: print('0')
" 2>/dev/null)
    echo "    Grype findings (fixable): $GRYPE_COUNT"
    echo "    Results: $OUTPUT_DIR/grype-results.json"
else
    echo "[!] Grype not found. Install: brew install grype"
fi

echo ""

# --- pip-audit (Python) ---
if command -v pip-audit &>/dev/null; then
    if [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/pyproject.toml" ]; then
        echo "[*] Running pip-audit (Python dependencies)..."
        pip-audit \
            --requirement "$TARGET/requirements.txt" \
            --format json \
            --output "$OUTPUT_DIR/pip-audit-results.json" \
            2>/dev/null || true
        echo "    Results: $OUTPUT_DIR/pip-audit-results.json"
    fi
fi

echo ""
echo "=== Dependency scan complete ==="
echo ""
echo "Next steps:"
echo "  1. Fix CRITICAL CVEs first — these have known exploits"
echo "  2. Focus on fixable vulnerabilities (Grype --only-fixed filters to these)"
echo "  3. For unfixable CVEs: check if the vulnerable code path is reachable"
echo "     (this is where Snyk's reachability analysis adds value over OSS)"
