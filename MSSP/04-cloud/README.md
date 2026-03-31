# 04-Cloud — Cloud Security Posture Management

## What Wiz CSPM Does

Cloud Security Posture Management. Wiz connects to your AWS/Azure/GCP accounts
via read-only API access, inventories every resource, scans for misconfigurations,
and builds an attack graph that shows which misconfigurations are actually
exploitable. It combines CSPM (configuration), CIEM (identity), and DSPM (data)
into a single graph — "this public S3 bucket contains PII, is accessible via this
over-permissioned Lambda, which is triggered by this unauthenticated API Gateway."

## What Open Source Covers (the 80%)

| Tool | What It Scans | Install |
|------|--------------|---------|
| **Prowler** | AWS/Azure/GCP misconfiguration — 300+ checks per cloud | `pip install prowler` |
| **Checkov** | IaC scanning — Terraform, CloudFormation, ARM, K8s | `pip install checkov` |
| **tfsec** | Terraform-specific security scanning | `brew install tfsec` |
| **Trivy config** | IaC scanning — Terraform, Dockerfile, K8s manifests | `brew install trivy` |
| **Parliament** | AWS IAM policy linting | `pip install parliament` |

## How to Run It

```bash
# Scan live AWS account
./scan-aws.sh

# Scan Infrastructure-as-Code
./scan-iac.sh /path/to/terraform
```

## What the Enterprise Tool Does Better (the 20%)

- **Attack graph**: Wiz connects misconfigurations across services into exploitable
  paths. Prowler finds "S3 bucket is public" and "Lambda has admin role" as separate
  findings. Wiz shows they're connected and exploitable together.
- **CIEM (identity analysis)**: Wiz maps effective permissions across roles, policies,
  and trust relationships. Parliament lints individual policies but doesn't resolve
  the full permission chain.
- **DSPM (data security)**: Wiz scans data stores for sensitive data (PII, PHI,
  credentials) and maps access paths to that data. No open source equivalent.
- **Multi-cloud correlation**: Wiz provides a single view across AWS, Azure, and GCP.
  Prowler supports all three but doesn't correlate across clouds.

## When to Escalate to the Enterprise Tool

- You need **attack path analysis** — not just "what's misconfigured" but "what's exploitable"
- You need **CIEM** — understanding effective permissions across complex IAM hierarchies
- You need **DSPM** — finding and classifying sensitive data in cloud storage
- You run **multi-cloud** and need a unified posture view
- Compliance requires **continuous posture monitoring** with historical trending
