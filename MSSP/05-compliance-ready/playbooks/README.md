# 05 — Compliance Ready Playbooks

> Map your security work to NIST 800-53 controls. Produce evidence an auditor can use.

This package takes everything you built in packages 01-04 and maps it to compliance frameworks — FedRAMP Moderate, NIST 800-53, SOC 2. Enterprise tools (Drata, Vanta, Anecdotes) handle continuous compliance in production. This gets the initial assessment done and the evidence organized.

---

## Follow the Playbooks in Order

| Phase | # | Playbook | Controls | Time |
|-------|---|----------|----------|------|
| **Assess** | 00 | [Gap Assessment](00-gap-assessment.md) | All 27 | 30 min |
| **Implement** | 01 | [Access Control](01-access-control.md) | AC-2, AC-3, AC-6, AC-17 | 30 min |
| **Implement** | 02 | [Audit Logging](02-audit-logging.md) | AU-2, AU-3, AU-6, AU-12 | 20 min |
| **Implement** | 03 | [Configuration Mgmt](03-configuration-management.md) | CM-2, CM-6, CM-7, CM-8 | 20 min |
| **Implement** | 04 | [System Communications](04-system-communications.md) | SC-7, SC-8, SC-12, SC-28 | 20 min |
| **Implement** | 05 | [Identity & Secrets](05-identity-secrets.md) | IA-2, IA-5 | 15 min |
| **Implement** | 06 | [Vulnerability & Integrity](06-vulnerability-integrity.md) | SI-2, SI-4, SI-10, RA-5, RA-7 | 20 min |
| **Implement** | 07 | [Incident Response](07-incident-response.md) | IR-4, IR-5 | 15 min |
| **Package** | 08 | [Documentation Package](08-documentation-package.md) | CA-2, CA-7, SA-3, SA-11 | 30 min |

---

## What's in This Directory

```
05-compliance-ready/
  playbooks/          <- You are here
  tools/              <- scan-and-map, gap-analysis, evidence packaging
  scan-configs/       <- FedRAMP-tuned scanner configs
  compliance-docs/    <- SSP, POA&M, SAR templates + control family narratives
  policies/           <- FedRAMP Conftest + Kyverno policies
  ci-templates/       <- GitHub Actions compliance pipelines
```

---

## The Tools

| Tool | What It Does |
|------|-------------|
| `run-fedramp-scan.sh` | Runs all scanners with FedRAMP configs |
| `scan-and-map.py` | Maps findings to NIST 800-53 controls |
| `gap-analysis.py` | Generates control matrix + POA&M |
| `package-evidence.sh` | Creates evidence archive with SHA256 manifest |

---

## How This Connects to Production

| This Package | Production |
|-------------|------------|
| `gap-analysis.py` | Drata, Vanta (continuous assessment) |
| `scan-and-map.py` | Anecdotes (control mapping) |
| `package-evidence.sh` | GRC platforms (evidence collection) |
| Manual control narratives | Automated compliance dashboards |

Same controls, same evidence. The enterprise tools automate the collection and reporting. This gives them a clean baseline.
