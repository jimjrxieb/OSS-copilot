# 08 — Documentation Package

> Produce the SSP, POA&M, SAR, and evidence package. This is the deliverable.

Everything from playbooks 00-07 produces evidence. This playbook packages it into the documents an auditor needs.

---

## The Five Documents

| Document | Template | What It Is |
|----------|----------|-----------|
| **SSP** (System Security Plan) | `compliance-docs/ssp-skeleton.md` | How the system works and how controls are implemented |
| **POA&M** (Plan of Action & Milestones) | `compliance-docs/poam-template.md` | Open findings with fix dates |
| **SAR** (Security Assessment Report) | `compliance-docs/sar-template.md` | Scan results and assessment findings |
| **Control Matrix** | `compliance-docs/control-matrix-template.md` | Status of each control (MET/PARTIAL/MISSING) |
| **Control Narratives** | `compliance-docs/control-families/*.md` | How each control family is implemented |

---

## Step 1: Generate Automated Artifacts

```bash
# Fresh scan (evidence must be < 30 days old for 3PAO)
bash tools/run-fedramp-scan.sh --target $TARGET_DIR --output $OUTPUT_DIR

# Generate control matrix + POA&M
python3 tools/gap-analysis.py --scan-dir $OUTPUT_DIR --output $OUTPUT_DIR/

# Package evidence with SHA256 manifest
bash tools/package-evidence.sh --input $OUTPUT_DIR --output $OUTPUT_DIR/evidence-package/
```

---

## Step 2: Write the SSP

Copy and fill in the skeleton:

```bash
cp compliance-docs/ssp-skeleton.md $OUTPUT_DIR/SSP.md
```

**Key sections:**
- System description (what it does, who uses it, data types)
- Authorization boundary (what's in scope vs out of scope)
- Architecture diagram (network, data flow)
- Control implementation (one narrative per control family)

The control family narratives are pre-written templates in `compliance-docs/control-families/`. Copy and customize:

```bash
for f in compliance-docs/control-families/*.md; do
  cp "$f" $OUTPUT_DIR/control-narratives/
done
```

---

## Step 3: Complete the POA&M

```bash
cat $OUTPUT_DIR/poam.md
```

For each open finding:
- Set a target remediation date
- Assign an owner
- Note the risk level
- Track status (Open / In Progress / Closed)

---

## Step 4: Write the SAR

```bash
cp compliance-docs/sar-template.md $OUTPUT_DIR/SAR.md
```

Include: scan tool versions, scan dates, finding counts, control coverage percentage.

---

## Step 5: Set Up Continuous Compliance

### Every Commit (CI Pipeline)
- Gitleaks (secrets)
- Semgrep (SAST)
- Trivy (dependency CVEs)
- Checkov (IaC)

CI templates are in `ci-templates/`:
```bash
cp ci-templates/*.yml $TARGET_DIR/.github/workflows/
```

### Weekly (Scheduled Scan)
```bash
# Add to cron or GHA schedule
bash tools/run-fedramp-scan.sh --target $TARGET_DIR --output $OUTPUT_DIR --label weekly
```

### Monthly
- Generate compliance report
- Upload evidence to artifact storage

### Quarterly
- Account review (disable inactive users)
- POA&M status review
- Regenerate gap analysis

### Annually
- Incident response tabletop exercise
- Full 3PAO re-assessment

---

## Evidence Retention

| Evidence Type | Retention | Storage |
|--------------|-----------|---------|
| Scan results | 1 year | S3 Standard |
| Audit logs | 1-3 years | S3 IA → Glacier |
| POA&M history | 3 years | S3 Standard |
| Incident reports | 3 years | S3 Standard |

---

## What "Done" Looks Like

- [ ] SSP complete with all control narratives
- [ ] POA&M with owners and target dates for every open finding
- [ ] SAR with scan results < 30 days old
- [ ] Control matrix showing 80%+ MET/PARTIAL
- [ ] Evidence package with SHA256 manifest
- [ ] CI pipeline running compliance scans on every commit
- [ ] Weekly scheduled scan configured
- [ ] Quarterly review calendar set

The enterprise compliance tools (Drata, Vanta, Anecdotes) take over continuous monitoring from here. This package gives them a clean baseline and organized evidence.

---

## What's Next

All five MSSP packages are complete:
1. **01-application-hardening** — Code and infra secure in dev/staging
2. **02-platform-hardening** — Cluster hardened with admission control
3. **03-runtime-security** — Detection, monitoring, and response deployed
4. **04-cloud-security** — Cloud account hardened
5. **05-compliance-ready** — Evidence packaged for auditors
