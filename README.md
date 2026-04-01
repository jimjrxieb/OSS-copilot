# OSS-Copilot

Open source security for dev and staging. Enterprise tools take over in production.

Five packages. 49 playbooks. 250 files. Everything a junior DevOps engineer needs to harden an application from source code through cloud deployment — using free tools that cover 80-90% of what enterprise platforms charge for.

Run these first. Fix the noise. Then the enterprise tools (Checkmarx, Prisma Cloud, Wiz, Sysdig, Drata) focus on signal instead of drowning in LOW and MEDIUM findings.

---

## MSSP — The Framework

Everything lives in [`MSSP/`](MSSP/). Five packages, run in order:

| # | Package | What It Covers | Playbooks | Time |
|---|---------|---------------|-----------|------|
| 01 | [Application Hardening](MSSP/01-application-hardening/playbooks/) | Scan + fix source code, deps, Dockerfiles, IaC. CI gates. Deploy to dev. | 11 | ~2 hrs |
| 02 | [Platform Hardening](MSSP/02-platform-hardening/playbooks/) | Cluster audit, Kyverno, RBAC, NetworkPolicy, secrets. Deploy to staging. | 10 | ~3 hrs |
| 03 | [Runtime Security](MSSP/03-runtime-security/playbooks/) | Falco, monitoring, logging. ArgoCD deploy. Tune, SIEM, incident response. | 10 | ~2.5 hrs |
| 04 | [Cloud Security](MSSP/04-cloud-security/playbooks/) | VPC, IAM, encryption, EKS, detection services, ECR pipeline. AWS default, Azure/GCP noted. | 9 | ~2 hrs |
| 05 | [Compliance Ready](MSSP/05-compliance-ready/playbooks/) | NIST 800-53 gap assessment, control implementation, evidence package. | 9 | ~3 hrs |

**Full pass: ~12 hours.** Manual equivalent: 8-16 weeks.

---

## Quick Start

```bash
# 1. Clone your project into a slot
cd Target-Projects/slot-1/
git clone <your-project-url>

# 2. Set your paths (every playbook uses these)
export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs

# 3. Start with package 01, playbook 00
cd ../../MSSP/01-application-hardening/playbooks/
# Open 00-understand-your-app.md and follow the steps
```

Scan results go to `Target-Projects/slot-1/mssp-outputs/`.

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
| **Checkov** | IaC scanning (Terraform, CF, K8s) | Prisma Cloud, Bridgecrew |
| **Kubescape** | K8s hardening (NSA/CISA) | Wiz, ARMO |
| **Polaris** | K8s best practices | Fairwinds |
| **Conftest** | OPA policy checks | Styra DAS |
| **Kyverno** | K8s admission control | Nirmata, Styra |
| **Falco** | Runtime syscall monitoring | Sysdig Secure, CrowdStrike |
| **Prowler** | Cloud CIS benchmarks | Prisma Cloud, Wiz |
| **Cosign** | Image signing | Sigstore |

Scripts skip whatever isn't installed and tell you how to install it.

---

## The Workflow

### Phase 1 — Application Hardening

Scan source code and infrastructure. Auto-fix. Add CI gates. Deploy to dev.

```
00 Understand your app           05 Add policy gates (Conftest)
01 Scan source code              06 Add CI pipeline
02 Scan infrastructure           07 Add security configs
03 Auto-fix findings             08 Add pre-commit hooks
04 Rescan and compare            09 Harden CI/CD
                                 10 Deploy to dev
```

### Phase 2 — Platform Hardening

Harden the cluster. Deploy admission control. Lock down access and network. Deploy to staging.

```
00 Audit your cluster            05 Secrets management (ESO)
01 Auto-fix cluster security     06 Scan and verify
02 Deploy admission control      07 Wire CI/CD
03 RBAC audit                    08 Deploy staging
04 Network policies              09 Compliance report
```

### Phase 3 — Runtime Security

Deploy detection before the app. Deploy the app. Monitor and respond after.

```
Pre-deploy:                      Post-deploy:
  00 Install prerequisites         06 Tune Falco
  01 Deploy Falco                  07 SIEM integration
  02 Deploy monitoring             08 Incident response
  03 Deploy logging                09 Detection validation
  04 Verify container hardening
Deploy:
  05 Deploy application (ArgoCD)
```

### Phase 4 — Cloud Security

Harden the cloud account. AWS by default, Azure and GCP equivalents noted.

```
00 Scan your IaC                 05 Monitoring & detection
01 VPC & network security        06 ECR & CI/CD pipeline
02 IAM hardening                 07 Security validation
03 Data protection               08 Incident response
04 EKS security
```

### Phase 5 — Compliance Ready

Map everything to NIST 800-53. Produce evidence for auditors.

```
00 Gap assessment                05 Identity & secrets (IA)
01 Access control (AC)           06 Vulnerability & integrity (SI/RA)
02 Audit logging (AU)            07 Incident response (IR)
03 Configuration management (CM) 08 Documentation package
04 System communications (SC)
```

---

## Repository Structure

```
OSS-copilot/
  MSSP/                          <- The framework (5 packages, 49 playbooks)
    01-application-hardening/    <- Code + infra scanning, fixing, CI gates
    02-platform-hardening/       <- K8s hardening, admission control, RBAC
    03-runtime-security/         <- Falco, monitoring, ArgoCD deploy, IR
    04-cloud-security/           <- AWS/Azure/GCP hardening, detection
    05-compliance-ready/         <- NIST 800-53, FedRAMP, evidence packaging
  Target-Projects/               <- Where you clone projects to scan
    slot-1/
      mssp-outputs/              <- Scan results land here
    slot-2/
    slot-3/
  Mlops/                         <- ML pipeline tooling (separate)
  docs/                          <- Enterprise integration guides
```

---

## Multi-Cloud

All playbooks default to AWS. Azure and GCP equivalents are shown where the workflow differs.

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

## Who This Is For

**Junior DevOps engineers** who need step-by-step guidance on security hardening.

**Security teams** who want to clear the noise before enterprise tools run.

**MSSPs and consultants** who walk into client environments and need a triage layer before the enterprise stack adds value.

**Platform engineers** who own the Kubernetes stack and need to prove it's hardened.

**Students and cert preppers** — the cluster and cloud playbooks map to CKS, AWS Security Specialty, and NIST frameworks.

---

## Philosophy

Open source handles the load. Paid tools handle the gap.

This is not anti-enterprise. Prisma Cloud, Wiz, and Sysdig are genuinely good at what they do. But most of what they catch in their first scan — the LOWs, the MEDIUMs, the misconfigurations — open source catches too.

Run this first. Fix the noise. Then the enterprise tool focuses on what only it can do: deep taint analysis, ML anomaly detection, attack path mapping, and global threat intelligence.

That's when you get real value from the license.

---

## License

MIT. Use it, fork it, sell engagements with it. That's the point.
