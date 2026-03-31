# OSS-Copilot

Enterprise security tools like Prisma Cloud, Wiz, and Splunk
are excellent. They're also expensive, and they're most valuable
when your team isn't drowning in LOW and MEDIUM findings.

This repo gives you the open source playbooks to handle that
layer yourself — the scanning, the hardening, the compliance
evidence. Run these first. Let the enterprise tools focus on
what only they can catch.

Five layers. One methodology.
**Understand → Secure → Optimize → Outcome.**

No agents. No auto-fix. Just scanning, findings, and honest
guidance on when open source is enough and when it isn't.

---

## MSSP — Open Source Managed Security

Everything lives in [`MSSP/`](MSSP/) — the open source equivalent of what
managed security service providers (GuidePoint, Deloitte, PwC, KPMG) deploy
with enterprise tooling costing $200K-$2M/yr.

Same methodology. Same coverage areas. Open source tools.

### The 5 C's

| Layer | What MSSPs Deploy | What You Run (Free) | Directory |
|-------|-------------------|---------------------|-----------|
| **Code** | Checkmarx, Snyk Code, GitGuardian | Semgrep, Bandit, Gitleaks, Trivy | [`MSSP/01-code/`](MSSP/01-code/) |
| **Cluster** | Wiz K8s, Styra DAS, Teleport | kube-bench, Kubescape, Polaris, Kyverno | [`MSSP/02-cluster/`](MSSP/02-cluster/) |
| **Container** | Prisma Cloud CWPP, Sysdig Secure | Trivy, Hadolint, Falco | [`MSSP/03-container/`](MSSP/03-container/) |
| **Cloud** | Wiz CSPM, Prisma Cloud | Prowler, Checkov, tfsec | [`MSSP/04-cloud/`](MSSP/04-cloud/) |
| **Compliance** | Drata, Vanta | OPA, manual mapping, evidence scripts | [`MSSP/05-compliance/`](MSSP/05-compliance/) |

Each directory has:
- **Playbooks** — step-by-step guides a beginner can follow
- **Shell scripts** — run the scanners, copy-paste, works today
- **Enterprise comparison** — what the Big 4 use, what OSS covers, where the gap is
- **Honest guidance** — when to buy the enterprise tool and when open source is enough

---

## How to Use This

```bash
cd MSSP

# Pick a layer. Follow the playbooks.
cd 01-code && cat playbooks/00-understand-your-repo.md

# Or just scan something right now
cd 01-code && ./scan-code.sh /path/to/your/project
cd 02-cluster && ./scan-cis.sh
cd 03-container && ./scan-images.sh nginx:1.25
cd 04-cloud && ./scan-aws.sh
cd 05-compliance && ./map-nist.sh
```

---

## Who This Is For

**Security teams** who want coverage before (or instead of) enterprise licenses.

**MSSPs and consultants** (GuidePoint, Deloitte, PwC) who walk into client
environments and need a triage layer before the enterprise tools add value.
Run this first. Clear the noise. Then the $200K/yr tool focuses on signal.

**Platform engineers** who own the Kubernetes stack and need to prove it's
hardened without waiting for a vendor POC.

**Students and cert preppers** — the cluster playbooks map directly to CKS
(Certified Kubernetes Security Specialist) exam domains.

## Philosophy

Open source handles the load. Paid tools handle the gap.

This repo is not anti-enterprise. Prisma Cloud, Wiz, and Splunk are genuinely
good at what they do. But most of what they catch in their first scan — the LOWs,
the MEDIUMs, the misconfigurations — open source catches too.

Run OSS-Copilot first. Fix the noise. Then point your enterprise tool at what's
left. That's when you get real value from the license.

## Enterprise Coverage Map

For the full tool-by-tool breakdown across all 5 C's — what enterprise does,
what open source covers, and where to buy:

[`docs/enterprise-map.md`](docs/enterprise-map.md)

## Enterprise Integrations

Two ways to connect OSS-Copilot to enterprise tools:

| Integration | Method | Guide |
|-------------|--------|-------|
| **AWS Security Hub** | Prowler pushes ASFF natively (one flag) | [`docs/integrations/security-hub.md`](docs/integrations/security-hub.md) |
| **Prisma Cloud** | Checkov outputs Prisma format natively | [`docs/integrations/prisma-cloud.md`](docs/integrations/prisma-cloud.md) |
| **Splunk** | Any scanner JSON via HTTP Event Collector | [`docs/integrations/splunk.md`](docs/integrations/splunk.md) |
| **Wiz** | Fix first — Wiz sees clean environment | [`docs/integrations/wiz.md`](docs/integrations/wiz.md) |
| **CrowdStrike** | Via Splunk intermediary | [`docs/integrations/crowdstrike.md`](docs/integrations/crowdstrike.md) |

Full guide: [`docs/integrations/README.md`](docs/integrations/README.md)

## Prerequisites

Most scripts check for tool availability and print install instructions if missing.
Core tools used across layers:

| Tool | Install | Used In |
|------|---------|---------|
| [Trivy](https://github.com/aquasecurity/trivy) | `brew install trivy` | Code, Container, Cloud |
| [Semgrep](https://github.com/returntocorp/semgrep) | `pip install semgrep` | Code |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | `brew install gitleaks` | Code |
| [Hadolint](https://github.com/hadolint/hadolint) | `brew install hadolint` | Container |
| [kube-bench](https://github.com/aquasecurity/kube-bench) | `brew install kube-bench` | Cluster |
| [Kubescape](https://github.com/kubescape/kubescape) | `curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh \| bash` | Cluster |
| [Prowler](https://github.com/prowler-cloud/prowler) | `pip install prowler` | Cloud |
| [Checkov](https://github.com/bridgecrewio/checkov) | `pip install checkov` | Cloud |

## License

MIT. Use it, fork it, sell engagements with it. That's the point.
