# 00 — Scan Your IaC

> Scan Terraform and CloudFormation for misconfigurations before deploying anything.

Checkov catches the same IaC issues that Prisma Cloud and Bridgecrew flag — because Checkov IS Bridgecrew's engine. Get your infrastructure code clean here so the enterprise tools have nothing to complain about in production.

---

## What You Need

- Terraform or CloudFormation templates in your project
- `checkov` installed (`pip install checkov`)
- Your paths set:
  ```bash
  export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

---

## Step 1: Scan with Checkov

### AWS (default)
```bash
checkov -d $TARGET_DIR/terraform/ --framework terraform --output json > $OUTPUT_DIR/checkov-terraform.json
checkov -d $TARGET_DIR/terraform/ --framework terraform
```

### Azure equivalent
```bash
checkov -d $TARGET_DIR/terraform/ --check "CKV_AZURE_*"
```

### GCP equivalent
```bash
checkov -d $TARGET_DIR/terraform/ --check "CKV_GCP_*"
```

---

## Step 2: Review Findings

Common AWS findings and their fixes:

| Check ID | Finding | Fix |
|----------|---------|-----|
| CKV_AWS_18 | S3 access logging disabled | See `iac-templates/terraform-hardening/s3-access-logging.tf` |
| CKV_AWS_19 | S3 encryption disabled | Add `server_side_encryption_configuration` block |
| CKV_AWS_145 | S3 KMS encryption | Use `aws:kms` instead of `AES256` |
| CKV_AWS_37 | CloudWatch log group not encrypted | See `iac-templates/terraform-hardening/cloudwatch-kms.tf` |
| CKV_AWS_104 | RDS not encrypted | See `iac-templates/terraform-hardening/rds-hardening.tf` |
| CKV_AWS_16 | RDS not encrypted at rest | Add `storage_encrypted = true` |
| CKV_AWS_118 | RDS enhanced monitoring | Add `monitoring_interval = 60` |
| CKV_AWS_338 | CloudWatch log retention | Set `retention_in_days = 365` |
| CKV2_AWS_5 | Security group allows 0.0.0.0/0 | Restrict to specific CIDRs |

---

## Step 3: Auto-Fix

```bash
bash tools/fix-terraform-findings.sh --target $TARGET_DIR/terraform/
```

The script applies safe fixes (encryption, logging, monitoring) and flags risky ones for review.

---

## Step 4: Rescan

```bash
checkov -d $TARGET_DIR/terraform/ --framework terraform
# Target: 0 CRITICAL, 0 HIGH
```

---

## Hardening Templates

Pre-built Terraform modules for common fixes are in `iac-templates/terraform-hardening/`:

| Template | What It Fixes |
|----------|--------------|
| `cloudwatch-kms.tf` | CloudWatch log group KMS encryption |
| `s3-access-logging.tf` | S3 access logging + encryption |
| `rds-hardening.tf` | RDS encryption, monitoring, deletion protection |
| `iam-scope-flowlogs.tf` | VPC Flow Logs IAM policy |
| `lambda-hardening.tf` | Lambda VPC, tracing, DLQ |
| `vpc-default-sg.tf` | Lock down default security group |

Copy what you need into your Terraform modules.

---

## Next Step

Go to [01-vpc-network-security.md](01-vpc-network-security.md) to harden VPC and networking.
