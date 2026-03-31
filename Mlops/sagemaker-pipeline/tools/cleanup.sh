#!/usr/bin/env bash
set -euo pipefail

# cleanup.sh — Delete SageMaker resources to stop billing
# Usage: ./cleanup.sh [--all] [--endpoint NAME] [--job NAME]
#
# IMPORTANT: Running endpoints cost $0.74+/hr even when idle.
# Run this when you're done to stop charges.

echo "=== SageMaker Cleanup ==="
echo ""

# List running endpoints
echo "[*] Running endpoints (each costs \$0.74+/hr):"
ENDPOINTS=$(aws sagemaker list-endpoints --status-equals InService \
    --query 'Endpoints[*].EndpointName' --output text 2>/dev/null)
if [[ -z "$ENDPOINTS" ]]; then
    echo "    None."
else
    for ep in $ENDPOINTS; do
        echo "    $ep"
    done
fi

# List running notebook instances
echo ""
echo "[*] Running notebook instances:"
NOTEBOOKS=$(aws sagemaker list-notebook-instances --status-equals InService \
    --query 'NotebookInstances[*].[NotebookInstanceName,InstanceType]' --output text 2>/dev/null)
if [[ -z "$NOTEBOOKS" ]]; then
    echo "    None."
else
    echo "$NOTEBOOKS" | while read name type; do
        echo "    $name ($type)"
    done
fi

# List recent training jobs
echo ""
echo "[*] Recent training jobs:"
aws sagemaker list-training-jobs --max-results 5 \
    --query 'TrainingJobSummaries[*].[TrainingJobName,TrainingJobStatus]' --output table 2>/dev/null

echo ""

# Parse args
if [[ "${1:-}" == "--all" ]]; then
    echo "[*] Deleting ALL endpoints..."
    for ep in $ENDPOINTS; do
        echo "    Deleting endpoint: $ep"
        aws sagemaker delete-endpoint --endpoint-name "$ep"

        # Try to delete config and model with same name pattern
        aws sagemaker delete-endpoint-config --endpoint-config-name "${ep}-config" 2>/dev/null || true
    done
    echo "    Done."

elif [[ "${1:-}" == "--endpoint" ]]; then
    EP="${2:?Usage: cleanup.sh --endpoint NAME}"
    echo "[*] Deleting endpoint: $EP"
    aws sagemaker delete-endpoint --endpoint-name "$EP"
    echo "    Deleted. Billing stopped."

else
    echo "Options:"
    echo "  ./cleanup.sh --all                  Delete all endpoints"
    echo "  ./cleanup.sh --endpoint NAME        Delete specific endpoint"
    echo ""
    echo "To stop training jobs:"
    echo "  aws sagemaker stop-training-job --training-job-name JOB_NAME"
fi
