# 06 — ECR & CI/CD Pipeline

> Set up a secure image pipeline: build, scan, push to ECR, no static credentials.

GitHub Actions builds the image. Trivy scans it. OIDC federation authenticates to AWS — no access keys stored in GitHub secrets.

---

## Step 1: Create ECR Repositories

### AWS
```bash
for repo in api worker ui; do
  aws ecr create-repository --repository-name $repo \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability IMMUTABLE \
    --encryption-configuration encryptionType=KMS,kmsKey=alias/ecr-key
done
```

### Azure equivalent
```bash
az acr create --name myacr --resource-group $RG --sku Standard --admin-enabled false
```

### GCP equivalent
```bash
gcloud artifacts repositories create app-images --repository-format=docker --location=us-central1
```

---

## Step 2: Set Up OIDC Federation (No Static Keys)

### AWS
```bash
# Create OIDC provider for GitHub Actions
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create role with OIDC trust (scoped to your repo)
aws iam create-role --role-name github-actions-ecr \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
        "StringLike": {"token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"}
      }
    }]
  }'

# Attach minimal ECR push permissions
aws iam put-role-policy --role-name github-actions-ecr --policy-name ecr-push \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["ecr:GetDownloadUrlForLayer","ecr:BatchGetImage","ecr:BatchCheckLayerAvailability",
        "ecr:PutImage","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload",
        "ecr:GetAuthorizationToken","ecr:DescribeImageScanFindings"],
      "Resource": "*"
    }]
  }'
```

---

## Step 3: GitHub Actions Workflow

```yaml
# .github/workflows/build-push.yml
name: Build and Push
on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC — no static keys)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/github-actions-ecr
          aws-region: us-east-1

      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build image
        run: docker build -t $ECR_REGISTRY/api:${{ github.sha }} .

      - name: Scan with Trivy
        run: trivy image --severity HIGH,CRITICAL --exit-code 1 $ECR_REGISTRY/api:${{ github.sha }}

      - name: Push (only if scan passes)
        run: docker push $ECR_REGISTRY/api:${{ github.sha }}
```

Add `AWS_ROLE_ARN`, `AWS_REGION`, and `ECR_REGISTRY` as GitHub repository variables (not secrets — OIDC handles auth).

---

## Step 4: Verify

```bash
# ECR repos exist with scanning enabled?
aws ecr describe-repositories --query 'repositories[*].[repositoryName,imageScanningConfiguration.scanOnPush,imageTagMutability]' --output table

# OIDC provider exists?
aws iam list-open-id-connect-providers

# Role has correct trust policy?
aws iam get-role --role-name github-actions-ecr --query 'Role.AssumeRolePolicyDocument'
```

---

## Next Step

Go to [07-security-validation.md](07-security-validation.md) to run the full security audit.
