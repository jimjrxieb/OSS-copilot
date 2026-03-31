#!/usr/bin/env bash
set -euo pipefail

# setup-sagemaker.sh — Create IAM role + S3 bucket for SageMaker
# Usage: ./setup-sagemaker.sh [--dry-run]
#
# Creates:
#   - S3 bucket: ml-training-{account_id}-{region}
#   - IAM role: SageMakerTrainingRole
#   - Scoped S3 access policy

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_load-config.sh" 2>/dev/null || true

REGION="${SM_REGION:-us-east-1}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "=== SageMaker Setup ==="

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="ml-training-${ACCOUNT_ID}-${REGION}"
ROLE_NAME="SageMakerTrainingRole"

echo "  Account:  $ACCOUNT_ID"
echo "  Region:   $REGION"
echo "  Bucket:   $BUCKET"
echo "  Role:     $ROLE_NAME"

if $DRY_RUN; then
    echo "[DRY RUN] Would create bucket and role. Exiting."
    exit 0
fi

# --- S3 Bucket ---
echo ""
echo "[*] Creating S3 bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "    Bucket already exists."
else
    aws s3 mb "s3://${BUCKET}" --region "$REGION"
    aws s3api put-public-access-block \
        --bucket "$BUCKET" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET" \
        --versioning-configuration Status=Enabled
    echo "    Created with public access blocked + versioning."
fi

# --- IAM Role ---
echo ""
echo "[*] Creating IAM role: $ROLE_NAME"
if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo "    Role already exists."
else
    cat > /tmp/sm-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "sagemaker.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/sm-trust-policy.json \
        --description "Execution role for SageMaker training jobs"

    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess

    # Scoped S3 policy (not S3FullAccess)
    cat > /tmp/sm-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"],
        "Resource": ["arn:aws:s3:::${BUCKET}", "arn:aws:s3:::${BUCKET}/*"]
    }]
}
EOF
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name S3TrainingAccess \
        --policy-document file:///tmp/sm-s3-policy.json

    echo "    Created with SageMaker + scoped S3 access."
fi

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Update values.yaml:"
echo "  aws:"
echo "    account_id: \"$ACCOUNT_ID\""
echo "    region: \"$REGION\""
echo "  s3:"
echo "    bucket: \"$BUCKET\""
echo "  iam:"
echo "    role_name: \"$ROLE_NAME\""
echo ""
echo "Role ARN: $ROLE_ARN"
