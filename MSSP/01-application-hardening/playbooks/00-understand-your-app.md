# 00 — Understand Your App

> **Run this before any scanner. Always.**

You don't scan first and figure out what you scanned later. That's how you end up chasing 85 fake CVEs from Terraform provider binaries for two days.

This playbook profiles your repo so the scanners know what to scan and what to skip.

---

## What You Need

- Your project cloned into `Target-Projects/slot-1/`
- That's it. The script figures out the rest.

## Set Up Your Paths

Run these once per session. Every playbook in this package uses them.

```bash
# Where your project lives (the repo you're hardening)
export TARGET_DIR=../../Target-Projects/slot-1/<your-project>

# Where scan results go
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
```

---

## Step 1: Run Target Discovery

```bash
bash tools/understand-target.sh --target-dir $TARGET_DIR --output $OUTPUT_DIR
```

**What it does:**
1. Counts files by language (Python, JS, Go, etc.)
2. Finds build artifacts that shouldn't be scanned (.terraform/, node_modules/, vendor/)
3. Detects IaC frameworks (Terraform, CloudFormation, K8s manifests, Kustomize)
4. Checks for existing security configs (.hadolint.yaml, .bandit, etc.)
5. Picks the right scanners for your tech stack
6. Estimates scan size (total files vs scannable files)
7. Flags things that will cause false positives

**Output:** Three files in your output directory:
- `TARGET-PROFILE.md` — what the script found
- `.scanner-excludes` — directories to skip
- `.scanner-config.env` — scanner settings

---

## Step 2: Review the Profile

```bash
cat $OUTPUT_DIR/TARGET-PROFILE.md
```

**Check these things:**
- Does the language breakdown match what you expect?
- Did it find build artifacts that should be excluded?
- Are the right scanners selected for this stack?
- Do the false positive warnings make sense?

---

## Step 3: Review the Excludes

```bash
cat $OUTPUT_DIR/.scanner-excludes
```

Common things that should be excluded:
- `.terraform/` — compiled Go binaries, not your app code
- `node_modules/` — third-party code, scanned separately via lockfile
- `vendor/` — Go vendored dependencies
- `*.bak` — backup files from previous fixes

If something is missing, add it. If something shouldn't be excluded, remove it.

---

## Step 4: Run the Scanners

The excludes load automatically — no manual flags needed.

```bash
# Run everything (source + infrastructure scanners)
bash tools/run-all-scanners.sh --target-dir $TARGET_DIR

# Or run each group separately
bash tools/run-src-scanners.sh --target-dir $TARGET_DIR
bash tools/run-infra-scanners.sh --target-dir $TARGET_DIR
```

For monorepos, scope to specific directories:

```bash
bash tools/run-all-scanners.sh --target-dir $TARGET_DIR --include-dir src --include-dir infrastructure
```

---

## Why This Matters

Without this step, your scanners will:
- Flag Go binaries inside `.terraform/` as having CVEs (they're not your code)
- Scan `node_modules/` line-by-line instead of checking the lockfile
- Run Python scanners on a Go-only project
- Report findings in test fixtures as real vulnerabilities

This step takes 2 minutes and saves hours of false positive triage.

---

## Next Step

Go to [01-src-code-scan.md](01-src-code-scan.md) to scan your source code.
