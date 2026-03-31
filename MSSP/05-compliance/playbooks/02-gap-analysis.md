# Playbook 02: Run a Gap Analysis

> Find out which controls are met, partially met, or missing entirely.
> This is the document that drives your remediation plan.
>
> **Time:** ~10 minutes
> **Prerequisites:** Mapped findings from [01-map-findings.md](01-map-findings.md)

---

## What a Gap Analysis Is

A gap analysis compares what you have against what the framework requires.
For every control, the answer is one of four statuses:

| Status | What It Means | Action |
|--------|-------------|--------|
| **MET** | Evidence exists, control is satisfied | Document and move on |
| **PARTIAL** | Some evidence exists, gaps remain | Close the gaps |
| **MISSING** | No evidence for this control | Implement from scratch |
| **MANUAL** | Requires human attestation, not automation | Interview stakeholders |

---

## Step 1: Build Your Control Matrix

For each control your framework requires, check your scan evidence:

```bash
# Quick gap check — do you have evidence for these critical controls?
EVIDENCE_DIR="/path/to/scan-results"

echo "=== Control Evidence Check ==="

# RA-5: Vulnerability scanning
[ -f "$EVIDENCE_DIR/01-code/trivy-deps-results.json" ] && echo "[MET]     RA-5: Vulnerability scanning (Trivy output exists)" || echo "[MISSING] RA-5: No vulnerability scan evidence"

# SI-2: Flaw remediation
[ -f "$EVIDENCE_DIR/01-code/semgrep-results.json" ] && echo "[MET]     SI-2: SAST scanning (Semgrep output exists)" || echo "[MISSING] SI-2: No SAST scan evidence"

# IA-5: Authenticator management
[ -f "$EVIDENCE_DIR/01-code/gitleaks-results.json" ] && echo "[MET]     IA-5: Secret detection (Gitleaks output exists)" || echo "[MISSING] IA-5: No secret scan evidence"

# CM-6: Configuration settings
[ -f "$EVIDENCE_DIR/02-cluster/checkov-results.json" ] && echo "[MET]     CM-6: Configuration audit (Checkov output exists)" || echo "[MISSING] CM-6: No configuration audit evidence"

# AC-6: Least privilege
[ -f "$EVIDENCE_DIR/02-cluster/polaris-static.json" ] && echo "[PARTIAL] AC-6: Best practices audit (Polaris output exists)" || echo "[MISSING] AC-6: No RBAC/privilege audit"

# SC-7: Boundary protection
[ -f "$EVIDENCE_DIR/02-cluster/conftest-results.json" ] && echo "[MET]     SC-7: Policy enforcement (Conftest output exists)" || echo "[MISSING] SC-7: No policy enforcement evidence"

# AU-2: Event logging
echo "[MANUAL]  AU-2: Check if CloudTrail is enabled (aws cloudtrail describe-trails)"
echo "[MANUAL]  AU-12: Check if GuardDuty is enabled (aws guardduty list-detectors)"
```

---

## Step 2: Create the Control Matrix Document

```markdown
# Control Matrix — [Your Project Name]
Date: [Today]
Framework: NIST 800-53 Rev 5 (Moderate baseline)

| Control | Name | Status | Evidence | Gap |
|---------|------|--------|----------|-----|
| AC-2 | Account Management | MANUAL | — | Need IAM user inventory |
| AC-3 | Access Enforcement | PARTIAL | Kyverno policies deployed | 2 namespaces without admission control |
| AC-6 | Least Privilege | PARTIAL | Polaris 100/100, RBAC scoped | No automount audit |
| AU-2 | Event Logging | MET | CloudTrail multi-region enabled | — |
| AU-12 | Audit Record Generation | MET | K8s audit logging + CloudTrail | — |
| CM-6 | Configuration Settings | MET | Checkov 256 PASS / 16 FAIL | 16 findings in POA&M |
| CM-7 | Least Functionality | PARTIAL | Kyverno policies, PSA labels | 3 namespaces without PSA |
| IA-5 | Authenticator Management | MET | Gitleaks 0 real secrets | — |
| RA-5 | Vulnerability Scanning | MET | Trivy + Grype + Semgrep | 4 HIGH CVEs in POA&M |
| SC-7 | Boundary Protection | MET | NetworkPolicy + Conftest clean | — |
| SC-28 | Protection at Rest | PARTIAL | S3 encrypted | EBS default encryption not verified |
| SI-2 | Flaw Remediation | PARTIAL | 70 CVEs fixable, 0 remaining | Before/after comparison documented |
| SI-3 | Malicious Code Protection | MET | Trivy image scan, Falco deployed | — |
```

---

## Step 3: Identify the Gaps

Look at everything that isn't **MET**:

| Priority | Status | Count | Action |
|----------|--------|-------|--------|
| **1. MISSING** | No evidence at all | Count yours | Implement the control from scratch |
| **2. PARTIAL** | Some evidence, gaps remain | Count yours | Close the specific gap identified |
| **3. MANUAL** | Needs human input | Count yours | Interview the team, document the process |

### Common gaps and how to close them:

| Gap | How to Close It | Time |
|-----|----------------|------|
| No vulnerability scanning | Run Trivy + Semgrep (Playbook 01-code/01) | 15 min |
| No secret detection | Run Gitleaks (Playbook 01-code/01) | 5 min |
| No CIS benchmark | Run kube-bench (Playbook 02-cluster/01) | 10 min |
| No admission control | Deploy Kyverno (Playbook 02-cluster/03) | 15 min |
| No CloudTrail | Enable CloudTrail (Playbook 04-cloud/04) | 10 min |
| No GuardDuty | Enable GuardDuty (Playbook 04-cloud/04) | 5 min |
| No NetworkPolicy | Add default-deny per namespace | 20 min |
| No image scanning | Run Trivy image (Playbook 03-container/01) | 10 min |

**Every gap maps back to a playbook you already have.** The compliance layer
doesn't create new work — it identifies which existing playbooks to run.

---

## Step 4: Prioritize

```
1. MISSING controls that block the audit     ← do these first
2. PARTIAL controls with specific gaps       ← close the gaps
3. MANUAL controls needing documentation     ← schedule interviews
4. MET controls needing fresh evidence       ← re-scan if >30 days old
```

---

## Next Steps

- Package evidence for auditors → [03-package-evidence.md](03-package-evidence.md)
- Build a POA&M for open findings → [04-build-poam.md](04-build-poam.md)
