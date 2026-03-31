# Playbook 03: Monitor & Download

> Watch your training job, stream logs, pull the model when it's done.
>
> **Time:** ~10 minutes (plus training time)
> **Prerequisites:** Running job from [02-submit-training-job.md](02-submit-training-job.md)

---

## Step 1: Monitor Job Status

```bash
JOB_NAME="lora-finetune-20260331"  # Your job name

# Quick status check
aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query '[TrainingJobStatus, SecondaryStatus, TrainingTimeInSeconds]' \
    --output text

# Poll until complete (check every 30 seconds)
while true; do
    STATUS=$(aws sagemaker describe-training-job \
        --training-job-name "$JOB_NAME" \
        --query 'TrainingJobStatus' --output text)
    echo "$(date +%H:%M:%S) Status: $STATUS"
    [ "$STATUS" = "Completed" ] || [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Stopped" ] && break
    sleep 30
done
```

---

## Step 2: Stream CloudWatch Logs

```bash
# Get the log stream name
LOG_GROUP="/aws/sagemaker/TrainingJobs"

# Stream logs in real-time
aws logs tail "$LOG_GROUP" \
    --log-stream-name-prefix "$JOB_NAME" \
    --follow

# Or get the last 50 lines
aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "${JOB_NAME}/algo-1-$(date +%s)" \
    --limit 50 \
    --query 'events[*].message' \
    --output text
```

### Console:
```
SageMaker → Training jobs → [your job] → View logs
  → Opens CloudWatch Logs
```

---

## Step 3: Check Job Metrics

```bash
# Training time, cost, and configuration
aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query '{
        Status: TrainingJobStatus,
        Duration: TrainingTimeInSeconds,
        BillableSeconds: BillableTimeInSeconds,
        Instance: ResourceConfig.InstanceType,
        SpotSavings: [EnableManagedSpotTraining, TrainingTimeInSeconds, BillableTimeInSeconds]
    }'
```

**Spot savings calculation:**
```
On-demand cost = TrainingTimeInSeconds × (hourly rate / 3600)
Spot cost      = BillableTimeInSeconds × (hourly rate / 3600)
Savings        = 1 - (BillableSeconds / TrainingTimeSeconds)
```

If `BillableTimeInSeconds` < `TrainingTimeInSeconds`, you saved money with spot.

---

## Step 4: Download Model Artifacts

```bash
BUCKET="ml-training-123456789012-us-east-1"

# Find the output path
OUTPUT_PATH=$(aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query 'ModelArtifacts.S3ModelArtifacts' --output text)
echo "Model artifacts: $OUTPUT_PATH"

# Download
mkdir -p ../model-registry/latest
aws s3 cp "$OUTPUT_PATH" ../model-registry/latest/model.tar.gz

# Extract
cd ../model-registry/latest
tar -xzf model.tar.gz
rm model.tar.gz

echo "Model downloaded to model-registry/latest/"
ls -la
```

---

## Step 5: What to Do Next

The downloaded artifacts contain the LoRA adapter weights. To use the model:

```bash
# Option A: Merge LoRA into base model locally, convert to GGUF, serve with Ollama
cd ../../local-pipeline
python3 tools/merge_model.py    # (when implemented)
python3 tools/convert_gguf.py   # (when implemented)
ollama create my-model -f Modelfile

# Option B: Deploy as SageMaker endpoint (see playbook 04)
# Good for API access, auto-scaling, production serving
```

---

## Handling Failures

### Job failed:

```bash
# Check failure reason
aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query 'FailureReason' --output text
```

Common failures:
| Error | Cause | Fix |
|-------|-------|-----|
| `ResourceLimitExceeded` | GPU quota not approved | Request quota increase in Service Quotas |
| `InternalServerError` | Spot instance interrupted, no checkpoint | Re-run with `--checkpoint-config` |
| `AlgorithmError` | Training script crashed | Check CloudWatch logs for Python traceback |
| `MaxRuntimeExceeded` | Training took longer than limit | Increase `MaxRuntimeInSeconds` |

### Spot interruption:

With managed spot training + checkpoints, SageMaker automatically resumes.
If it can't get a spot instance within `MaxWaitTimeInSeconds`, it fails.
Re-submit with on-demand as fallback:

```bash
# Same job without spot
aws sagemaker create-training-job \
    ... (same config, remove --enable-managed-spot-training)
```

---

## What You Just Did (for the cert)

| Concept | What You Learned | Cert Domain |
|---------|-----------------|-------------|
| **CloudWatch Logs** | Training job logs in `/aws/sagemaker/TrainingJobs` | Monitoring |
| **Model Artifacts** | Output saved to S3 as `model.tar.gz` | Modeling |
| **Spot Savings** | `BillableTimeInSeconds` < `TrainingTimeInSeconds` | Cost Optimization |
| **Failure Handling** | `FailureReason` field + CloudWatch troubleshooting | Operations |
| **S3 Output Path** | `ModelArtifacts.S3ModelArtifacts` contains the full path | Data Engineering |

---

## Next Steps

- Deploy as an endpoint → [04-deploy-endpoint.md](04-deploy-endpoint.md)
- Optimize costs → [05-cost-optimization.md](05-cost-optimization.md)
