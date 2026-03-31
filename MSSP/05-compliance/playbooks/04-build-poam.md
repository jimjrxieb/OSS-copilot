# Playbook 04: Build a POA&M

> Plan of Action and Milestones — the document that tracks every open
> finding with a remediation plan and target date.
>
> **Time:** ~10 minutes
> **Prerequisites:** Gap analysis from [02-gap-analysis.md](02-gap-analysis.md)

---

## What a POA&M Is

A POA&M (Plan of Action and Milestones) is a tracking document for every
open finding. It tells auditors: "we know about this, here's the plan to
fix it, here's when it will be done."

Not having a POA&M is worse than having one full of findings. A POA&M with
50 items shows process. No POA&M shows nothing.

---

## Step 1: Create Your POA&M from Scan Results

```markdown
# Plan of Action & Milestones — [Project Name]
Date: [Today]
Next review: [30 days from now]

| ID | Control | Finding | Severity | Target Date | Owner | Status |
|----|---------|---------|----------|-------------|-------|--------|
| POA-001 | RA-5 | 4 HIGH CVEs in tar@7.5.6 | High | [+7 days] | Dev team | OPEN |
| POA-002 | CM-6 | 6 Checkov findings (namespace defaults) | Medium | [+14 days] | Platform | OPEN |
| POA-003 | CM-6 | 3 images missing digest pinning (CKV_K8S_43) | Medium | [+30 days] | Dev team | OPEN |
| POA-004 | AC-6 | 3 containers missing high UID (CKV_K8S_40) | Low | [+30 days] | Platform | OPEN |
| POA-005 | IA-5 | 2 generic API keys need review | Medium | [+7 days] | Security | OPEN |
```

---

## Step 2: Fill In Details for Each Finding

For each POA&M item, document:

```markdown
### POA-001: HIGH CVEs in tar package

**Control:** RA-5 (Vulnerability Monitoring and Scanning)
**Source:** Trivy dependency scan (2026-03-30)
**Finding:** tar@7.5.6 has 3 known CVEs (CVE-2026-24842, CVE-2026-26960, CVE-2026-29786)
**Fix:** `npm update tar` (patches to 7.5.10)
**Risk if not fixed:** Known exploit paths for file extraction vulnerabilities
**Target date:** 2026-04-07
**Owner:** Development team
**Status:** OPEN

**Milestones:**
- [ ] Run npm update tar in dev environment
- [ ] Verify fix with trivy fs rescan
- [ ] Merge to main, deploy to staging
- [ ] Rescan staging environment
- [ ] Close POA&M item with before/after evidence
```

---

## Step 3: Categorize by Priority

| Priority | Criteria | Target Date | Example |
|----------|---------|-------------|---------|
| **P1 — Critical** | Active exploit, data exposure risk | 7 days | Exposed secrets, CRITICAL CVEs |
| **P2 — High** | Known vulnerability, no active exploit | 14 days | HIGH CVEs, privileged containers |
| **P3 — Medium** | Misconfiguration, defense-in-depth gap | 30 days | Missing image digests, namespace defaults |
| **P4 — Low** | Best practice, hardening polish | 90 days | High UIDs, secrets as files vs env vars |

---

## Step 4: Track Remediation

Update the POA&M as items get fixed:

```markdown
| ID | Control | Finding | Severity | Target Date | Owner | Status |
|----|---------|---------|----------|-------------|-------|--------|
| POA-001 | RA-5 | 4 HIGH CVEs in tar@7.5.6 | High | 2026-04-07 | Dev team | **CLOSED** |
| POA-002 | CM-6 | 6 Checkov namespace findings | Medium | 2026-04-14 | Platform | IN-PROGRESS |
| POA-003 | CM-6 | 3 images missing digest | Medium | 2026-04-30 | Dev team | OPEN |
```

When closing an item, attach the evidence:
```markdown
**POA-001 — CLOSED (2026-04-05)**
Evidence: trivy-deps-results-postfix.json shows 0 HIGH CVEs.
Before: 4 HIGH CVEs. After: 0.
Commit: abc123 ("fix: update tar to 7.5.10")
```

---

## Step 5: Monthly POA&M Review

Every 30 days:

1. Review all OPEN items — are target dates on track?
2. Rescan to check if new findings appeared
3. Add new items for any new findings
4. Close items with evidence
5. Update the "Next review" date

This monthly cadence is what compliance frameworks call "continuous monitoring."
It's not real-time (that's Drata's job), but it proves ongoing attention.

---

## Next Steps

- Set up recurring scans → [05-continuous-compliance.md](05-continuous-compliance.md)
- Back to overview → [../README.md](../README.md)
