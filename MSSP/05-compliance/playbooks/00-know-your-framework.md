# Playbook 00: Know Your Framework

> Before you map findings to controls, know which framework applies to you.
>
> **Time:** 5 minutes
> **Prerequisites:** None — just know your business context

---

## Which Framework Do You Need?

| If You... | Framework | Controls | Typical Timeline |
|-----------|----------|----------|-----------------|
| Sell to enterprises (SaaS) | **SOC 2** | ~60 trust criteria | 3-6 months (Type I), 6-12 months (Type II) |
| Handle healthcare data (PHI) | **HIPAA** | ~180 requirements | 6-12 months |
| Handle credit card data | **PCI DSS** | ~300 requirements | 3-6 months |
| Sell to US federal government | **FedRAMP** | 125-421 controls (depends on impact) | 12-24 months |
| Want a general security baseline | **NIST 800-53** | 1,000+ controls (select what applies) | Ongoing |
| Want K8s-specific hardening proof | **CIS Kubernetes Benchmark** | ~120 checks | 1-2 weeks |
| Want AWS-specific hardening proof | **CIS AWS Foundations** | ~50 checks | 1-2 weeks |
| International customers (EU) | **ISO 27001** | 93 controls (Annex A) | 6-12 months |

---

## What Most Teams Actually Need

**If you're not sure:** Start with CIS benchmarks. kube-bench (K8s) and Prowler
(AWS) already check these. You have the evidence from layers 02 and 04.

**If you need SOC 2:** Most SOC 2 trust criteria map to NIST 800-53 controls.
Start with NIST mapping (this repo does this), and your SOC 2 auditor will
recognize the controls.

**If you need FedRAMP:** The full GP-Copilot framework has FedRAMP-specific
templates. OSS-Copilot covers the scanning and mapping foundation — you'll
need the full framework (or a consultant) for SSP, SAR, and 3PAO prep.

---

## The Controls You Already Have Evidence For

If you ran layers 01-04, you already have evidence for these controls:

| Framework | Controls With Evidence | How |
|-----------|----------------------|-----|
| **NIST RA-5** (Vulnerability Scanning) | Trivy + Semgrep + Grype output | 01-code |
| **NIST SI-2** (Flaw Remediation) | Before/after scan comparison | 01-code |
| **NIST CM-6** (Configuration Settings) | Checkov + Polaris + kube-bench | 02-cluster |
| **NIST AC-6** (Least Privilege) | RBAC audit + Kyverno policies | 02-cluster |
| **NIST SC-7** (Boundary Protection) | NetworkPolicy audit + Conftest | 02-cluster |
| **NIST SI-3** (Malicious Code Protection) | Trivy image scan + Falco | 03-container |
| **NIST AU-2** (Event Logging) | CloudTrail + GuardDuty status | 04-cloud |
| **CIS K8s 1.x-5.x** | kube-bench full report | 02-cluster |
| **CIS AWS 1.x-5.x** | Prowler full report | 04-cloud |

**You don't need to start from zero.** The scanners already produced the evidence.
This layer organizes it.

---

## Next Steps

Go to: [01-map-findings.md](01-map-findings.md)
