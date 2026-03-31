# Playbook 00: Know Your AWS

> Before you scan, understand what you're working with.
> Which accounts, which regions, which services.
>
> **Time:** 5 minutes
> **Prerequisites:** AWS CLI configured (`aws sts get-caller-identity` works)

---

## Why This Matters

Prowler scans 300+ checks across every AWS service. If you scan without
knowing what's in use, you'll get hundreds of findings for services you
don't even use. A senior engineer inventories first.

---

## Step 1: Who Am I?

```bash
# What account am I in?
aws sts get-caller-identity

# What regions am I using?
# (Check for resources in common regions)
for region in us-east-1 us-west-2 eu-west-1 ap-southeast-1; do
    COUNT=$(aws ec2 describe-instances --region "$region" --query 'Reservations[].Instances[] | length(@)' --output text 2>/dev/null)
    [ "$COUNT" -gt 0 ] && echo "  $region: $COUNT EC2 instances"
done
```

---

## Step 2: What Services Are in Use?

```bash
# S3 buckets
echo "S3 buckets: $(aws s3 ls 2>/dev/null | wc -l)"

# EKS clusters
echo "EKS clusters: $(aws eks list-clusters --query 'clusters | length(@)' --output text 2>/dev/null)"

# RDS databases
echo "RDS instances: $(aws rds describe-db-instances --query 'DBInstances | length(@)' --output text 2>/dev/null)"

# Lambda functions
echo "Lambda functions: $(aws lambda list-functions --query 'Functions | length(@)' --output text 2>/dev/null)"

# IAM users
echo "IAM users: $(aws iam list-users --query 'Users | length(@)' --output text 2>/dev/null)"
```

---

## Step 3: What's Already Enabled?

```bash
# CloudTrail — is it logging?
aws cloudtrail describe-trails --query 'trailList[*].[Name,IsMultiRegionTrail,IsLogging]' --output table 2>/dev/null

# GuardDuty — is it detecting?
aws guardduty list-detectors --query 'DetectorIds' --output text 2>/dev/null

# Security Hub — is it aggregating?
aws securityhub describe-hub 2>/dev/null && echo "Security Hub: ENABLED" || echo "Security Hub: NOT ENABLED"

# VPC Flow Logs
aws ec2 describe-flow-logs --query 'FlowLogs[*].[FlowLogId,ResourceId,FlowLogStatus]' --output table 2>/dev/null
```

---

## Step 4: Build Your AWS Profile

```
AWS Profile
───────────
Account ID:            ___
Primary region:        ___
Regions with resources: ___

Services in use:
  EC2:       ___ instances
  S3:        ___ buckets
  EKS:       ___ clusters
  RDS:       ___ databases
  Lambda:    ___ functions
  IAM users: ___

Already enabled:
  CloudTrail:    Yes / No
  GuardDuty:     Yes / No
  Security Hub:  Yes / No
  VPC Flow Logs: Yes / No
```

If CloudTrail, GuardDuty, and Security Hub all say "No" — that's your
first priority. Playbook 04 covers enabling them.

---

## Next Steps

Go to: [01-scan-your-account.md](01-scan-your-account.md)
