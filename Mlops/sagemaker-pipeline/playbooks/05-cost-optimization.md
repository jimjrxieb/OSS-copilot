# Playbook 05: Cost Optimization

> SageMaker can get expensive fast. These patterns keep costs under control
> while you're learning and in production.
>
> **Time:** ~10 minutes to implement
> **Prerequisites:** Active SageMaker usage

---

## The Cost Traps

| Trap | What Happens | Cost |
|------|-------------|------|
| **Idle endpoint** | Left running after testing | $533/month (ml.g4dn.xlarge) |
| **On-demand training** | Didn't use spot instances | 2-3x more than spot |
| **Oversized instance** | Used ml.p3 when ml.g4dn works | 5x more per hour |
| **Large volumes** | 100GB EBS when 30GB is enough | $10/month per 100GB |
| **No auto-stop** | Notebook instances left running | $140/month (ml.t3.medium) |

---

## Training Cost Optimization

### 1. Always Use Spot Instances

```bash
# Spot saves 60-90% on training
aws sagemaker create-training-job \
    --enable-managed-spot-training \
    --stopping-condition MaxRuntimeInSeconds=3600,MaxWaitTimeInSeconds=7200 \
    --checkpoint-config S3Uri="s3://bucket/checkpoints/job-name/" \
    ...
```

| Instance | On-Demand | Spot | Savings |
|----------|-----------|------|---------|
| ml.g4dn.xlarge | $0.74/hr | ~$0.25/hr | 66% |
| ml.g5.xlarge | $1.41/hr | ~$0.50/hr | 65% |
| ml.p3.2xlarge | $3.83/hr | ~$1.20/hr | 69% |

### 2. Right-Size Your Instance

```
3B model (LoRA fine-tune):  ml.g4dn.xlarge (T4 16GB)  — $0.25/hr spot
8B model (LoRA fine-tune):  ml.g5.xlarge (A10G 24GB)   — $0.50/hr spot
8B model (full fine-tune):  ml.g5.2xlarge (A10G 24GB)   — $0.55/hr spot
70B model (LoRA):           ml.p4d.24xlarge (8x A100)    — expensive, use SageMaker Pipelines
```

### 3. Use Stopping Conditions

```bash
# Never let a job run forever
--stopping-condition MaxRuntimeInSeconds=3600   # Kill after 1 hour
```

---

## Endpoint Cost Optimization

### 1. Delete Endpoints When Not in Use

```bash
# Check for running endpoints
aws sagemaker list-endpoints --query 'Endpoints[*].[EndpointName,EndpointStatus]' --output table

# Delete any you're not actively using
aws sagemaker delete-endpoint --endpoint-name my-test-endpoint
```

### 2. Use Serverless Inference (pay per request)

For low-traffic endpoints (< 1 request/second):

```bash
aws sagemaker create-endpoint-config \
    --endpoint-config-name "serverless-config" \
    --production-variants '[{
        "VariantName": "primary",
        "ModelName": "my-model",
        "ServerlessConfig": {
            "MemorySizeInMB": 4096,
            "MaxConcurrency": 5
        }
    }]'
```

**Serverless pricing:** Pay only when invoked. No idle cost.
**Trade-off:** Cold start of 1-5 seconds on first request.

### 3. Use Async Inference (batch, cheaper)

For workloads that don't need real-time response:

```bash
aws sagemaker create-endpoint-config \
    --endpoint-config-name "async-config" \
    --async-inference-config '{
        "OutputConfig": {
            "S3OutputPath": "s3://bucket/inference-output/"
        }
    }' \
    --production-variants '[{
        "VariantName": "primary",
        "ModelName": "my-model",
        "InstanceType": "ml.g4dn.xlarge",
        "InitialInstanceCount": 0
    }]'
```

**InitialInstanceCount=0** — scales from zero. No idle cost.

---

## Notebook Cost Optimization

### Auto-Stop Lifecycle Configuration

```bash
# Create lifecycle config that stops idle notebooks after 1 hour
cat > /tmp/auto-stop.sh << 'SCRIPT'
#!/bin/bash
set -e
IDLE_TIME=3600  # 1 hour in seconds

# Install the auto-stop extension
pip install sagemaker-studio-analytics-extension

# Create the idle checker
cat > /home/ec2-user/SageMaker/auto-stop.py << 'EOF'
import subprocess, json, time, os
idle = int(os.environ.get("IDLE_TIME", 3600))
while True:
    result = subprocess.run(["jupyter", "notebook", "list", "--json"], capture_output=True, text=True)
    notebooks = [json.loads(l) for l in result.stdout.strip().split("\n") if l.strip()]
    if not notebooks:
        subprocess.run(["sudo", "shutdown", "-h", "now"])
    time.sleep(300)
EOF
nohup python3 /home/ec2-user/SageMaker/auto-stop.py &
SCRIPT

aws sagemaker create-notebook-instance-lifecycle-config \
    --notebook-instance-lifecycle-config-name "auto-stop-1hr" \
    --on-start Content=$(base64 /tmp/auto-stop.sh | tr -d '\n')
```

---

## Monthly Cost Checklist

Run this monthly to catch cost leaks:

```bash
echo "=== SageMaker Cost Check ==="

# Running endpoints (each costs $0.74+/hr)
echo "Endpoints:"
aws sagemaker list-endpoints --status-equals InService \
    --query 'Endpoints[*].[EndpointName,CreationTime]' --output table

# Running notebook instances (each costs $0.05+/hr)
echo "Notebooks:"
aws sagemaker list-notebook-instances --status-equals InService \
    --query 'NotebookInstances[*].[NotebookInstanceName,InstanceType]' --output table

# Recent training jobs (check spot savings)
echo "Recent training jobs:"
aws sagemaker list-training-jobs --max-results 5 \
    --query 'TrainingJobSummaries[*].[TrainingJobName,TrainingJobStatus]' --output table

# S3 storage
BUCKET="ml-training-$(aws sts get-caller-identity --query Account --output text)-us-east-1"
echo "S3 usage:"
aws s3 ls "s3://${BUCKET}" --summarize --recursive | tail -2
```

---

## What You Just Learned (for the cert)

| Concept | Cert Domain |
|---------|-------------|
| Managed spot training with checkpoints | Cost Optimization |
| Serverless inference (pay per request) | Deployment |
| Async inference (scale from zero) | Deployment |
| Auto-scaling with Application Auto Scaling | Infrastructure |
| Instance right-sizing (g4dn vs g5 vs p3) | Infrastructure |
| Lifecycle configurations for auto-stop | Operations |
| S3 storage management for model artifacts | Data Engineering |

**Exam tip:** The cost optimization question on the MLE cert almost always
involves spot training + right-sizing + auto-scaling. Know the trade-offs:
spot = cheaper but can be interrupted, serverless = no idle cost but cold start,
async = batch processing from zero instances.

---

## Quick Reference: Instance Costs

| Instance | GPU | VRAM | On-Demand/hr | Spot/hr | Best For |
|----------|-----|------|-------------|---------|----------|
| ml.g4dn.xlarge | T4 | 16GB | $0.74 | $0.25 | 3B LoRA, inference |
| ml.g5.xlarge | A10G | 24GB | $1.41 | $0.50 | 8B LoRA |
| ml.g5.2xlarge | A10G | 24GB | $1.52 | $0.55 | 8B with bigger batch |
| ml.p3.2xlarge | V100 | 16GB | $3.83 | $1.20 | Legacy, avoid |
| ml.p4d.24xlarge | 8xA100 | 320GB | $37.69 | $12.00 | 70B+ models only |

**Rule of thumb:** Start with `ml.g4dn.xlarge` spot. Only go bigger if training
fails with OOM (out of memory) errors.
