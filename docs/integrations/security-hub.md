# AWS Security Hub Integration

> Prowler pushes findings directly to Security Hub. One flag. No extra code.
> This is the cleanest integration story in the repo.

---

## What Security Hub Expects

AWS Security Hub accepts findings in **ASFF** (Amazon Security Finding Format).
Prowler outputs ASFF natively — it was built for this.

Security Hub aggregates findings from GuardDuty, Inspector, Macie, and
third-party tools into a single dashboard. Your Prowler findings show up
alongside AWS-native findings. One pane of glass.

---

## How to Format Your Findings

Prowler handles formatting automatically. No transformation needed.

```bash
# Prowler outputs ASFF natively
prowler aws --output-formats json-asff
```

Other tools need conversion:

| Tool | ASFF Support | How |
|------|-------------|-----|
| **Prowler** | Native | `--output-formats json-asff` |
| **Trivy** | Native | `trivy image --format asff` |
| **Checkov** | Via SARIF → manual import | Not native, use Prisma instead |
| **Semgrep** | Via SARIF → manual import | `--sarif` output, import manually |

---

## The Command

### Prowler → Security Hub (automatic)

```bash
# Scan AWS account and push findings directly to Security Hub
prowler aws \
    --output-formats json-asff \
    --security-hub \
    --region us-east-1

# With a specific profile
prowler aws \
    --output-formats json-asff \
    --security-hub \
    --region us-east-1 \
    --profile production
```

**What happens:**
1. Prowler scans your AWS account (300+ checks)
2. Findings are formatted as ASFF
3. `--security-hub` flag sends them directly via `BatchImportFindings` API
4. Findings appear in Security Hub within minutes

### Prerequisites

```bash
# Security Hub must be enabled in the region
aws securityhub enable-security-hub --region us-east-1

# IAM permissions needed (add to Prowler's role)
# - securityhub:BatchImportFindings
# - securityhub:GetFindings
```

### Trivy → Security Hub (manual push)

```bash
# Generate ASFF output
trivy image --format asff --output findings.asff.json my-app:latest

# Push to Security Hub
aws securityhub batch-import-findings \
    --findings file://findings.asff.json \
    --region us-east-1
```

---

## What It Looks Like in Security Hub

After pushing, you'll see in the Security Hub console:

```
Findings → Filter by: Product name = "Prowler"

┌──────────────────────────────────────────────────────┐
│ Finding: S3 bucket public access not blocked         │
│ Severity: HIGH                                       │
│ Resource: arn:aws:s3:::my-bucket                     │
│ Source: Prowler                                      │
│ Status: NEW                                          │
│ Compliance: CIS AWS 2.1.5                            │
└──────────────────────────────────────────────────────┘
```

Prowler findings sit alongside GuardDuty, Inspector, and Macie findings.
Security Hub calculates a security score that includes your Prowler results.

---

## When to Use This vs. Fix First

| Scenario | Use Security Hub Integration | Use Fix First |
|----------|----------------------------|---------------|
| Client has Security Hub, wants one dashboard | Yes | Both |
| FedRAMP/SOC 2 evidence collection | Yes — auditors love Security Hub exports | Both |
| Team drowning in findings | No — adds more findings to the pile | Yes — reduce noise first |
| Proving OSS coverage to leadership | Yes — shows findings in their tool | No |
| Pre-engagement triage | No | Yes — fix before showing the client |

**The best approach is usually both:** Fix E/D rank findings first (Workflow B),
then push remaining findings to Security Hub (Workflow A). The auditor sees
a clean posture with evidence of what was found and fixed.

---

## Automation (Nightly)

```bash
# Cron job: nightly Prowler scan → Security Hub
# Add to crontab or GitHub Actions schedule

0 3 * * * prowler aws \
    --output-formats json-asff \
    --security-hub \
    --region us-east-1 \
    --severity critical high \
    2>&1 >> /var/log/prowler-securityhub.log
```

This gives you continuous monitoring via open source — findings flow into
Security Hub nightly, and Security Hub tracks trends over time.
