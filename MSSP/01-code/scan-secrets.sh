#!/usr/bin/env bash
set -euo pipefail

# scan-secrets.sh — Secret detection with Gitleaks
# Usage: ./scan-secrets.sh /path/to/repo

TARGET="${1:-.}"
OUTPUT_DIR="${TARGET}/.oss-copilot/code"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: Secret Detection Scan ==="
echo "Target: $TARGET"
echo "Output: $OUTPUT_DIR"
echo ""

# --- Gitleaks ---
if command -v gitleaks &>/dev/null; then
    echo "[*] Running Gitleaks (current state)..."
    gitleaks detect \
        --source "$TARGET" \
        --report-path "$OUTPUT_DIR/gitleaks-results.json" \
        --report-format json \
        --no-banner \
        2>/dev/null || true

    GITLEAKS_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OUTPUT_DIR/gitleaks-results.json'))
    print(len(data) if isinstance(data, list) else 0)
except: print('0')
" 2>/dev/null)
    echo "    Gitleaks findings: $GITLEAKS_COUNT"
    echo "    Results: $OUTPUT_DIR/gitleaks-results.json"

    echo ""

    # Git history scan (slower, catches rotated secrets)
    if [ -d "$TARGET/.git" ]; then
        echo "[*] Running Gitleaks (git history)..."
        gitleaks detect \
            --source "$TARGET" \
            --report-path "$OUTPUT_DIR/gitleaks-history-results.json" \
            --report-format json \
            --log-opts="--all" \
            --no-banner \
            2>/dev/null || true

        HISTORY_COUNT=$(python3 -c "
import json, sys
try:
    data = json.load(open('$OUTPUT_DIR/gitleaks-history-results.json'))
    print(len(data) if isinstance(data, list) else 0)
except: print('0')
" 2>/dev/null)
        echo "    History findings: $HISTORY_COUNT"
        echo "    Results: $OUTPUT_DIR/gitleaks-history-results.json"
    fi
else
    echo "[!] Gitleaks not found. Install: brew install gitleaks"
fi

echo ""
echo "=== Secret scan complete ==="
echo ""
echo "If secrets were found:"
echo "  1. Rotate the credential immediately"
echo "  2. Remove from code and use environment variables or a secrets manager"
echo "  3. If in git history: consider git-filter-repo to purge"
echo ""
echo "Note: Gitleaks catches ~90% of what GitGuardian catches on current branch."
echo "GitGuardian's advantage is historical scanning across all branches and"
echo "monitoring public GitHub for your org's leaked credentials."
