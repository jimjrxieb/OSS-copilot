# 01 — Application Hardening Playbooks

> Get your source code and infrastructure secure in dev and staging. Enterprise tools take over in production.

This is training camp. The open source scanners here cover 80-90% of what the enterprise tools find. Get everything clean with these tools first, then the enterprise scanners (Checkmarx, Snyk, Prisma Cloud, etc.) have a clean baseline to work with in production.

---

## Follow the Playbooks in Order

| Phase | # | Playbook | What You Do | Time |
|-------|---|----------|-------------|------|
| **Understand** | 00 | [Understand Your App](00-understand-your-app.md) | Profile the repo before scanning | 2 min |
| **Scan** | 01 | [Source Code Scan](01-src-code-scan.md) | Scan for secrets, SAST, CVEs, Dockerfile issues | 10 min |
| **Scan** | 02 | [Infrastructure Scan](02-infra-scan.md) | Scan K8s manifests, Terraform, CIS benchmarks | 5 min |
| **Fix** | 03 | [Auto-Fix](03-auto-fix.md) | Run automated fixes on findings | 10 min |
| **Verify** | 04 | [Rescan and Compare](04-rescan-and-compare.md) | Before/after proof | 15 min |
| **Gate** | 05 | [Add Policy Gates](05-add-policy-gates.md) | Deploy OPA/Conftest policies | 10 min |
| **Gate** | 06 | [Add CI Pipeline](06-add-ci-pipeline.md) | Security scanning on every PR | 10 min |
| **Gate** | 07 | [Add Security Configs](07-add-security-configs.md) | Scanner configs in the repo | 5 min |
| **Gate** | 08 | [Add Pre-Commit](08-add-pre-commit.md) | Catch findings before commit | 5 min |
| **Harden** | 09 | [Harden CI/CD](09-harden-cicd.md) | SHA-pin actions, sign images, SBOM | 30 min |
| **Deploy** | 10 | [Deploy Dev](10-deploy-dev.md) | Deploy to dev, validate at runtime | 20 min |

**Total: ~2 hours for the full pass.**

---

## Setup

### 1. Clone your project

```bash
cd Target-Projects/slot-1/
git clone <your-project-url>
```

### 2. Set your paths

```bash
export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
```

### 3. Follow playbook 00

---

## The Tools

| Tool | What It Does | Install |
|------|-------------|---------|
| **Semgrep** | SAST (multi-language) | `pip install semgrep` |
| **Bandit** | Python SAST | `pip install bandit` |
| **Gitleaks** | Secret detection | `brew install gitleaks` |
| **Trivy** | Dependency CVEs + image scan | `brew install trivy` |
| **Grype** | CVE cross-check | `brew install grype` |
| **Hadolint** | Dockerfile linting | `brew install hadolint` |
| **Checkov** | IaC scanning | `pip install checkov` |
| **Kubescape** | K8s hardening | `brew install kubescape` |
| **Polaris** | K8s best practices | `brew install polaris` |
| **Conftest** | OPA policy checks | `brew install conftest` |

You don't need all of them installed. Scripts skip whatever is missing.

---

## What's in This Directory

```
01-application-hardening/
  playbooks/      <- You are here. Follow these in order.
  tools/          <- Shell scripts the playbooks call
  scan-configs/   <- Scanner config files (deployed to your project)
  templates/      <- CI pipeline and pre-commit templates
```

---

## How This Connects to Production

| This Package (Dev/Staging) | Production |
|---------------------------|------------|
| Semgrep, Bandit, Gitleaks | Checkmarx, Snyk, GitGuardian |
| Trivy, Grype | Snyk SCA, Mend |
| Checkov, Kubescape, Polaris | Prisma Cloud, Wiz |
| Conftest (CI gate) | Kyverno / Gatekeeper (admission) |
| Cosign image signing | Sigstore verification at admission |

Same rules, different tools. Get everything passing here and the enterprise tools have nothing to complain about.
