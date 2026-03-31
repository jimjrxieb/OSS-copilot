# Playbook 01: Scan Your AWS Account

> Run Prowler against your live AWS account. Find every misconfiguration
> the enterprise tools would find — using the same CIS benchmarks.
>
> **Time:** ~15 minutes (Prowler runs 10-30 min depending on account size)
> **Prerequisites:** AWS credentials with SecurityAudit policy attached

---

## Step 1: Install Prowler

```bash
pip install prowler
```

Prowler needs read-only access to your AWS account. The `SecurityAudit`
managed policy covers most checks. For full coverage:

```bash
# Attach these to your IAM user/role:
# - arn:aws:iam::aws:policy/SecurityAudit
# - arn:aws:iam::aws:policy/job-function/ViewOnlyAccess
```

---

## Step 2: Run the Scan

```bash
# Full scan — all 300+ checks (takes 10-30 minutes)
prowler aws --output-formats json-ocsf html

# Faster — critical and high severity only
prowler aws --severity critical high --output-formats json-ocsf html

# Specific CIS benchmark
prowler aws --compliance cis_2.0_aws --output-formats json-ocsf html

# With a named profile
prowler aws --profile production --severity critical high
```

Prowler writes output to `./output/` by default.

---

## Step 3: Read the Results

### HTML report (easiest to read):

```bash
# Open the HTML report
open output/prowler-output-*.html    # macOS
xdg-open output/prowler-output-*.html  # Linux
```

The HTML report shows:
- Overall compliance score
- Findings grouped by service (IAM, S3, EC2, VPC, etc.)
- Severity breakdown (CRITICAL, HIGH, MEDIUM, LOW)
- CIS benchmark mapping for each finding

### Quick summary from CLI:

```bash
# Count findings by severity
prowler aws --severity critical high --output-formats csv 2>/dev/null
cat output/*.csv | awk -F',' '{print $6}' | sort | uniq -c | sort -rn
```

---

## Step 4: Understand What Prowler Checks

Prowler maps to CIS AWS Foundations Benchmark. Here are the checks that matter most:

| Category | What It Checks | Common Findings |
|----------|---------------|-----------------|
| **IAM** | Root MFA, stale keys, wildcard policies | Root without MFA, 180-day-old access keys |
| **S3** | Public access, encryption, logging | Public buckets, missing encryption |
| **VPC** | Flow logs, security groups, NACLs | No flow logs, 0.0.0.0/0 ingress rules |
| **CloudTrail** | Multi-region, log validation | Trail disabled or single-region |
| **RDS** | Encryption, public access, backups | Unencrypted databases, public endpoints |
| **EC2** | IMDSv2, EBS encryption, key age | IMDSv1 (SSRF vulnerable), unencrypted volumes |
| **GuardDuty** | Enabled, findings reviewed | Not enabled (most common) |
| **KMS** | Key rotation, key policies | Rotation disabled |

---

## Step 5: The Priority Order

```
1. ROOT ACCOUNT           ← MFA not enabled? Fix TODAY.
2. PUBLIC S3 BUCKETS      ← Data exposure. Fix TODAY.
3. CLOUDTRAIL DISABLED    ← No audit trail. Fix this week.
4. GUARDDUTY DISABLED     ← No threat detection. Fix this week.
5. STALE IAM KEYS         ← >90 days old = rotate or deactivate.
6. WILDCARD IAM POLICIES  ← "Action": "*" = overprivileged. Fix this sprint.
7. UNENCRYPTED STORAGE    ← EBS, RDS, S3 without KMS. Fix this sprint.
8. VPC FLOW LOGS          ← No network visibility. Enable this sprint.
9. OPEN SECURITY GROUPS   ← 0.0.0.0/0 on non-ALB ports. Review.
10. IMDSV1                ← SSRF attack vector. Enable IMDSv2.
```

---

## Step 6: Save Your Baseline

```bash
BASELINE_DIR=".oss-copilot/cloud-baseline-$(date +%Y%m%d)"
mkdir -p "$BASELINE_DIR"
cp output/prowler-output-*.json "$BASELINE_DIR/"
cp output/prowler-output-*.html "$BASELINE_DIR/"
echo "Baseline saved to $BASELINE_DIR"
```

---

## Step 7: Push to Security Hub (Optional)

If you use AWS Security Hub, Prowler can push findings directly:

```bash
prowler aws \
    --output-formats json-asff \
    --security-hub \
    --region us-east-1
```

Findings appear in Security Hub alongside GuardDuty, Inspector, and Config.
See [docs/integrations/security-hub.md](../../../docs/integrations/security-hub.md) for details.

---

## Next Steps

- Scan your Terraform before deploying → [02-scan-your-iac.md](02-scan-your-iac.md)
- Harden IAM → [03-harden-iam.md](03-harden-iam.md)
