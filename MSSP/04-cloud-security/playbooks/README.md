# 04 — Cloud Security Playbooks

> Harden your cloud account. AWS by default, Azure and GCP equivalents noted.

This package covers the cloud layer underneath your cluster — VPC, IAM, encryption, detection services, and container registries. Enterprise tools (Prisma Cloud, Wiz, CrowdStrike Cloud) take over in production. This gets everything clean for staging.

---

## Follow the Playbooks in Order

| Phase | # | Playbook | What You Do | Time |
|-------|---|----------|-------------|------|
| **Scan** | 00 | [Scan Your IaC](00-scan-your-iac.md) | Checkov on Terraform/CloudFormation | 15 min |
| **Foundation** | 01 | [VPC & Network](01-vpc-network-security.md) | Private subnets, SGs, flow logs, endpoints | 20 min |
| **Foundation** | 02 | [IAM Hardening](02-iam-hardening.md) | Root lockdown, MFA, IRSA, stale creds | 15 min |
| **Foundation** | 03 | [Data Protection](03-data-protection.md) | KMS, S3/EBS/RDS encryption, Secrets Manager | 15 min |
| **Harden** | 04 | [EKS Security](04-eks-security.md) | Private endpoint, logging, envelope encryption | 15 min |
| **Detect** | 05 | [Monitoring & Detection](05-monitoring-detection.md) | CloudTrail, GuardDuty, Security Hub, Config | 15 min |
| **CI/CD** | 06 | [ECR & Pipeline](06-ecr-cicd-pipeline.md) | OIDC federation, Trivy scan, push to ECR | 15 min |
| **Verify** | 07 | [Security Validation](07-security-validation.md) | Prowler + Checkov full audit | 15 min |
| **Respond** | 08 | [Incident Response](08-incident-response.md) | Cloud IR runbooks | As needed |

---

## Setup

```bash
export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
aws sts get-caller-identity  # verify AWS access
```

---

## The Tools

| Tool | What It Does | Install |
|------|-------------|---------|
| **Checkov** | IaC scanning (Terraform, CF, K8s) | `pip install checkov` |
| **Prowler** | AWS/Azure/GCP CIS benchmark | `pip install prowler` |
| **Trivy** | Container image CVE scanning | `brew install trivy` |
| **AWS CLI** | Cloud resource management | `brew install awscli` |

---

## What's in This Directory

```
04-cloud-security/
  playbooks/          <- You are here
  tools/              <- Scripts the playbooks call
  iac-templates/      <- Terraform hardening templates
  security-patterns/  <- VPC isolation, zero-trust SG patterns
```

---

## Multi-Cloud Note

All playbooks default to AWS commands. Azure and GCP equivalents are shown where the workflow differs. The concepts are the same across clouds:

| Concept | AWS | Azure | GCP |
|---------|-----|-------|-----|
| Identity federation | IRSA (OIDC) | Pod Identity | Workload Identity |
| IaC scanning | Checkov `CKV_AWS_*` | Checkov `CKV_AZURE_*` | Checkov `CKV_GCP_*` |
| Threat detection | GuardDuty | Defender for Cloud | Security Command Center |
| CIS benchmark | Prowler aws | Prowler azure | Prowler gcp |
| Secret management | Secrets Manager | Key Vault | Secret Manager |
| Container registry | ECR | ACR | Artifact Registry |
