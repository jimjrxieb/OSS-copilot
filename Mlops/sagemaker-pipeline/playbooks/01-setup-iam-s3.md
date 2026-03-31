# Playbook 01: Setup IAM & S3

> Create the IAM role and S3 bucket SageMaker needs before you can train.
> This is the foundation — do it once, use it for every training job.
>
> **Time:** ~15 minutes
> **Prerequisites:** AWS CLI configured (`aws sts get-caller-identity` works)

---

## What SageMaker Needs

SageMaker training jobs run inside AWS-managed containers. Those containers
need permissions to:
1. Read training data from S3
2. Write model artifacts to S3
3. Write logs to CloudWatch
4. Pull container images from ECR

This means you need an **IAM execution role** that SageMaker assumes when
running your job.

---

## Step 1: Create the S3 Bucket

### AWS CLI:

```bash
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="ml-training-${ACCOUNT_ID}-${REGION}"

# Create bucket
aws s3 mb "s3://${BUCKET}" --region "$REGION"

# Block public access (always)
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable versioning (recover from accidental overwrites)
aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

echo "Bucket: s3://${BUCKET}"
```

### Console:
```
S3 → Create bucket
  Name: ml-training-{account-id}-{region}
  Region: us-east-1
  Block all public access: ON
  Versioning: Enabled
  Encryption: SSE-S3 (default)
```

---

## Step 2: Create the IAM Execution Role

SageMaker needs a role it can assume. The trust policy says "SageMaker
service is allowed to use this role."

### AWS CLI:

```bash
# Create trust policy
cat > /tmp/sagemaker-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "sagemaker.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create the role
aws iam create-role \
    --role-name SageMakerTrainingRole \
    --assume-role-policy-document file:///tmp/sagemaker-trust-policy.json \
    --description "Execution role for SageMaker training jobs"

# Attach managed policies
# SageMaker full access (training, endpoints, logs)
aws iam attach-role-policy \
    --role-name SageMakerTrainingRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess

# S3 access for training data and model artifacts
aws iam attach-role-policy \
    --role-name SageMakerTrainingRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Get the role ARN (you'll need this for training jobs)
ROLE_ARN=$(aws iam get-role --role-name SageMakerTrainingRole --query 'Role.Arn' --output text)
echo "Role ARN: $ROLE_ARN"
```

### Console:
```
IAM → Roles → Create role
  Trusted entity: AWS service → SageMaker
  Use case: SageMaker - Execution
  Policies:
    - AmazonSageMakerFullAccess
    - AmazonS3FullAccess
  Name: SageMakerTrainingRole
```

### Scoped-Down S3 Policy (production — instead of S3FullAccess):

```bash
cat > /tmp/s3-training-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}",
                "arn:aws:s3:::${BUCKET}/*"
            ]
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name SageMakerTrainingRole \
    --policy-name S3TrainingAccess \
    --policy-document file:///tmp/s3-training-policy.json
```

---

## Step 3: Verify Everything Works

```bash
# Verify role exists
aws iam get-role --role-name SageMakerTrainingRole --query 'Role.Arn'

# Verify bucket exists
aws s3 ls "s3://${BUCKET}/"

# Verify you can upload to the bucket
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt "s3://${BUCKET}/test.txt"
aws s3 rm "s3://${BUCKET}/test.txt"

echo "Setup complete. Update values.yaml with:"
echo "  aws.account_id: ${ACCOUNT_ID}"
echo "  s3.bucket: ${BUCKET}"
echo "  iam.role_name: SageMakerTrainingRole"
```

---

## Step 4: Update values.yaml

```yaml
aws:
  region: "us-east-1"
  account_id: "123456789012"     # Your account ID

s3:
  bucket: "ml-training-123456789012-us-east-1"

iam:
  role_name: "SageMakerTrainingRole"
```

---

## What You Just Built (for the cert)

| AWS Service | What You Used It For | Cert Domain |
|-------------|---------------------|-------------|
| **IAM** | Execution role with trust policy | Security & Governance |
| **S3** | Training data + model artifact storage | Data Engineering |
| **IAM Policy** | Scoped S3 access (least privilege) | Security & Governance |

**Exam concept:** SageMaker training jobs assume an IAM execution role.
The role must have: S3 read (data), S3 write (artifacts), CloudWatch write (logs),
and ECR pull (container images). `AmazonSageMakerFullAccess` covers all of these
but is overprivileged for production — scope down with inline policies.

---

## Next Steps

Go to: [02-submit-training-job.md](02-submit-training-job.md)
