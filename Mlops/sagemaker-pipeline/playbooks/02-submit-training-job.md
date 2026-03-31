# Playbook 02: Submit Training Job

> Upload your data to S3 and launch a SageMaker training job on a GPU.
> Spot instances make this cost $0.10-$0.25 per chunk.
>
> **Time:** ~10 minutes (upload + submit)
> **Prerequisites:** IAM role + S3 bucket from [01-setup-iam-s3.md](01-setup-iam-s3.md)

---

## Step 1: Upload Training Data to S3

```bash
# Your chunked training data (from local-pipeline)
CHUNK="../local-pipeline/03-chunked-untrained/chunk_0001_5k.jsonl"
BUCKET="ml-training-123456789012-us-east-1"  # From values.yaml

# Upload
aws s3 cp "$CHUNK" "s3://${BUCKET}/training-data/"

# Verify
aws s3 ls "s3://${BUCKET}/training-data/"
```

---

## Step 2: Submit the Training Job

### AWS CLI (recommended — scriptable):

```bash
ROLE_ARN=$(aws iam get-role --role-name SageMakerTrainingRole --query 'Role.Arn' --output text)
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="ml-training-${ACCOUNT_ID}-${REGION}"
JOB_NAME="lora-finetune-$(date +%Y%m%d-%H%M%S)"

# HuggingFace Deep Learning Container (PyTorch 2.3 + CUDA 12.1)
IMAGE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/huggingface-pytorch-training:2.3.0-transformers4.43.4-gpu-py311-cu121-ubuntu22.04"
# Or use the AWS-managed image:
IMAGE="763104351884.dkr.ecr.${REGION}.amazonaws.com/huggingface-pytorch-training:2.3.0-transformers4.43.4-gpu-py311-cu121-ubuntu22.04"

aws sagemaker create-training-job \
    --training-job-name "$JOB_NAME" \
    --role-arn "$ROLE_ARN" \
    --algorithm-specification \
        TrainingImage="$IMAGE",TrainingInputMode=File \
    --resource-config \
        InstanceType=ml.g4dn.xlarge,InstanceCount=1,VolumeSizeInGB=50 \
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
    --stopping-condition MaxRuntimeInSeconds=3600 \
    --enable-managed-spot-training \
    --region "$REGION"

echo "Job submitted: $JOB_NAME"
echo "Monitor: aws sagemaker describe-training-job --training-job-name $JOB_NAME"
```

### With Spot Instances (60-90% cheaper):

The `--enable-managed-spot-training` flag tells SageMaker to use spot instances.
If the spot instance gets interrupted, SageMaker automatically resumes from
the last checkpoint. You need to add:

```bash
    --enable-managed-spot-training \
    --stopping-condition MaxRuntimeInSeconds=3600,MaxWaitTimeInSeconds=7200 \
    --checkpoint-config S3Uri="s3://${BUCKET}/checkpoints/${JOB_NAME}/"
```

`MaxWaitTimeInSeconds` is how long to wait for a spot instance. Set it to 2x
the expected training time.

### Console:

```
SageMaker → Training → Training jobs → Create training job

  Job name: lora-finetune-20260331
  IAM role: SageMakerTrainingRole

  Algorithm: Custom → Training image URI
    Image: 763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-training:2.3.0-...

  Resource configuration:
    Instance type: ml.g4dn.xlarge
    Instance count: 1
    Volume size: 50 GB

  Managed spot training: Enabled
  Maximum runtime: 3600 seconds
  Maximum wait time: 7200 seconds

  Input data:
    Channel: training
    S3 location: s3://your-bucket/training-data/

  Output data:
    S3 location: s3://your-bucket/model-output/

  Hyperparameters:
    model_name: unsloth/Llama-3.2-3B-Instruct
    lora_r: 64
    lora_alpha: 128
    epochs: 2
    batch_size: 4
    learning_rate: 2e-5
```

---

## Step 3: Verify Job Started

```bash
# Check status
aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query '[TrainingJobStatus, SecondaryStatus]' \
    --output text

# Expected: InProgress  Starting
# Then:     InProgress  Training
# Finally:  Completed   Completed
```

---

## What You Just Did (for the cert)

| Concept | What You Used | Cert Domain |
|---------|-------------|-------------|
| **Training Job** | `create-training-job` | Modeling |
| **Input Channels** | S3 data source with `S3Prefix` | Data Engineering |
| **Managed Spot** | `enable-managed-spot-training` with checkpointing | Cost Optimization |
| **DLC** | HuggingFace Deep Learning Container | Modeling |
| **Hyperparameters** | Passed as strings to the container | Modeling |
| **Instance Types** | `ml.g4dn.xlarge` (T4 GPU) | Infrastructure |
| **Stopping Condition** | `MaxRuntimeInSeconds` prevents runaway billing | Cost Optimization |

**Exam concepts:**
- Training data goes INTO S3 → SageMaker reads it via input channels
- Model artifacts go OUT to S3 → specified by `OutputDataConfig`
- Managed spot training saves 60-90% — SageMaker handles interruption + resume
- Hyperparameters are passed as string key-value pairs (not typed)
- The training script runs inside the container at `/opt/ml/code/`
- Training data is mounted at `/opt/ml/input/data/{channel_name}/`

---

## Next Steps

Go to: [03-monitor-download.md](03-monitor-download.md)
