# Playbook 04: Deploy Endpoint

> Serve your trained model via a SageMaker real-time endpoint.
> API access, auto-scaling, pay per inference.
>
> **Time:** ~15 minutes
> **Prerequisites:** Trained model artifacts in S3 from [03-monitor-download.md](03-monitor-download.md)

---

## When to Use an Endpoint vs. Ollama

| Scenario | Ollama (Local) | SageMaker Endpoint |
|----------|---------------|-------------------|
| Development / testing | Yes | Overkill |
| Single user | Yes | Overkill |
| API access for apps | Port-forward | Yes — HTTPS + auth |
| Auto-scaling | No | Yes — scales to demand |
| Multiple users | Limited | Yes |
| Production SLA | No uptime guarantee | Yes — multi-AZ |
| Cost when idle | Free (local) | $0.74/hr minimum |

---

## Step 1: Create a SageMaker Model

```bash
ROLE_ARN=$(aws iam get-role --role-name SageMakerTrainingRole --query 'Role.Arn' --output text)
REGION="us-east-1"
MODEL_NAME="my-model-$(date +%Y%m%d)"

# Get the model artifacts location from the training job
JOB_NAME="lora-finetune-20260331"
MODEL_DATA=$(aws sagemaker describe-training-job \
    --training-job-name "$JOB_NAME" \
    --query 'ModelArtifacts.S3ModelArtifacts' --output text)

# Get the training image (same one used for training)
IMAGE="763104351884.dkr.ecr.${REGION}.amazonaws.com/huggingface-pytorch-inference:2.3.0-transformers4.43.4-gpu-py311-cu121-ubuntu22.04"

# Create the model
aws sagemaker create-model \
    --model-name "$MODEL_NAME" \
    --primary-container \
        Image="$IMAGE",ModelDataUrl="$MODEL_DATA" \
    --execution-role-arn "$ROLE_ARN"

echo "Model created: $MODEL_NAME"
```

### Console:
```
SageMaker → Inference → Models → Create model
  Name: my-model-20260331
  Container: HuggingFace inference container
  Model data: s3://your-bucket/model-output/{job-name}/output/model.tar.gz
  IAM role: SageMakerTrainingRole
```

---

## Step 2: Create Endpoint Configuration

```bash
ENDPOINT_CONFIG="${MODEL_NAME}-config"

aws sagemaker create-endpoint-config \
    --endpoint-config-name "$ENDPOINT_CONFIG" \
    --production-variants '[{
        "VariantName": "primary",
        "ModelName": "'"$MODEL_NAME"'",
        "InstanceType": "ml.g4dn.xlarge",
        "InitialInstanceCount": 1,
        "InitialVariantWeight": 1.0
    }]'

echo "Endpoint config: $ENDPOINT_CONFIG"
```

---

## Step 3: Create the Endpoint

```bash
ENDPOINT_NAME="${MODEL_NAME}-endpoint"

aws sagemaker create-endpoint \
    --endpoint-name "$ENDPOINT_NAME" \
    --endpoint-config-name "$ENDPOINT_CONFIG"

echo "Endpoint creating: $ENDPOINT_NAME (takes 5-10 minutes)"

# Wait for it to be InService
aws sagemaker wait endpoint-in-service --endpoint-name "$ENDPOINT_NAME"
echo "Endpoint ready: $ENDPOINT_NAME"
```

### Console:
```
SageMaker → Inference → Endpoints → Create endpoint
  Name: my-model-20260331-endpoint
  Endpoint configuration: my-model-20260331-config
  → Click Create endpoint
  → Wait 5-10 minutes for InService
```

---

## Step 4: Test the Endpoint

```bash
# Invoke the endpoint
aws sagemaker-runtime invoke-endpoint \
    --endpoint-name "$ENDPOINT_NAME" \
    --content-type "application/json" \
    --body '{"inputs": "How do I fix a privileged container in Kubernetes?"}' \
    /tmp/response.json

cat /tmp/response.json | python3 -m json.tool
```

### From Python:

```python
import boto3
import json

runtime = boto3.client("sagemaker-runtime")

response = runtime.invoke_endpoint(
    EndpointName="my-model-20260331-endpoint",
    ContentType="application/json",
    Body=json.dumps({"inputs": "How do I fix a privileged container?"}),
)

result = json.loads(response["Body"].read())
print(result)
```

---

## Step 5: Add Auto-Scaling (Production)

```bash
# Register the endpoint as a scalable target
aws application-autoscaling register-scalable-target \
    --service-namespace sagemaker \
    --resource-id "endpoint/${ENDPOINT_NAME}/variant/primary" \
    --scalable-dimension "sagemaker:variant:DesiredInstanceCount" \
    --min-capacity 1 \
    --max-capacity 3

# Scale based on invocations per instance
aws application-autoscaling put-scaling-policy \
    --policy-name "${ENDPOINT_NAME}-scaling" \
    --service-namespace sagemaker \
    --resource-id "endpoint/${ENDPOINT_NAME}/variant/primary" \
    --scalable-dimension "sagemaker:variant:DesiredInstanceCount" \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration '{
        "TargetValue": 50,
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "SageMakerVariantInvocationsPerInstance"
        },
        "ScaleInCooldown": 300,
        "ScaleOutCooldown": 60
    }'
```

---

## Step 6: Delete When Done (IMPORTANT — stops billing)

```bash
# Delete endpoint (stops per-hour billing immediately)
aws sagemaker delete-endpoint --endpoint-name "$ENDPOINT_NAME"

# Delete endpoint config
aws sagemaker delete-endpoint-config --endpoint-config-name "$ENDPOINT_CONFIG"

# Delete model (just metadata — doesn't delete S3 artifacts)
aws sagemaker delete-model --model-name "$MODEL_NAME"

echo "Cleanup complete. No more charges."
```

**Do not forget this step.** A `ml.g4dn.xlarge` endpoint costs $0.74/hour =
$17.76/day = $533/month if left running.

---

## What You Just Did (for the cert)

| Concept | What You Learned | Cert Domain |
|---------|-----------------|-------------|
| **Model** | Pointer to S3 artifacts + container image | Modeling |
| **Endpoint Config** | Instance type, count, variant weight | Infrastructure |
| **Endpoint** | Live inference service with HTTPS | Deployment |
| **Auto-Scaling** | Target tracking on invocations per instance | Cost Optimization |
| **Invoke** | `sagemaker-runtime invoke-endpoint` | Modeling |
| **Cleanup** | Delete endpoint → config → model (order matters) | Operations |

**Exam concepts:**
- SageMaker has 3 objects: Model → EndpointConfig → Endpoint
- Model = container image + S3 model data
- EndpointConfig = instance type + count + variant weights
- Endpoint = the live service (takes 5-10 min to create)
- Auto-scaling via Application Auto Scaling (not SageMaker native)
- Multi-variant endpoints support A/B testing (different weights)

---

## Next Steps

- Optimize costs → [05-cost-optimization.md](05-cost-optimization.md)
