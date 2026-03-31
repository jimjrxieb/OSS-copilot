#!/usr/bin/env bash
set -euo pipefail

# monitor-job.sh — Watch a SageMaker training job until completion
# Usage: ./monitor-job.sh <job-name>

JOB_NAME="${1:?Usage: monitor-job.sh <job-name>}"

echo "=== Monitoring: $JOB_NAME ==="
echo ""

while true; do
    RESULT=$(aws sagemaker describe-training-job \
        --training-job-name "$JOB_NAME" \
        --query '[TrainingJobStatus, SecondaryStatus, TrainingTimeInSeconds]' \
        --output text 2>/dev/null)

    STATUS=$(echo "$RESULT" | awk '{print $1}')
    SECONDARY=$(echo "$RESULT" | awk '{print $2}')
    SECONDS=$(echo "$RESULT" | awk '{print $3}')

    echo "$(date +%H:%M:%S) | Status: $STATUS | Phase: $SECONDARY | Time: ${SECONDS}s"

    case "$STATUS" in
        Completed)
            echo ""
            echo "=== Training Complete ==="

            # Show cost info
            BILLABLE=$(aws sagemaker describe-training-job \
                --training-job-name "$JOB_NAME" \
                --query 'BillableTimeInSeconds' --output text)
            echo "  Training time: ${SECONDS}s"
            echo "  Billable time: ${BILLABLE}s"
            if [[ "$BILLABLE" -lt "$SECONDS" ]]; then
                SAVINGS=$(( (SECONDS - BILLABLE) * 100 / SECONDS ))
                echo "  Spot savings:  ${SAVINGS}%"
            fi

            # Show output location
            OUTPUT=$(aws sagemaker describe-training-job \
                --training-job-name "$JOB_NAME" \
                --query 'ModelArtifacts.S3ModelArtifacts' --output text)
            echo ""
            echo "  Model: $OUTPUT"
            echo ""
            echo "Download:"
            echo "  bash tools/download-model.sh $JOB_NAME"
            break
            ;;
        Failed)
            echo ""
            echo "=== Training FAILED ==="
            REASON=$(aws sagemaker describe-training-job \
                --training-job-name "$JOB_NAME" \
                --query 'FailureReason' --output text)
            echo "  Reason: $REASON"
            echo ""
            echo "Check logs:"
            echo "  aws logs tail /aws/sagemaker/TrainingJobs --log-stream-name-prefix $JOB_NAME --follow"
            exit 1
            ;;
        Stopped)
            echo ""
            echo "=== Training Stopped ==="
            exit 1
            ;;
    esac

    sleep 30
done
