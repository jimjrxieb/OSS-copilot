# 05-Compliance — Evidence Packaging and Control Mapping

> This is what Drata, Vanta, and Anecdotes do.
> Here's how to map your scan findings to compliance controls
> and package evidence for auditors — using scripts and the output
> from the other 4 layers.

---

## Start Here

Compliance is not a separate activity. It's the evidence that the first four
layers (Code, Cluster, Container, Cloud) were done correctly. Every scanner
you ran in layers 01-04 produced JSON output. This layer maps those findings
to compliance controls and packages them for auditors.

**The key insight:** You already did most of the compliance work. You just
need to prove it.

**Follow the playbooks in order. Each one builds on the last.**

| # | Playbook | What You'll Do | Time |
|---|----------|---------------|------|
| 00 | [Know Your Framework](playbooks/00-know-your-framework.md) | Figure out which compliance framework applies to you | 5 min |
| 01 | [Map Findings to Controls](playbooks/01-map-findings.md) | Connect scanner output to NIST/CIS/SOC 2 controls | 10 min |
| 02 | [Run a Gap Analysis](playbooks/02-gap-analysis.md) | Find which controls are met, partial, or missing | 10 min |
| 03 | [Package Evidence](playbooks/03-package-evidence.md) | Bundle everything into an auditor-ready archive | 10 min |
| 04 | [Build a POA&M](playbooks/04-build-poam.md) | Track open findings with remediation dates | 10 min |
| 05 | [Continuous Compliance](playbooks/05-continuous-compliance.md) | Schedule recurring scans and track posture over time | 10 min |

---

## The Tools

| Tool | What It Does | Install | Enterprise Equivalent |
|------|-------------|---------|----------------------|
| **Conftest/OPA** | Validate configs against compliance rules | `brew install conftest` | Styra DAS ($50-150K/yr) |
| **Prowler** | CIS AWS Benchmark evidence (300+ checks) | `pip install prowler` | Drata AWS integration |
| **kube-bench** | CIS Kubernetes Benchmark evidence | `brew install kube-bench` | Vanta K8s integration |
| **map-nist.sh** | Map scanner findings to NIST 800-53 controls | Built-in | Drata control mapping ($15-50K/yr) |
| **package-evidence.sh** | Bundle evidence for auditors | Built-in | Drata evidence collection ($15-50K/yr) |

---

## Quick Start (Skip the Playbooks)

```bash
cd MSSP/05-compliance

# Map your scan findings to NIST 800-53 controls
./map-nist.sh /path/to/scan-results

# Package everything for your auditor
./package-evidence.sh
```

---

## What the Big 4 Run (and What You Can Run Instead)

| Engagement Phase | What the Big 4 Use | What You Run | Coverage |
|-----------------|-------------------|-------------|----------|
| **Control Mapping** | Drata ($15-50K/yr) | map-nist.sh + scan-and-map.py | 55% — maps scanner findings to 27 NIST controls |
| **Gap Analysis** | Vanta ($15-50K/yr) | gap-analysis.py | 55% — identifies MET/PARTIAL/MISSING per control |
| **Evidence Collection** | Drata ($15-50K/yr) | package-evidence.sh | 50% — bundles scan JSON + manifests + reports |
| **POA&M Generation** | GRC tools ($50-200K/yr) | Scripts + templates | 45% — auto-populated, manual lifecycle |
| **Continuous Monitoring** | Drata ($15-50K/yr) | Cron + CI pipeline | 40% — weekly scans, no real-time dashboard |
| **Auditor Portal** | Drata/Vanta | ZIP files + shared drive | 20% — no self-service portal |
| **Multi-Framework Mapping** | Drata (1,400+ controls) | Single framework per run | 30% — NIST 800-53 only by default |

### The time savings:

```
Without OSS-Copilot:
  Auditor asks for evidence of vulnerability scanning (RA-5)
  Team scrambles to find last scan report → 2 hours
  Auditor asks for RBAC evidence (AC-6)
  Team screenshots kubectl output → 1 hour
  Repeat 27 times → 2-3 weeks of evidence gathering

With OSS-Copilot:
  package-evidence.sh bundles everything in 5 minutes
  Scan reports + control mapping + gap analysis in one archive
  Auditor opens ZIP, finds evidence organized by control family
  2-3 weeks → 1 day
```

---

## How Compliance Maps to the Other 4 Layers

Every compliance control traces back to a scanner you already ran:

| Control | What It Requires | Evidence From | Layer |
|---------|-----------------|---------------|-------|
| **RA-5** | Vulnerability scanning | Trivy, Semgrep, Grype JSON | 01-code |
| **SI-2** | Flaw remediation | Before/after scan comparison | 01-code |
| **IA-5** | Authenticator management | Gitleaks (no secrets in code) | 01-code |
| **SA-11** | Developer testing | Semgrep, Bandit SAST reports | 01-code |
| **CM-6** | Configuration settings | Checkov, Polaris, kube-bench | 02-cluster |
| **AC-6** | Least privilege | RBAC audit, Kyverno policies | 02-cluster |
| **SC-7** | Boundary protection | NetworkPolicy audit, Conftest | 02-cluster |
| **SI-3** | Malicious code protection | Trivy image scan, Falco | 03-container |
| **AU-2** | Event logging | CloudTrail, GuardDuty status | 04-cloud |
| **SC-28** | Protection of information at rest | KMS encryption checks | 04-cloud |

**You already have the evidence. You just need to organize it.**

---

## What Enterprise Does Better (the Honest 50%)

Compliance has the biggest enterprise gap of all 5 layers. Here's why:

| Gap | What Enterprise Does | Why Scripts Can't |
|-----|---------------------|-------------------|
| **Continuous monitoring** | Drata checks every 24 hours automatically | Scripts run when you remember |
| **Auditor portal** | Self-service evidence access for auditors | You email ZIP files |
| **Multi-framework** | Maps to SOC 2 + HIPAA + ISO 27001 + FedRAMP simultaneously | One framework at a time |
| **75+ integrations** | Pulls evidence from HR, identity, ticketing, cloud | Scripts cover scanners only |
| **Historical trending** | Shows compliance posture over months/years | Point-in-time snapshots |
| **Workflow management** | Assign controls to owners, track remediation | Manual in spreadsheets |

**When to buy Drata/Vanta:**
- SOC 2 Type II or FedRAMP continuous monitoring (requires 24/7 evidence)
- Multiple frameworks simultaneously (SOC 2 + HIPAA + ISO 27001)
- Auditor wants a portal, not ZIP files
- Team spending >40 hours per audit cycle on evidence gathering

**When open source is enough:**
- SOC 2 Type I (point-in-time assessment)
- Pre-compliance — proving basic hygiene before a formal audit
- Single framework (NIST 800-53 or CIS)
- Internal security assessments
- Proving to leadership that controls exist before investing in Drata

---

## How This Connects to GP-Copilot

This directory is the open source version of
GP-CONSULTING/05-COMPLIANCE-READY in the [GP-Copilot](https://github.com/jimjrxieb/GP-copilot) repo — the
full compliance automation package with 12 playbooks, scan-to-control mapping
for 44 finding types, automated gap analysis, evidence bundling with S3
Object Lock, and FedRAMP-specific documentation templates.

| You're Here (OSS-Copilot) | Full Framework (GP-Copilot) |
|---------------------------|----------------------------|
| NIST mapping script | scan-and-map.py (44 finding types → 27 controls) |
| Basic gap analysis | gap-analysis.py (MET/PARTIAL/MISSING + auto-POA&M) |
| Evidence as ZIP | Evidence with S3 Object Lock (AU-9 immutable storage) |
| Point-in-time scans | Continuous compliance pipeline (CI + cron) |
| No SSP templates | SSP + SAR + 10 control family documents |
| Single framework | FedRAMP Low/Moderate/High ready |

OSS-Copilot gives you the mapping and evidence packaging for free.
The full framework adds FedRAMP documentation, automated gap analysis,
and evidence lifecycle management for formal compliance programs.
