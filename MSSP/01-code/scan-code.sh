#!/usr/bin/env bash
set -euo pipefail

# scan-code.sh — SAST scanning with Semgrep and Bandit
# Usage: ./scan-code.sh /path/to/repo [--output /path/to/output]

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

echo "=== OSS-Copilot: Code Security Scan ==="
echo "Target: $TARGET"
echo "Output: $OUTPUT_DIR"
echo ""

# --- Semgrep ---
if command -v semgrep &>/dev/null; then
    echo "[*] Running Semgrep (SAST)..."
    semgrep scan \
        --config=auto \
        --json \
        --output "$OUTPUT_DIR/semgrep-results.json" \
        --exclude=".oss-copilot" \
        --exclude="node_modules" \
        --exclude=".terraform" \
        --exclude="vendor" \
        --exclude="venv" \
        --exclude=".venv" \
        "$TARGET" 2>/dev/null || true

    SEMGREP_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OUTPUT_DIR/semgrep-results.json'))
    print(len(data.get('results', [])))
except: print('0')
" 2>/dev/null)
    echo "    Semgrep findings: $SEMGREP_COUNT"
    echo "    Results: $OUTPUT_DIR/semgrep-results.json"
else
    echo "[!] Semgrep not found. Install: pip install semgrep"
fi

echo ""

# --- Bandit (Python only) ---
if command -v bandit &>/dev/null; then
    PYTHON_FILES=$(find "$TARGET" -name "*.py" -not -path "*/venv/*" -not -path "*/.venv/*" -not -path "*/node_modules/*" -not -path "*/.oss-copilot/*" 2>/dev/null | head -1)
    if [ -n "$PYTHON_FILES" ]; then
        echo "[*] Running Bandit (Python SAST)..."
        bandit -r "$TARGET" \
            -f json \
            -o "$OUTPUT_DIR/bandit-results.json" \
            --exclude "*/venv/*,*/.venv/*,*/node_modules/*,*/.oss-copilot/*" \
            2>/dev/null || true

        BANDIT_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OUTPUT_DIR/bandit-results.json'))
    print(len(data.get('results', [])))
except: print('0')
" 2>/dev/null)
        echo "    Bandit findings: $BANDIT_COUNT"
        echo "    Results: $OUTPUT_DIR/bandit-results.json"
    else
        echo "[*] Bandit: No Python files found, skipping."
    fi
else
    echo "[!] Bandit not found. Install: pip install bandit"
fi

echo ""
echo "=== Code scan complete ==="
echo ""
echo "Next steps:"
echo "  1. Review findings: cat $OUTPUT_DIR/semgrep-results.json | python3 -m json.tool"
echo "  2. Scan for secrets: ./scan-secrets.sh $TARGET --output $OUTPUT_DIR"
echo "  3. Scan dependencies: ./scan-dependencies.sh $TARGET --output $OUTPUT_DIR"
