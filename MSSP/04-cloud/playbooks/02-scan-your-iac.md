# Playbook 02: Scan Your IaC

> Catch cloud misconfigurations before you deploy them.
> Checkov and tfsec scan your Terraform the same way Prisma Cloud does.
>
> **Time:** ~10 minutes
> **Prerequisites:** Terraform files in a directory

---

## Why IaC Scanning Matters

Scanning a live AWS account finds problems after they exist.
Scanning IaC finds them before `terraform apply` — when fixing is
a one-line change instead of a production incident.

Checkov is built by Bridgecrew, which was acquired by Palo Alto Networks
and became Prisma Cloud's Code Security engine. **You're running the same
scanner that Prisma Cloud runs — for free.**

---

## Step 1: Install the Scanners

```bash
# Checkov (multi-framework — Terraform, CloudFormation, K8s, Dockerfile)
pip install checkov

# tfsec (Terraform-specific, different rule set)
brew install tfsec

# Both is better — they catch different things
```

---

## Step 2: Scan Your Terraform

```bash
cd /path/to/your/terraform

# Checkov — comprehensive
checkov --directory . --framework terraform
# Shows: PASS/FAIL per check with CKV_AWS_* IDs

# tfsec — Terraform-focused
tfsec .
# Shows: findings with severity and remediation advice

# Both, JSON output for processing
checkov --directory . --framework terraform --output json --quiet > checkov-results.json
tfsec . --format json > tfsec-results.json
```

### Using the OSS-Copilot script:

```bash
# From the MSSP/04-cloud directory
./scan-iac.sh /path/to/your/terraform --output /path/to/output
```

---

## Step 3: Understand the Results

### Checkov findings — what the IDs mean:

| Check ID | What It Checks | Severity | Fix |
|----------|---------------|----------|-----|
| **CKV_AWS_145** | S3 bucket encrypted with KMS | High | Add `server_side_encryption_configuration` block |
| **CKV_AWS_18** | S3 bucket has access logging | Medium | Add `logging` block pointing to log bucket |
| **CKV_AWS_19** | S3 bucket has versioning | Medium | Add `versioning { enabled = true }` |
| **CKV_AWS_21** | S3 bucket has public access block | High | Add `aws_s3_bucket_public_access_block` resource |
| **CKV_AWS_46** | IAM policy doesn't use wildcards | High | Replace `"Resource": "*"` with specific ARNs |
| **CKV_AWS_24** | CloudWatch log group encrypted | Medium | Add `kms_key_id` to log group |
| **CKV_AWS_126** | EKS control plane logging | High | Enable all 5 log types |
| **CKV_AWS_58** | EKS secrets encryption | High | Add `encryption_config` block |
| **CKV_AWS_23** | Security group has description | Low | Add `description` field |
| **CKV2_AWS_5** | Security group allows 0.0.0.0/0 | High | Scope to specific CIDRs |

### tfsec findings — common patterns:

| Rule | What It Checks | Fix |
|------|---------------|-----|
| `aws-s3-enable-bucket-encryption` | Bucket missing encryption | Add SSE configuration |
| `aws-iam-no-policy-wildcards` | IAM policy with `*` resource | Scope to specific resources |
| `aws-vpc-no-public-ingress-sgr` | Security group 0.0.0.0/0 | Restrict to known CIDRs |
| `aws-rds-encrypt-instance-storage` | RDS without encryption | Set `storage_encrypted = true` |
| `aws-ec2-enforce-http-token-imds` | IMDSv1 enabled | Set `http_tokens = "required"` |

---

## Step 4: Fix the Common Findings

### S3 bucket hardening (covers 4-5 Checkov findings at once):

```hcl
resource "aws_s3_bucket" "example" {
  bucket = "my-secure-bucket"
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.example.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket                  = aws_s3_bucket.example.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "example" {
  bucket        = aws_s3_bucket.example.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "s3-access-logs/"
}
```

### Security group — no 0.0.0.0/0:

```hcl
# BAD: open to the world
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # Checkov flags this
}

# GOOD: scoped to known sources (ALB security group)
ingress {
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  security_groups = [aws_security_group.alb.id]  # Only from ALB
}
```

---

## Step 5: Add to CI

```yaml
# .github/workflows/iac-security.yml
name: IaC Security

on:
  pull_request:
    paths: ['**/*.tf', '**/*.tfvars']

jobs:
  checkov:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bridgecrewio/checkov-action@v12
        with:
          directory: .
          framework: terraform
          soft_fail: false  # Blocks PR on findings
```

---

## Step 6: Rescan After Fixes

```bash
# Before
checkov --directory . --framework terraform --quiet 2>/dev/null | tail -5
# Passed checks: 42  Failed checks: 12

# After fixing
checkov --directory . --framework terraform --quiet 2>/dev/null | tail -5
# Passed checks: 54  Failed checks: 0
```

---

## Next Steps

- Harden IAM → [03-harden-iam.md](03-harden-iam.md)
- Enable threat detection → [04-enable-detection.md](04-enable-detection.md)
