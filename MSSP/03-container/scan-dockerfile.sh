#!/usr/bin/env bash
set -euo pipefail

# scan-dockerfile.sh — Dockerfile linting with Hadolint
# Usage: ./scan-dockerfile.sh /path/to/Dockerfile
# Usage: ./scan-dockerfile.sh /path/to/repo  (finds all Dockerfiles)

TARGET="${1:-.}"
OUTPUT_DIR=".oss-copilot/container"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: Dockerfile Lint ==="
echo "Target: $TARGET"
echo ""

if ! command -v hadolint &>/dev/null; then
    echo "[!] Hadolint not found. Install: brew install hadolint"
    exit 1
fi

# Find Dockerfiles
DOCKERFILES=()
if [ -f "$TARGET" ]; then
    DOCKERFILES=("$TARGET")
else
    mapfile -t DOCKERFILES < <(find "$TARGET" -name "Dockerfile*" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)
fi

if [ ${#DOCKERFILES[@]} -eq 0 ]; then
    echo "[*] No Dockerfiles found in $TARGET"
    exit 0
fi

echo "Found ${#DOCKERFILES[@]} Dockerfile(s)"
echo ""

TOTAL_WARNINGS=0

for DF in "${DOCKERFILES[@]}"; do
    echo "--- $DF ---"

    # Hadolint
    hadolint "$DF" --format json > "$OUTPUT_DIR/hadolint-$(basename "$DF").json" 2>/dev/null || true

    COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/hadolint-$(basename "$DF").json'))
    print(len(data) if isinstance(data, list) else 0)
except: print('0')
" 2>/dev/null)
    echo "    Hadolint findings: $COUNT"
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + COUNT))

    # Quick checks that Hadolint might miss
    if ! grep -q "^USER" "$DF" 2>/dev/null; then
        echo "    [WARN] No USER instruction — container runs as root"
    fi
    if ! grep -q "^HEALTHCHECK" "$DF" 2>/dev/null; then
        echo "    [WARN] No HEALTHCHECK instruction"
    fi
    if grep -q ":latest" "$DF" 2>/dev/null; then
        echo "    [WARN] Uses :latest tag — pin to specific version"
    fi

    echo ""
done

echo "=== Dockerfile lint complete ==="
echo "Total findings: $TOTAL_WARNINGS"
echo ""
echo "Common fixes:"
echo "  - Add 'USER nonroot' before CMD/ENTRYPOINT"
echo "  - Pin base image versions (FROM node:20.11.1-alpine, not FROM node:latest)"
echo "  - Add HEALTHCHECK for orchestrator integration"
echo "  - Add .dockerignore to reduce image size"
