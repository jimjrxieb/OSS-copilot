#!/usr/bin/env bash
set -euo pipefail

# submit-job.sh — Upload data + submit SageMaker training job
# Usage: ./submit-job.sh chunk_0001_5k.jsonl [--spot] [--instance ml.g5.xlarge]
#
# Reads config from values.yaml. Uploads chunk to S3, submits training job.

CHUNK_FILE="${1:?Usage: submit-job.sh <chunk_file.jsonl> [--spot] [--instance type]}"
SPOT=true
INSTANCE="ml.g4dn.xlarge"

shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --spot) SPOT=true; shift ;;
        --no-spot) SPOT=false; shift ;;
        --instance) INSTANCE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(dirname "$SCRIPT_DIR")"
CHUNK_DIR="${PIPELINE_DIR}/../local-pipeline/03-chunked-untrained"
CHUNK_PATH="${CHUNK_DIR}/${CHUNK_FILE}"

if [[ ! -f "$CHUNK_PATH" ]]; then
    echo "[ERROR] Chunk not found: $CHUNK_PATH"
    echo "        Available chunks:"
    ls "$CHUNK_DIR"/*.jsonl 2>/dev/null || echo "        None"
    exit 1
fi

# AWS config
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="ml-training-${ACCOUNT_ID}-${REGION}"
ROLE_ARN=$(aws iam get-role --role-name SageMakerTrainingRole --query 'Role.Arn' --output text)
JOB_NAME="lora-finetune-$(date +%Y%m%d-%H%M%S)"
IMAGE="763104351884.dkr.ecr.${REGION}.amazonaws.com/huggingface-pytorch-training:2.3.0-transformers4.43.4-gpu-py311-cu121-ubuntu22.04"

echo "=== Submit SageMaker Training Job ==="
echo "  Chunk:    $CHUNK_FILE"
echo "  Instance: $INSTANCE"
echo "  Spot:     $SPOT"
echo "  Job:      $JOB_NAME"
echo "  Bucket:   $BUCKET"
echo ""

# Upload chunk to S3
echo "[*] Uploading $CHUNK_FILE to S3..."
aws s3 cp "$CHUNK_PATH" "s3://${BUCKET}/training-data/${CHUNK_FILE}"

# Build spot config
SPOT_FLAG=""
STOP_CONDITION="MaxRuntimeInSeconds=3600"
if $SPOT; then
    SPOT_FLAG="--enable-managed-spot-training"
    STOP_CONDITION="MaxRuntimeInSeconds=3600,MaxWaitTimeInSeconds=7200"
fi

# Submit job
echo "[*] Submitting training job..."
aws sagemaker create-training-job \
    --training-job-name "$JOB_NAME" \
    --role-arn "$ROLE_ARN" \
    --algorithm-specification \
        TrainingImage="$IMAGE",TrainingInputMode=File \
    --resource-config \
        InstanceType="$INSTANCE",InstanceCount=1,VolumeSizeInGB=50 \
    --input-data-config '[{
        "ChannelName": "training",
        "DataSource": {
            "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://'"$BUCKET"'/training-data/",
                "S3DataDistributionType": "FullyReplicated"
            }
        }
    }]' \
    --output-data-config \
        S3OutputPath="s3://${BUCKET}/model-output/" \
    --hyperparameters '{
        "model_name": "unsloth/Llama-3.2-3B-Instruct",
        "lora_r": "64",
        "lora_alpha": "128",
        "epochs": "2",
        "batch_size": "4",
        "learning_rate": "2e-5",
        "max_seq_length": "2048",
        "gradient_accumulation_steps": "8"
    }' \
    --stopping-condition "$STOP_CONDITION" \
    $SPOT_FLAG \
    --region "$REGION"

echo ""
echo "=== Job Submitted ==="
echo "  Name: $JOB_NAME"
echo ""
echo "Monitor:"
echo "  bash tools/monitor-job.sh $JOB_NAME"
echo ""
echo "Or manually:"
echo "  aws sagemaker describe-training-job --training-job-name $JOB_NAME --query TrainingJobStatus"
