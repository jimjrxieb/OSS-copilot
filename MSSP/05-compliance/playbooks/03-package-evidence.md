# Playbook 03: Package Evidence

> Bundle your scan results, control matrix, and gap analysis into
> something an auditor can actually use.
>
> **Time:** ~10 minutes
> **Prerequisites:** Scan results from layers 01-04

---

## What Auditors Want

Auditors don't want to run tools. They want organized evidence that proves
each control is implemented. They want:

1. **Scan reports** — proof that scanning happened (RA-5)
2. **Control matrix** — which controls are met/partial/missing
3. **POA&M** — what's open, when it will be fixed
4. **Before/after comparisons** — proof of remediation (SI-2)
5. **Timestamps** — evidence must be recent (<30 days for most frameworks)

---

## Step 1: Run the Evidence Packager

```bash
cd MSSP/05-compliance

# Package all scan results
./package-evidence.sh
```

Or manually:

```bash
EVIDENCE_DIR="/path/to/scan-results"
PACKAGE="evidence-$(date +%Y%m%d)"
mkdir -p "$PACKAGE"

# 1. Scan reports (raw JSON)
mkdir -p "$PACKAGE/01-scan-reports"
cp "$EVIDENCE_DIR"/01-code/*.json "$PACKAGE/01-scan-reports/" 2>/dev/null
cp "$EVIDENCE_DIR"/02-cluster/*.json "$PACKAGE/01-scan-reports/" 2>/dev/null

# 2. Control mapping
mkdir -p "$PACKAGE/02-control-mapping"
cp "$EVIDENCE_DIR"/.oss-copilot/compliance/*.json "$PACKAGE/02-control-mapping/" 2>/dev/null
cp "$EVIDENCE_DIR"/.oss-copilot/compliance/*.txt "$PACKAGE/02-control-mapping/" 2>/dev/null

# 3. Gap analysis (your control matrix from Playbook 02)
mkdir -p "$PACKAGE/03-gap-analysis"
# Copy your control-matrix.md here

# 4. POA&M (from Playbook 04)
mkdir -p "$PACKAGE/04-poam"
# Copy your poam.md here

# 5. Generate manifest with checksums
echo "# Evidence Package Manifest" > "$PACKAGE/MANIFEST.md"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PACKAGE/MANIFEST.md"
echo "" >> "$PACKAGE/MANIFEST.md"
find "$PACKAGE" -type f -not -name "MANIFEST.md" | sort | while read f; do
    SHA=$(sha256sum "$f" | cut -d' ' -f1)
    echo "- \`$f\` — $SHA" >> "$PACKAGE/MANIFEST.md"
done

# 6. Create the archive
tar -czf "${PACKAGE}.tar.gz" "$PACKAGE/"
echo "Evidence package: ${PACKAGE}.tar.gz"
```

---

## Step 2: What the Package Should Contain

```
evidence-20260331/
├── MANIFEST.md                ← SHA256 of every file (integrity proof)
├── 01-scan-reports/
│   ├── gitleaks-results.json  ← Secret detection (IA-5)
│   ├── semgrep-results.json   ← SAST findings (SA-11)
│   ├── trivy-deps-results.json← Dependency CVEs (RA-5)
│   ├── grype-results.json     ← Dependency CVEs (RA-5, second scanner)
│   ├── checkov-results.json   ← K8s/IaC misconfigs (CM-6)
│   ├── polaris-static.json    ← K8s best practices (CM-6)
│   └── conftest-results.json  ← OPA policy enforcement (SC-7)
├── 02-control-mapping/
│   ├── nist-800-53-mapping.json  ← Findings mapped to controls
│   └── nist-800-53-summary.txt   ← Human-readable summary
├── 03-gap-analysis/
│   └── control-matrix.md         ← MET/PARTIAL/MISSING per control
├── 04-poam/
│   └── poam.md                   ← Open findings with target dates
└── 05-executive-summary/
    └── summary.md                ← High-level posture overview
```

---

## Step 3: Write the Executive Summary

Every evidence package needs a one-page summary:

```markdown
# Security Posture Assessment — [Project Name]
Date: [Today]
Assessor: [Your name/org]

## Scope
- Application: [description]
- Infrastructure: [AWS/K8s/etc]
- Framework: NIST 800-53 Rev 5 (Moderate)

## Tools Used
| Tool | Purpose | Controls Covered |
|------|---------|-----------------|
| Trivy + Grype | Dependency CVE scanning | RA-5, SI-2 |
| Semgrep | Static code analysis | SA-11, SI-2 |
| Gitleaks | Secret detection | IA-5 |
| Checkov + Polaris | K8s/IaC configuration audit | CM-6, CM-7 |
| Conftest | OPA policy enforcement | SC-7, AC-6 |

## Summary
- Controls assessed: [X]
- Controls MET: [X]
- Controls PARTIAL: [X]
- Controls MISSING: [X]
- Open findings in POA&M: [X]

## Key Findings
1. [Most important finding]
2. [Second most important]
3. [Third]

## Recommendation
[One paragraph: current posture, what was fixed, what remains,
what enterprise tooling would add for continuous monitoring]
```

---

## Step 4: Verify Evidence Freshness

Auditors check timestamps. Evidence older than 30 days is stale.

```bash
# Check when scan files were created
find "$PACKAGE" -name "*.json" -exec stat --format='%Y %n' {} \; | \
    python3 -c "
import sys, time
now = time.time()
for line in sys.stdin:
    ts, path = line.strip().split(' ', 1)
    age_days = (now - int(ts)) / 86400
    status = 'FRESH' if age_days < 30 else 'STALE'
    print(f'  [{status}] {path} ({age_days:.0f} days old)')
"
```

**If any evidence is stale:** Re-run the relevant scanner before packaging.

---

## Next Steps

- Build a POA&M for open findings → [04-build-poam.md](04-build-poam.md)
- Set up continuous compliance → [05-continuous-compliance.md](05-continuous-compliance.md)
