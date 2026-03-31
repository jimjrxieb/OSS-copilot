# Playbook 05: Continuous Compliance

> Schedule recurring scans, track posture over time, and keep evidence fresh.
> This is the difference between "we scanned once" and "we monitor continuously."
>
> **Time:** ~10 minutes to set up
> **Prerequisites:** Completed playbooks 01-04

---

## Why Continuous Matters

A point-in-time scan proves you were compliant on March 31st. Continuous
monitoring proves you stayed compliant through April, May, June. SOC 2
Type II and FedRAMP specifically require continuous monitoring evidence.

Even if you're not under a formal compliance framework, monthly rescans
catch drift — new CVEs, new misconfigurations, developers bypassing
controls.

---

## Step 1: Schedule Weekly Scans

### GitHub Actions (if your code is on GitHub):

```yaml
# .github/workflows/compliance-scan.yml
name: Weekly Compliance Scan

on:
  schedule:
    - cron: '0 3 * * 1'  # Monday 3am UTC

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install scanners
        run: |
          pip install semgrep
          brew install trivy gitleaks

      - name: Run scans
        run: |
          semgrep scan --config=auto --json --output semgrep-results.json . || true
          trivy fs --format json --output trivy-results.json --severity HIGH,CRITICAL . || true
          gitleaks detect --source . --report-path gitleaks-results.json --report-format json || true

      - name: Upload evidence
        uses: actions/upload-artifact@v4
        with:
          name: compliance-evidence-${{ github.run_id }}
          path: |
            semgrep-results.json
            trivy-results.json
            gitleaks-results.json
          retention-days: 90
```

### Cron (if you run scans locally or on a server):

```bash
# Add to crontab: weekly scan on Monday at 3am
0 3 * * 1 cd /path/to/project && \
    bash /path/to/MSSP/01-code/scan-code.sh . --output /path/to/evidence/weekly-$(date +\%Y\%m\%d) && \
    bash /path/to/MSSP/01-code/scan-secrets.sh . --output /path/to/evidence/weekly-$(date +\%Y\%m\%d) && \
    bash /path/to/MSSP/01-code/scan-dependencies.sh . --output /path/to/evidence/weekly-$(date +\%Y\%m\%d)
```

---

## Step 2: Track Posture Over Time

Build a monthly trend:

```markdown
# Compliance Posture Trend — [Project Name]

| Date | Secrets | CRITICAL CVEs | HIGH CVEs | Checkov FAIL | Polaris Score | Controls MET |
|------|---------|--------------|-----------|-------------|---------------|-------------|
| Mar 15 | 7 | 7 | 32 | 16 | 62/100 | 8/15 |
| Mar 22 | 0 | 0 | 4 | 16 | 82/100 | 12/15 |
| Mar 31 | 0 | 0 | 0 | 10 | 100/100 | 14/15 |
| Apr 7 | 0 | 0 | 2 | 10 | 100/100 | 14/15 |
```

**That trend line is your compliance story.** It shows continuous improvement,
not just a one-time effort. Auditors love trend lines.

---

## Step 3: Monthly Compliance Review

Every 30 days, spend 30 minutes:

```
1. Rescan all layers (01-code, 02-cluster, 03-container, 04-cloud)
2. Re-run control mapping (05-compliance/map-nist.sh)
3. Update the control matrix (MET/PARTIAL/MISSING)
4. Review the POA&M (close fixed items, add new findings)
5. Update the trend table
6. Re-package evidence if auditor needs fresh reports
```

---

## Step 4: Alert on Regressions

Set up notifications for when posture degrades:

```bash
# Simple regression check — compare this week to last week
THIS_WEEK=$(python3 -c "import json; d=json.load(open('evidence/weekly-$(date +%Y%m%d)/trivy-results.json')); print(sum(len(r.get('Vulnerabilities',[])) for r in d.get('Results',[])))" 2>/dev/null || echo 0)
LAST_WEEK=$(python3 -c "import json; d=json.load(open('evidence/weekly-LASTWEEK/trivy-results.json')); print(sum(len(r.get('Vulnerabilities',[])) for r in d.get('Results',[])))" 2>/dev/null || echo 0)

if [ "$THIS_WEEK" -gt "$LAST_WEEK" ]; then
    echo "REGRESSION: CVEs increased from $LAST_WEEK to $THIS_WEEK"
    # Send Slack/email notification
fi
```

---

## Step 5: Evidence Retention

| Framework | Minimum Retention | Recommendation |
|-----------|------------------|----------------|
| SOC 2 | 1 year | 2 years |
| FedRAMP | 3 years | 3 years |
| HIPAA | 6 years | 6 years |
| PCI DSS | 1 year | 2 years |
| ISO 27001 | 3 years | 3 years |

```bash
# Archive monthly evidence to long-term storage
aws s3 cp evidence-20260331.tar.gz s3://compliance-evidence/2026/03/ \
    --storage-class GLACIER_IR
```

---

## What This Gives You vs. Drata/Vanta

| Capability | Your Setup (Free) | Drata/Vanta |
|-----------|-------------------|-------------|
| Weekly automated scans | Cron + CI pipeline | Built-in |
| Monthly trend tracking | Manual markdown table | Automatic dashboard |
| Evidence freshness alerts | Script-based | Automatic |
| Auditor access | ZIP files, shared drive | Self-service portal |
| Multi-framework mapping | One framework at a time | Simultaneous |
| Control assignment | Manual in POA&M | Workflow with owners |

**This is where the enterprise gap is real.** For SOC 2 Type II or FedRAMP
continuous monitoring, Drata saves hundreds of hours per year. But for
proving basic hygiene, passing a Type I audit, or internal assessments —
this approach works.

Open source handles the scanning and evidence. Enterprise tools handle the
lifecycle and presentation. Run both when the audit demands it.

---

## You Completed All 5 Layers

If you followed all the playbooks across all 5 C's:

| Layer | What You Built | Time Saved for Enterprise Tools |
|-------|---------------|-------------------------------|
| 01-Code | Scanned code, fixed dependencies, deployed CI gates | Weeks of triage on routine findings |
| 02-Cluster | Audited K8s, deployed admission control, hardened RBAC | Months of misconfiguration cleanup |
| 03-Container | Scanned images, hardened Dockerfiles, deployed Falco | Days of image CVE chasing |
| 04-Cloud | Scanned AWS, hardened IAM, enabled detection | Weeks of cloud posture assessment |
| 05-Compliance | Mapped to controls, packaged evidence, built POA&M | Days of evidence gathering per audit |

**The enterprise tools now scan a clean environment.** Their findings are all
signal — attack paths, cross-domain risks, data classification, behavioral
analysis. That's what they're built for. You took the load off.
