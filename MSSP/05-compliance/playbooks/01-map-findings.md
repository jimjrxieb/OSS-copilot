# Playbook 01: Map Findings to Controls

> Connect your scanner output to compliance controls.
> Turn JSON findings into a control matrix an auditor can use.
>
> **Time:** ~10 minutes
> **Prerequisites:** Scan results from layers 01-04

---

## What Control Mapping Means

An auditor doesn't ask "did Trivy find CVEs?" They ask "how do you satisfy
RA-5 (Vulnerability Monitoring and Scanning)?" Control mapping translates
scanner output into compliance language.

```
Scanner finding:      Trivy found 4 HIGH CVEs in tar@7.5.6
Control language:     RA-5: Vulnerability scans performed, 4 HIGH findings
                      identified in package dependencies, fixed in 7.5.10
```

---

## Step 1: Gather Your Scan Results

```bash
# Your scan output should be organized like this:
ls MSSP/example-output/
# 01-code/     → gitleaks, semgrep, trivy, grype JSON
# 02-cluster/  → polaris, checkov, conftest JSON
# 04-cloud/    → prowler output (if you ran it)
```

If you followed the playbooks in layers 01-04, all of this already exists.

---

## Step 2: Run the NIST Mapping Script

```bash
cd MSSP/05-compliance

# Map findings to NIST 800-53 controls
./map-nist.sh /path/to/scan-results
```

### What the script does:

1. Reads every JSON file in your scan results directory
2. Categorizes findings by type (CVE, secret, misconfig, SAST finding)
3. Maps each finding type to NIST 800-53 controls
4. Outputs a JSON report and a human-readable summary

### The mapping logic:

| Finding Type | Mapped Controls | Why |
|-------------|----------------|-----|
| Dependency CVEs (Trivy/Grype) | **RA-5** (Vulnerability Scanning), **SI-2** (Flaw Remediation) | CVE = known vulnerability = evidence of scanning |
| Secrets in code (Gitleaks) | **IA-5** (Authenticator Management) | Hardcoded secret = credential management failure |
| Code vulnerabilities (Semgrep) | **SA-11** (Developer Testing), **SI-2** (Flaw Remediation) | SAST finding = evidence of secure development |
| K8s misconfigs (Checkov/Polaris) | **CM-6** (Configuration Settings), **CM-7** (Least Functionality) | Misconfiguration = configuration management gap |
| Privileged containers | **AC-6** (Least Privilege), **CM-6** (Configuration Settings) | Privileged = excessive permissions |
| Missing NetworkPolicy | **SC-7** (Boundary Protection) | No network segmentation = boundary protection gap |
| Missing encryption | **SC-28** (Protection at Rest) | Unencrypted storage = data protection gap |

---

## Step 3: Read the Output

```bash
# Human-readable summary
cat /path/to/scan-results/.oss-copilot/compliance/nist-800-53-summary.txt

# Machine-readable JSON
cat /path/to/scan-results/.oss-copilot/compliance/nist-800-53-mapping.json | python3 -m json.tool
```

### Example output:

```
NIST 800-53 Rev 5 — Control Mapping Summary
Generated: 2026-03-31
Total findings mapped: 77
Controls affected: 8

============================================================

[FAIL] AC-6 — Least Privilege
       3 finding(s)
[FAIL] CM-6 — Configuration Settings
       16 finding(s)
[FAIL] RA-5 — Vulnerability Monitoring and Scanning
       74 finding(s)
[FAIL] SI-2 — Flaw Remediation
       74 finding(s)
[PASS] AU-2 — Event Logging
[PASS] AU-3 — Content of Audit Records
[PASS] SC-7 — Boundary Protection
[PASS] SC-28 — Protection of Information at Rest
```

**FAIL doesn't mean non-compliant.** It means findings exist. The evidence shows
you scanned (RA-5 = satisfied), found issues, and are tracking remediation.
That's what compliance requires — not perfection, but process.

---

## Step 4: Understand PASS vs. FAIL

| Status | What It Means | Auditor Perspective |
|--------|-------------|---------------------|
| **PASS (no findings)** | Scanner ran, found nothing | Control satisfied — evidence of scanning with clean results |
| **FAIL (findings exist)** | Scanner ran, found issues | Control partially satisfied — shows scanning works. Need POA&M for open findings. |
| **No evidence** | Scanner didn't run or no output | Control NOT satisfied — no evidence of the activity |

**The worst status is "no evidence."** Even a scan with 100 findings is better
than no scan at all — it proves the capability exists.

---

## Step 5: Expand Beyond NIST

### CIS benchmarks (already mapped):

```bash
# kube-bench output IS the CIS K8s evidence
cat .oss-copilot/cluster-baseline-*/kube-bench.json

# Prowler output IS the CIS AWS evidence
cat .oss-copilot/cloud-baseline-*/prowler-output-*.json
```

### SOC 2 mapping:

SOC 2 trust criteria map closely to NIST controls:

| SOC 2 Criteria | NIST Control | Your Evidence |
|---------------|--------------|---------------|
| CC6.1 (Logical access) | AC-6 | RBAC audit, Kyverno policies |
| CC6.6 (System boundaries) | SC-7 | NetworkPolicy audit |
| CC7.1 (Monitoring) | SI-4 | Falco deployment, GuardDuty |
| CC8.1 (Change management) | CM-6 | ArgoCD + Conftest in CI |

---

## Next Steps

- Run a gap analysis → [02-gap-analysis.md](02-gap-analysis.md)
- Package evidence for auditors → [03-package-evidence.md](03-package-evidence.md)
