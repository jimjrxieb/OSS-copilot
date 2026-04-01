# 01 — Source Code Scan

> Scan your source code for secrets, security bugs, vulnerable dependencies, and Dockerfile issues.

These are the same checks that enterprise tools like Checkmarx, Snyk, and GitGuardian run. We use open source tools that cover 80-90% of the same findings — for free.

In production, the enterprise tools take over. This is your staging version — get everything clean here first so the enterprise scanners have less noise to deal with.

---

## What You Need

- Playbook 00 completed (`.scanner-excludes` exists in your output directory)
- Your paths set:
  ```bash
  export TARGET_DIR=../../Target-Projects/slot-1/<your-project>
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

## The Scanners

| # | Scanner | What It Finds | What It Replaces in Prod |
|---|---------|---------------|--------------------------|
| 1 | **Gitleaks** | Hardcoded secrets, API keys, tokens | GitGuardian |
| 2 | **Bandit** | Python security issues (SAST) | Checkmarx, Fortify |
| 3 | **Semgrep** | Multi-language SAST (Python, JS, Go, Terraform) | Checkmarx, SonarQube |
| 4 | **Trivy-fs** | Dependency CVEs from lockfiles | Snyk SCA |
| 5 | **Grype** | CVE cross-check (second opinion on deps) | Mend/WhiteSource |
| 6 | **Hadolint** | Dockerfile best practices | Aqua Scanner |

Missing a scanner? It gets skipped automatically — you don't need all of them to start.

---

## Step 1: Run the Scan

```bash
bash tools/run-src-scanners.sh --target-dir $TARGET_DIR
```

**What happens:**
- Runs all 6 scanners one at a time
- Loads your `.scanner-excludes` automatically
- Drops JSON output per scanner into `$OUTPUT_DIR/`
- Skips any scanner that isn't installed

**Useful options:**
```bash
# Skip a scanner that doesn't apply
--skip-scanner bandit    # no Python in this repo

# Scope to specific directories in a monorepo
--include-dir src --include-dir services

# Run scanners in parallel (faster, noisier terminal)
--parallel
```

---

## Step 2: Triage the Findings

```bash
python3 tools/triage.py --scan-dir $OUTPUT_DIR --project <your-project-name>
```

This reads all the scanner JSON and produces `REMEDIATION-PLAN.md`:
- Findings grouped by severity (CRITICAL > HIGH > MEDIUM > LOW)
- Which findings can be auto-fixed
- Which findings need manual review
- Deduplication (same file flagged by multiple scanners counted once)

---

## Step 3: Review the Output

```bash
cat $OUTPUT_DIR/REMEDIATION-PLAN.md
cat $OUTPUT_DIR/SUMMARY.md
```

**Separate what's real from what's noise:**
- **Your code** (api/, services/, src/, lib/) — real findings, these matter
- **Vendor files** (node_modules/, vendor/) — should have been excluded by playbook 00
- **Test fixtures** — fake secrets in test files are expected, suppress them

---

## What You Get

| File | What It Is |
|------|-----------|
| `gitleaks.json` | Raw secret detection results |
| `bandit.json` | Raw Python SAST results |
| `semgrep.json` | Raw multi-language SAST results |
| `trivy-fs.json` | Raw dependency CVE results |
| `grype.json` | Raw CVE cross-check results |
| `hadolint-*.json` | Raw Dockerfile lint results |
| `SUMMARY.md` | Finding counts by scanner |
| `REMEDIATION-PLAN.md` | Prioritized fix list (from triage.py) |

All output is JSON and Markdown — no proprietary formats. These feed directly into the enterprise tools when they take over in production.

---

## Next Steps

- Run infrastructure scanners too? > [02-infra-scan.md](02-infra-scan.md)
- Ready to auto-fix? > [03-auto-fix.md](03-auto-fix.md)
- Run both source + infra at once: `bash tools/run-all-scanners.sh --target-dir $TARGET_DIR`
