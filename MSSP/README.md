# MSSP — Managed Security Service Provider Framework

> Open source security for dev and staging. Enterprise tools take over in production.

This is training camp. Five packages, 49 playbooks, 250 files. Everything a junior DevOps engineer needs to harden an application from source code through cloud deployment — using free, open source tools that cover 80-90% of what enterprise platforms charge for.

The playbooks prep your environment so the production tools (Checkmarx, Prisma Cloud, Sysdig, Wiz, Drata) inherit a clean baseline instead of starting from scratch.

---

## The Five Packages

Follow them in order. Each builds on the last.

| # | Package | What It Covers | Playbooks | Time |
|---|---------|---------------|-----------|------|
| 01 | [Application Hardening](01-application-hardening/playbooks/) | Scan + fix source code, deps, Dockerfiles, IaC. CI gates. Deploy to dev. | 11 | ~2 hours |
| 02 | [Platform Hardening](02-platform-hardening/playbooks/) | Cluster audit, Kyverno admission control, RBAC, NetworkPolicy, secrets. Deploy to staging. | 10 | ~3 hours |
| 03 | [Runtime Security](03-runtime-security/playbooks/) | Falco, monitoring, logging. Deploy app via ArgoCD. Tune, forward alerts, incident response. | 10 | ~2.5 hours |
| 04 | [Cloud Security](04-cloud-security/playbooks/) | VPC, IAM, encryption, EKS hardening, detection services, ECR pipeline. | 9 | ~2 hours |
| 05 | [Compliance Ready](05-compliance-ready/playbooks/) | NIST 800-53 gap assessment, control implementation, evidence package for auditors. | 9 | ~3 hours |

**Full pass: ~12 hours of active work.** Manual equivalent: 8-16 weeks.

---

## How It Works

```
You clone your project into Target-Projects/slot-1/
                    |
    MSSP playbooks scan, fix, and harden it
                    |
    Scan results go to Target-Projects/slot-1/mssp-outputs/
                    |
    Enterprise tools take over in production
```

### Setup

```bash
# 1. Clone your project
cd Target-Projects/slot-1/
git clone <your-project-url>

# 2. Set your paths (every playbook uses these)
export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs

# 3. Start with package 01, playbook 00
cd ../../MSSP/01-application-hardening/playbooks/
```

---

## The Workflow

### Phase 1: Application Hardening (01)

Scan source code and infrastructure. Auto-fix findings. Add CI gates and pre-commit hooks. Deploy to dev.

```
00 Understand your app
01 Scan source code (secrets, SAST, CVEs, Dockerfiles)
02 Scan infrastructure (K8s manifests, Terraform, CIS benchmarks)
03 Auto-fix findings
04 Rescan and compare (before/after proof)
05 Add policy gates (Conftest OPA)
06 Add CI pipeline (GitHub Actions)
07 Add security configs (scanner configs in repo)
08 Add pre-commit hooks
09 Harden CI/CD (SHA-pin actions, sign images)
10 Deploy to dev
```

### Phase 2: Platform Hardening (02)

Harden the cluster. Admission control, RBAC, network policies, secrets management. Deploy to staging.

```
00 Audit your cluster
01 Auto-fix cluster security (NetworkPolicy, PSS, limits)
02 Deploy admission control (Kyverno)
03 RBAC audit
04 Network policies (per-service ingress/egress)
05 Secrets management (External Secrets Operator)
06 Scan and verify
07 Wire CI/CD (Conftest in pipeline)
08 Deploy staging
09 Compliance report (before/after evidence)
```

### Phase 3: Runtime Security (03)

Deploy detection BEFORE the app. Deploy the app via ArgoCD. Monitor and respond AFTER.

```
Pre-deploy:
  00 Install prerequisites
  01 Deploy Falco (syscall monitoring)
  02 Deploy monitoring (Prometheus alerts + Grafana)
  03 Deploy logging (Fluent Bit + Loki)
  04 Verify container hardening (the gate)

Deploy:
  05 Deploy application (ArgoCD with security hooks)

Post-deploy:
  06 Tune Falco (reduce noise to < 50 alerts/day)
  07 SIEM integration (forward to Splunk/Elastic/Wazuh)
  08 Incident response (timeline, forensics, contain)
  09 Detection validation (trigger attacks, verify detection)
```

### Phase 4: Cloud Security (04)

Harden the cloud account. AWS by default, Azure and GCP equivalents noted.

```
00 Scan your IaC (Checkov on Terraform/CloudFormation)
01 VPC & network security (subnets, SGs, flow logs, endpoints)
02 IAM hardening (root lockdown, MFA, IRSA, stale creds)
03 Data protection (KMS, S3/EBS/RDS encryption, Secrets Manager)
04 EKS security (private endpoint, logging, envelope encryption)
05 Monitoring & detection (CloudTrail, GuardDuty, Security Hub, Config)
06 ECR & CI/CD pipeline (OIDC federation, Trivy scan, push)
07 Security validation (Prowler + Checkov full audit)
08 Incident response (cloud IR runbooks)
```

### Phase 5: Compliance Ready (05)

Map everything to NIST 800-53. Produce evidence for auditors.

```
00 Gap assessment (scan + map to 27 NIST controls)
01 Access control (AC-2, AC-3, AC-6, AC-17)
02 Audit logging (AU-2, AU-3, AU-6, AU-12)
03 Configuration management (CM-2, CM-6, CM-7, CM-8)
04 System communications (SC-7, SC-8, SC-12, SC-28)
05 Identity & secrets (IA-2, IA-5)
06 Vulnerability & integrity (SI-2, SI-4, SI-10, RA-5, RA-7)
07 Incident response (IR-4, IR-5)
08 Documentation package (SSP, POA&M, SAR, evidence archive)
```

---

## What's in Each Package

Every package follows the same structure:

```
XX-package-name/
  playbooks/      Numbered playbooks. Follow in order.
  tools/          Shell scripts and Python tools the playbooks call.
  <configs>       Scanner configs, policies, or templates specific to the package.
```

| Package | Configs Directory | What's In It |
|---------|------------------|-------------|
| 01 | `scan-configs/` | Scanner config files (.gitleaks.toml, .bandit, trivy.yaml, etc.) |
| 01 | `templates/` | CI pipelines + pre-commit hook configs |
| 02 | `policies/` | Kyverno + Conftest policy files |
| 02 | `templates/` | External Secrets + RBAC + Helm templates |
| 03 | `falco-rules/` | Custom Falco detection rules + MITRE mappings |
| 03 | `monitoring/` | Prometheus alerts + Grafana dashboards |
| 03 | `templates/` | ArgoCD hooks + Falco Helm values per platform |
| 04 | `iac-templates/` | Terraform hardening modules |
| 04 | `security-patterns/` | VPC isolation + zero-trust SG patterns |
| 05 | `scan-configs/` | FedRAMP-tuned scanner configs |
| 05 | `compliance-docs/` | SSP, POA&M, SAR templates + control family narratives |
| 05 | `policies/` | FedRAMP Conftest + Kyverno policies |
| 05 | `ci-templates/` | Compliance CI pipeline templates |

---

## The Open Source Stack

| Tool | What It Does | Replaces in Prod |
|------|-------------|-----------------|
| **Semgrep** | SAST (multi-language) | Checkmarx, SonarQube |
| **Bandit** | Python SAST | Fortify |
| **Gitleaks** | Secret detection | GitGuardian |
| **Trivy** | CVE scanning (deps + images) | Snyk, Mend |
| **Grype** | CVE cross-check | WhiteSource |
| **Hadolint** | Dockerfile linting | Aqua Scanner |
| **Checkov** | IaC scanning | Prisma Cloud, Bridgecrew |
| **Kubescape** | K8s hardening (NSA/CISA) | Wiz, ARMO |
| **Polaris** | K8s best practices | Fairwinds |
| **Conftest** | OPA policy checks | Styra DAS |
| **Kyverno** | K8s admission control | Nirmata, Styra |
| **Falco** | Runtime syscall monitoring | Sysdig Secure, CrowdStrike |
| **Prowler** | Cloud CIS benchmarks | Prisma Cloud, Wiz |
| **Cosign** | Image signing | Sigstore (same) |

You don't need all of them installed. Scripts skip whatever is missing and tell you how to install it.

---

## Output

All scan results, reports, and evidence go to:

```
Target-Projects/slot-1/mssp-outputs/
```

Output formats: JSON (scanner results), Markdown (reports, POA&M), SARIF (GitHub Security tab compatible).

---

## Multi-Cloud

All playbooks default to **AWS**. Azure and GCP equivalent commands are shown where the workflow differs. The concepts are identical across clouds:

| Concept | AWS | Azure | GCP |
|---------|-----|-------|-----|
| Identity federation | IRSA (OIDC) | Pod Identity | Workload Identity |
| IaC scanning | `CKV_AWS_*` | `CKV_AZURE_*` | `CKV_GCP_*` |
| Threat detection | GuardDuty | Defender for Cloud | Security Command Center |
| CIS benchmark | `prowler aws` | `prowler azure` | `prowler gcp` |
| Secret management | Secrets Manager | Key Vault | Secret Manager |
| Container registry | ECR | ACR | Artifact Registry |
| Managed K8s | EKS | AKS | GKE |

---

## What This Is Not

- **Not a replacement for enterprise tools.** It's the staging version. Get clean here, enterprise takes over in prod.
- **Not an AI product.** The playbooks work without any AI. A human follows the steps and runs the commands.
- **Not a SaaS platform.** It's a git repo with scripts and playbooks. Runs anywhere — laptop, EC2, or air-gapped.
- **Not finished.** Every engagement teaches something. Playbooks grow because real problems demand real solutions.
