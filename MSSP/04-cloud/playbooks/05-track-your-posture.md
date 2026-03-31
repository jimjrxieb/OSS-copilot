# Playbook 05: Track Your Posture

> Rescan after fixes, measure improvement, set up continuous monitoring.
>
> **Time:** ~10 minutes
> **Prerequisites:** You've run playbooks 01-04

---

## Step 1: Rescan with Prowler

```bash
# Same command as Playbook 01, with a post-fix label
prowler aws --severity critical high --output-formats json-ocsf html

# Save results
POSTFIX_DIR=".oss-copilot/cloud-postfix-$(date +%Y%m%d)"
mkdir -p "$POSTFIX_DIR"
cp output/prowler-output-*.json "$POSTFIX_DIR/"
cp output/prowler-output-*.html "$POSTFIX_DIR/"
```

---

## Step 2: Compare Before and After

```bash
BASELINE=".oss-copilot/cloud-baseline-YYYYMMDD"
POSTFIX=".oss-copilot/cloud-postfix-$(date +%Y%m%d)"

# Quick comparison (if using CSV output)
echo "=== Before ==="
grep -c "FAIL" "$BASELINE"/*.csv 2>/dev/null || echo "Use HTML reports"

echo "=== After ==="
grep -c "FAIL" "$POSTFIX"/*.csv 2>/dev/null || echo "Use HTML reports"
```

### Check Security Hub score improvement:

```bash
# Current compliance score
aws securityhub get-findings \
    --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}' \
    --query 'Findings | length(@)' --output text

aws securityhub get-findings \
    --filters '{"ComplianceStatus":[{"Value":"PASSED","Comparison":"EQUALS"}]}' \
    --query 'Findings | length(@)' --output text
```

---

## Step 3: What "Done" Looks Like

| Control | Target |
|---------|--------|
| Root MFA | Enabled, no access keys |
| User MFA | 100% of console users |
| Stale keys (>90 days) | 0 |
| Wildcard IAM policies | 0 custom policies |
| CloudTrail | Multi-region, log validation on |
| GuardDuty | Enabled, findings reviewed |
| Security Hub | Enabled, CIS + Best Practices standards |
| VPC Flow Logs | Enabled on all VPCs |
| S3 public buckets | 0 (account-level block) |
| Unencrypted storage | 0 (EBS, RDS, S3 all encrypted) |

You won't hit every target on day one. The priority is:
1. Root MFA + CloudTrail (visibility)
2. GuardDuty (threat detection)
3. IAM cleanup (reduce blast radius)
4. Encryption + S3 hardening (data protection)

---

## Step 4: Continuous Monitoring

### Weekly Prowler scan:

```bash
# Cron: weekly Prowler scan, push to Security Hub
0 3 * * 1 prowler aws \
    --severity critical high \
    --output-formats json-asff \
    --security-hub \
    --region us-east-1 \
    2>&1 >> /var/log/prowler-weekly.log
```

### Daily GuardDuty check:

```bash
# Check for new high-severity findings
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty list-findings --detector-id "$DETECTOR_ID" \
    --finding-criteria '{"Criterion":{"severity":{"Gte":7},"updatedAt":{"GreaterThanOrEqual":'"$(($(date +%s) - 86400))"'000}}}' \
    --query 'FindingIds'
```

### Monthly trend tracking:

```
Cloud Security Trend
────────────────────
Date          Prowler FAIL   GuardDuty HIGH   Security Hub Score
────────      ────────────   ──────────────   ─────────────────
Mar 15        87             3                 42%
Mar 22        34             1                 68%
Mar 29        12             0                 85%
Apr 5          4             0                 92%
```

---

## Step 5: Share Results

### For your team:

> "We went from 87 Prowler failures to 4 in three weeks. Root has MFA,
> all access keys rotated, CloudTrail + GuardDuty + Security Hub all
> enabled. Security Hub CIS compliance went from 42% to 92%.
> Zero additional license cost — all AWS native + Prowler."

### For auditors:

The Security Hub dashboard is your compliance evidence. Export it:

```bash
# Export all findings as JSON
aws securityhub get-findings --output json > security-hub-export.json

# Export compliance summary
aws securityhub describe-standards-controls \
    --standards-subscription-arn "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/2.0.0" \
    --output json > cis-compliance-report.json
```

---

## When to Scan Other Layers

| Your Environment Has... | Next Step |
|------------------------|-----------|
| Application code | [01-code/](../../01-code/) — SAST, secrets, dependencies |
| Kubernetes cluster | [02-cluster/](../../02-cluster/) — CIS benchmarks, admission control |
| Container images | [03-container/](../../03-container/) — image CVEs, Dockerfile hardening |
| Compliance requirements | [05-compliance/](../../05-compliance/) — NIST mapping, evidence packaging |
