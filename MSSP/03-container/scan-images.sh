#!/usr/bin/env bash
set -euo pipefail

# scan-images.sh — Container image CVE scanning with Trivy and Grype
# Usage: ./scan-images.sh image1:tag image2:tag ...
# Usage: ./scan-images.sh  (scans all images in current cluster)

OUTPUT_DIR=".oss-copilot/container"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: Container Image Scan ==="
echo "Output: $OUTPUT_DIR"
echo ""

# If no args, try to get images from the cluster
IMAGES=("$@")
if [ ${#IMAGES[@]} -eq 0 ]; then
    if command -v kubectl &>/dev/null; then
        echo "[*] No images specified. Fetching from cluster..."
        mapfile -t IMAGES < <(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | sort -u)
        echo "    Found ${#IMAGES[@]} unique images in cluster"
    else
        echo "[!] No images specified and kubectl not available."
        echo "    Usage: ./scan-images.sh nginx:1.25 my-app:latest"
        exit 1
    fi
fi

echo ""

for IMAGE in "${IMAGES[@]}"; do
    SAFE_NAME=$(echo "$IMAGE" | tr '/:' '_')

    echo "--- Scanning: $IMAGE ---"

    # --- Trivy ---
    if command -v trivy &>/dev/null; then
        echo "[*] Trivy scan..."
        trivy image \
            --format json \
            --output "$OUTPUT_DIR/trivy-${SAFE_NAME}.json" \
            --severity HIGH,CRITICAL \
            "$IMAGE" 2>/dev/null || true

        TRIVY_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/trivy-${SAFE_NAME}.json'))
    total = sum(len(r.get('Vulnerabilities', [])) for r in data.get('Results', []))
    print(total)
except: print('0')
" 2>/dev/null)
        echo "    Trivy HIGH+CRITICAL: $TRIVY_COUNT"
    fi

    # --- Grype ---
    if command -v grype &>/dev/null; then
        echo "[*] Grype scan..."
        grype "$IMAGE" \
            --output json \
            --file "$OUTPUT_DIR/grype-${SAFE_NAME}.json" \
            --only-fixed \
            2>/dev/null || true

        GRYPE_COUNT=$(python3 -c "
import json
try:
    data = json.load(open('$OUTPUT_DIR/grype-${SAFE_NAME}.json'))
    print(len(data.get('matches', [])))
except: print('0')
" 2>/dev/null)
        echo "    Grype fixable: $GRYPE_COUNT"
    fi

    echo ""
done

echo "=== Image scan complete ==="
echo ""
echo "Next steps:"
echo "  1. Fix CRITICAL CVEs by updating base images or pinning patched versions"
echo "  2. Run ./scan-dockerfile.sh to check Dockerfile best practices"
echo "  3. Results in: $OUTPUT_DIR/"
