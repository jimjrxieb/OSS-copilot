#!/usr/bin/env bash
set -euo pipefail

# download-model.sh — Pull trained model from S3 to local model-registry
# Usage: ./download-model.sh <job-name>

JOB_NAME="${1:?Usage: download-model.sh <job-name>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_DIR="${SCRIPT_DIR}/../../model-registry"

# Get model output path
OUTPUT=$(aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query 'ModelArtifacts.S3ModelArtifacts' --output text)

if [[ -z "$OUTPUT" || "$OUTPUT" == "None" ]]; then
    echo "[ERROR] No model artifacts found for job: $JOB_NAME"
    echo "        Job may not have completed successfully."
    exit 1
fi

# Download
DEST="${REGISTRY_DIR}/challenger/${JOB_NAME}"
mkdir -p "$DEST"

echo "=== Download Model Artifacts ==="
echo "  Source: $OUTPUT"
echo "  Dest:   $DEST/"
echo ""

aws s3 cp "$OUTPUT" "$DEST/model.tar.gz"

# Extract
echo "[*] Extracting..."
cd "$DEST"
tar -xzf model.tar.gz
rm model.tar.gz

echo ""
echo "=== Download Complete ==="
echo "  Location: $DEST/"
echo "  Files:"
ls -la "$DEST/"
echo ""
echo "Next steps:"
echo "  1. Merge LoRA into base model (if LoRA adapter)"
echo "  2. Convert to GGUF: python3 local-pipeline/tools/convert_gguf.py (when implemented)"
echo "  3. Evaluate: move to testing-pipeline/"
echo "  4. Promote to model-registry/champion/ if it passes"
