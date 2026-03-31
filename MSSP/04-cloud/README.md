# 04-Cloud — AWS Security Posture

> This is what Wiz CSPM, Prisma Cloud, and CrowdStrike Falcon Cloud do.
> Here's Prowler + Checkov + tfsec + AWS native services doing 65% of it.

---

## Start Here

Cloud security has two sides:

1. **Posture** — Is your AWS account configured securely? (misconfigurations, open S3, overprivileged IAM)
2. **Infrastructure-as-Code** — Are your Terraform/CloudFormation templates secure before you deploy them?

Enterprise tools like Wiz ($100-400K/yr) and Prisma Cloud ($100-400K/yr) do both
plus attack path analysis. Open source covers the individual checks — Prowler
finds the same misconfigurations, Checkov catches the same IaC issues. The gap
is connecting them into a graph that shows which misconfigurations are actually
exploitable together.

**Follow the playbooks in order. Each one builds on the last.**

| # | Playbook | What You'll Do | Time |
|---|----------|---------------|------|
| 00 | [Know Your AWS](playbooks/00-know-your-aws.md) | Inventory accounts, regions, services in use | 5 min |
| 01 | [Scan Your Account](playbooks/01-scan-your-account.md) | Run Prowler against your live AWS account | 15 min |
| 02 | [Scan Your IaC](playbooks/02-scan-your-iac.md) | Run Checkov + tfsec against Terraform before you deploy | 10 min |
| 03 | [Harden IAM](playbooks/03-harden-iam.md) | Find and fix overprivileged roles, stale keys, missing MFA | 15 min |
| 04 | [Enable Detection](playbooks/04-enable-detection.md) | Turn on CloudTrail, GuardDuty, Security Hub (free tier) | 15 min |
| 05 | [Track Your Posture](playbooks/05-track-your-posture.md) | Before/after comparison, continuous monitoring | 10 min |

---

## The Tools

| Tool | What It Does | Install | Enterprise Equivalent |
|------|-------------|---------|----------------------|
| **Prowler** | AWS/Azure/GCP misconfiguration — 300+ checks | `pip install prowler` | Wiz CSPM ($100-400K/yr) |
| **Checkov** | IaC scanning — Terraform, CloudFormation, K8s | `pip install checkov` | Prisma Cloud IaC ($100-400K/yr) |
| **tfsec** | Terraform-specific security scanning | `brew install tfsec` | Snyk IaC ($25-100K/yr) |
| **Parliament** | AWS IAM policy linting | `pip install parliament` | Wiz CIEM ($100-400K/yr) |
| **AWS GuardDuty** | Threat detection (included in AWS) | AWS Console | CrowdStrike Falcon ($50-200K/yr) |
| **AWS Security Hub** | Findings aggregation (included in AWS) | AWS Console | Splunk ($50-500K/yr) |
| **AWS CloudTrail** | API audit logging (included in AWS) | AWS Console | Built into Wiz/Prisma |

Three of the most powerful tools are already in your AWS account — GuardDuty,
Security Hub, and CloudTrail. They just need to be turned on.

---

## Quick Start (Skip the Playbooks)

```bash
cd MSSP/04-cloud

# Scan your live AWS account (needs AWS credentials)
./scan-aws.sh

# Scan your Terraform before deploying
./scan-iac.sh /path/to/terraform
```

---

## What the Big 4 Run (and What You Can Run Instead)

| Engagement Phase | What the Big 4 Use | What You Run (Free) | Coverage |
|-----------------|-------------------|---------------------|----------|
| **Cloud Posture** | Wiz CSPM ($100-400K/yr) | Prowler (300+ checks) | 80% — same CIS checks, no attack path graph |
| **IaC Security** | Prisma Cloud ($100-400K/yr) | Checkov + tfsec | 90% — Checkov IS Prisma's engine (Bridgecrew) |
| **IAM Analysis** | Wiz CIEM ($100-400K/yr) | Parliament + aws iam cli | 50% — lints policies, no effective permission resolution |
| **Threat Detection** | CrowdStrike ($50-200K/yr) | GuardDuty (AWS native, free tier) | 80% — strong for AWS-native threats |
| **Log Aggregation** | Splunk ($50-500K/yr) | CloudTrail + CloudWatch | 60% — logs everything, no cross-service correlation |
| **Attack Path** | Wiz ($100-400K/yr) | (nothing equivalent) | 10% — this is where Wiz earns its money |
| **Data Classification** | Macie ($0.10/GB) | (nothing equivalent) | 5% — no OSS alternative for PII scanning |

### The time savings:

```
Without OSS-Copilot:
  Enterprise tool scans AWS account → 2,000+ findings
  Security team spends 3-4 weeks triaging LOW/MEDIUM noise
  Actual critical findings get buried in the backlog

With OSS-Copilot first:
  Prowler + Checkov clear routine findings in hours
  Enterprise tool scans same account → 400 findings
  Security team focuses on signal from day 1
  Weeks of triage time eliminated
```

The cloud gap is bigger than code (80%) or cluster (85%) because enterprise
tools like Wiz do graph-based analysis that has no open source equivalent.
But the 65% you get — Prowler + GuardDuty + CloudTrail + Checkov — clears
the routine findings so the enterprise tool's output is immediately actionable.

---

## What These Tools Actually Catch

**Real examples from a production AWS account:**

```
Prowler     →  S3 bucket "logs-backup" has public read ACL
                IAM user "deploy-bot" has access key older than 180 days
                CloudTrail is not enabled in us-west-2
                Root account has no MFA configured
                VPC flow logs not enabled on vpc-abc123

Checkov     →  CKV_AWS_18: S3 bucket missing access logging
                CKV_AWS_145: S3 bucket not encrypted with KMS
                CKV_AWS_24: CloudWatch log group not encrypted
                CKV_AWS_46: IAM policy allows wildcard resource

tfsec       →  aws-iam-no-policy-wildcards: Policy has * resource
                aws-s3-enable-bucket-encryption: Bucket missing encryption
                aws-vpc-no-public-ingress-sgr: Security group allows 0.0.0.0/0

GuardDuty   →  UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration
                Recon:EC2/PortProbeUnprotectedPort
                CryptoCurrency:EC2/BitcoinTool.B
```

---

## The Defense-in-Depth Model

```
DEVELOPER writes Terraform
        ↓
    Checkov + tfsec scan IaC         ← PRE-DEPLOY: catch before apply
        ↓ (pass)
    terraform apply
        ↓
    Prowler scans live account       ← POST-DEPLOY: find misconfigurations
        ↓
    GuardDuty monitors threats       ← RUNTIME: detect active attacks
        ↓
    CloudTrail logs everything       ← AUDIT: forensics trail
        ↓
    Security Hub aggregates          ← DASHBOARD: single pane of glass
```

---

## What Enterprise Does Better (the Honest 35%)

The cloud layer has the biggest enterprise gap. Here's why:

| Gap | What Enterprise Does | Why OSS Can't |
|-----|---------------------|---------------|
| **Attack path** | "Public S3 → Lambda with admin role → RDS with PII" as one finding | Requires cross-service graph — no OSS tool builds this |
| **CIEM** | Resolves effective permissions across role chains + trust policies | IAM policy simulation at scale is complex |
| **DSPM** | Scans S3/RDS for PII, PHI, financial data | No OSS data classification engine |
| **Multi-cloud** | Single view across AWS + Azure + GCP | Prowler supports all 3 but doesn't correlate |
| **Agentless** | Reads EBS snapshots without agents | Prowler needs API credentials |

**When to buy enterprise:**
- You need attack path analysis (Wiz graph — genuinely unique)
- You handle regulated data (PII/PHI) and need classification
- You run multi-cloud and need a unified posture view
- You need continuous monitoring dashboards for auditors

**When open source + AWS native is enough:**
- Single AWS account or small organization
- CIS benchmark compliance (Prowler covers this completely)
- IaC security in CI/CD (Checkov = Prisma's own engine)
- Basic threat detection (GuardDuty is genuinely good)
- Pre-SOC 2 environments proving cloud hygiene

---

## How This Connects to GP-Copilot

This directory is the open source version of
GP-CONSULTING/04-CLOUD-SECURITY in the [GP-Copilot](https://github.com/jimjrxieb/GP-copilot) repo — the
full cloud security package with 14 playbooks, 7 security patterns, 9 automation
scripts, Terraform templates, and an 8-12 week migration methodology.

| You're Here (OSS-Copilot) | Full Framework (GP-Copilot) |
|---------------------------|----------------------------|
| 2 scanners + 6 playbooks | 5 scanners + 14 playbooks |
| Prowler + Checkov | Prowler + Checkov + tfsec + Parliament + cfn-lint |
| Basic IAM audit | Full IAM hardening (IRSA, permission boundaries, Access Analyzer) |
| Enable GuardDuty/CloudTrail | Full monitoring stack (5 CloudWatch filters, 8 Config rules, SNS routing) |
| Point-in-time scans | 7 reusable security patterns (VPC isolation, zero-trust SG, DDoS resilience) |
| No IaC templates | Terraform + CloudFormation templates with hardening modules |

OSS-Copilot gives you the scanning and basic hardening for free.
The full framework adds IaC templates, security patterns, migration
methodology, and production deployment playbooks.
