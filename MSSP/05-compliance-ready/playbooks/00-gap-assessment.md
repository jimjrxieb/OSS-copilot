# 00 — Gap Assessment

> Run the FedRAMP/NIST scan, map findings to controls, see where you stand.

This is the starting point. One script scans everything (code, containers, IaC, cluster), maps findings to NIST 800-53 controls, and tells you which controls are MET, PARTIAL, MISSING, or MANUAL.

In production, tools like Drata, Vanta, and Anecdotes handle continuous compliance. This gets you the initial assessment and gap analysis.

---

## What You Need

- Packages 01-04 completed (app hardened, cluster hardened, runtime deployed, cloud secured)
- Your paths set:
  ```bash
  export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

---

## Step 1: Run the FedRAMP Scan

```bash
bash tools/run-fedramp-scan.sh --target $TARGET_DIR --output $OUTPUT_DIR
```

This runs all scanners with FedRAMP-tuned configs from `scan-configs/`:
- Trivy (with `trivy-fedramp.yaml`)
- Semgrep (with `semgrep-fedramp.yaml`)
- Gitleaks (with `gitleaks-fedramp.toml`)
- Checkov (IaC)
- Kubescape (cluster)

---

## Step 2: Map Findings to NIST Controls

```bash
python3 tools/scan-and-map.py --scan-dir $OUTPUT_DIR --output $OUTPUT_DIR/control-mapping.md
```

This maps every finding to its NIST 800-53 control:
- Gitleaks secret → IA-5 (Authenticator Management)
- Missing encryption → SC-28 (Protection of Information at Rest)
- No audit logs → AU-2 (Audit Events)
- Running as root → AC-6 (Least Privilege)

---

## Step 3: Generate Gap Analysis

```bash
python3 tools/gap-analysis.py --scan-dir $OUTPUT_DIR --output $OUTPUT_DIR/
```

**Produces:**
- `control-matrix.md` — every control marked MET / PARTIAL / MISSING / MANUAL
- `poam.md` — Plan of Action & Milestones for MISSING controls
- `remediation-plan.md` — prioritized fix list

---

## Step 4: Review Your Score

```bash
cat $OUTPUT_DIR/control-matrix.md
```

**Typical first scan:** 30-45% MET. That's normal. The remediation playbooks (01-07) bring it to 80%+.

| Status | Meaning | Action |
|--------|---------|--------|
| **MET** | Control fully satisfied by evidence | None — document it |
| **PARTIAL** | Some aspects covered, gaps remain | Fix the gaps |
| **MISSING** | No evidence for this control | Implement the control |
| **MANUAL** | Can't be automated — needs human process | Write the policy/procedure |

---

## The 27 Controls Covered

| Family | Controls | What They Cover |
|--------|----------|----------------|
| **AC** (Access Control) | AC-2, AC-3, AC-6, AC-17 | Account management, RBAC, least privilege |
| **AU** (Audit) | AU-2, AU-3, AU-6, AU-12 | Logging, log content, review, generation |
| **CA** (Assessment) | CA-2, CA-7 | Security assessment, continuous monitoring |
| **CM** (Config Mgmt) | CM-2, CM-6, CM-7, CM-8 | Baselines, config settings, least functionality |
| **IA** (Identity) | IA-2, IA-5 | MFA, credential management |
| **IR** (Incident Response) | IR-4, IR-5 | Incident handling, monitoring |
| **RA** (Risk Assessment) | RA-5, RA-7 | Vulnerability scanning, risk response |
| **SA** (System Acquisition) | SA-3, SA-11 | SDLC, developer testing |
| **SC** (System Comms) | SC-7, SC-8, SC-12, SC-28 | Boundary protection, TLS, crypto, encryption |
| **SI** (System Integrity) | SI-2, SI-4, SI-10 | Patching, monitoring, input validation |

---

## Next Step

Go to [01-access-control.md](01-access-control.md) to start implementing controls.
