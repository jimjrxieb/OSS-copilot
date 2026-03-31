# Playbook 01: Your First Scan

> Run all the scanners against your repo and see what they find.
>
> **Time:** ~15 minutes (install + scan + review)
> **Prerequisites:** Your repo cloned locally. That's it.

---

## Before You Start

You should have completed [00-understand-your-repo.md](00-understand-your-repo.md).
You know what languages your project uses and what directories to ignore. If you
skipped it, go back — it takes 5 minutes and saves you an hour of chasing false positives.

---

## Step 1: Install the Scanners

You don't need all of them. Install what applies to your project.

### Everyone needs these:

```bash
# Secret detection (every project has secrets risk)
brew install gitleaks
# Or: https://github.com/gitleaks/gitleaks/releases

# Dependency scanning (every project has dependencies)
brew install trivy
# Or: https://github.com/aquasecurity/trivy/releases
```

### If you write Python:

```bash
pip install semgrep   # SAST — finds code vulnerabilities
pip install bandit    # Python-specific security linting
```

### If you write JavaScript, Go, Java, Ruby, or anything else:

```bash
pip install semgrep   # Covers 30+ languages
```

### For a second opinion on dependencies:

```bash
brew install grype    # Different CVE database than Trivy
```

**Don't have brew?** Check each tool's GitHub releases page for direct downloads.
**On Linux?** Most tools have apt/yum packages or static binaries.

---

## Step 2: Run the Scanners

From the `01-code/` directory in this repo:

```bash
# Point all scanners at your project
TARGET=/path/to/your/project

# 1. Scan for hardcoded secrets (API keys, passwords, tokens)
./scan-secrets.sh "$TARGET"

# 2. Scan source code for security bugs
./scan-code.sh "$TARGET"

# 3. Scan dependencies for known CVEs
./scan-dependencies.sh "$TARGET"
```

Each script:
- Checks if the scanner is installed (tells you how to install if not)
- Runs the scan and saves JSON results
- Prints a summary count of findings

**Results land in:** `$TARGET/.oss-copilot/code/`

---

## Step 3: Look at the Results

### Quick overview — how bad is it?

```bash
cd /path/to/your/project/.oss-copilot/code/
ls -la *.json
```

You should see files like:
```
gitleaks-results.json        ← Secrets found in your code
semgrep-results.json         ← Code vulnerabilities
bandit-results.json          ← Python-specific issues
trivy-deps-results.json      ← Dependency CVEs
grype-results.json           ← More dependency CVEs
```

### Get the counts:

```bash
# How many secrets?
python3 -c "import json; data=json.load(open('gitleaks-results.json')); print(f'Secrets: {len(data) if isinstance(data, list) else 0}')" 2>/dev/null

# How many code vulnerabilities?
python3 -c "import json; data=json.load(open('semgrep-results.json')); print(f'Code findings: {len(data.get(\"results\", []))}')" 2>/dev/null

# How many dependency CVEs?
python3 -c "import json; data=json.load(open('trivy-deps-results.json')); total=sum(len(r.get('Vulnerabilities',[])) for r in data.get('Results',[])); print(f'Dependency CVEs (HIGH+CRITICAL): {total}')" 2>/dev/null
```

---

## Step 4: Don't Panic

Your first scan will probably find a lot of things. That's normal. Here's context:

| Finding Count | What It Means |
|--------------|---------------|
| **0 findings** | Either your code is very secure, or the scanner didn't have the right config. Double-check. |
| **1-20 findings** | Healthy. Fix secrets first, then CRITICAL CVEs, then the rest. |
| **20-100 findings** | Normal for a medium project that hasn't been scanned before. Most are LOW/MEDIUM. |
| **100+ findings** | Expected for large projects or repos that have never been scanned. Don't try to fix everything at once. |

**The priority is always the same:**
1. Hardcoded secrets (rotate immediately — someone might already have them)
2. CRITICAL CVEs in dependencies (known exploits exist)
3. HIGH code vulnerabilities (SQL injection, command injection)
4. Everything else (work through it over time)

---

## Step 5: Save Your Baseline

This first scan is your **baseline** — the "before" picture. You'll compare against
it later to measure progress.

```bash
# Create a snapshot of your scan results
BASELINE_DIR="/path/to/your/project/.oss-copilot/baseline-$(date +%Y%m%d)"
mkdir -p "$BASELINE_DIR"
cp /path/to/your/project/.oss-copilot/code/*.json "$BASELINE_DIR/"
echo "Baseline saved to $BASELINE_DIR"
```

---

## What Just Happened

You ran the same scanners that enterprise tools like Checkmarx ($50K/yr) and Snyk
($25K/yr) run under the hood. The difference is presentation — enterprise tools
have nicer dashboards, auto-fix PRs, and IDE integrations. But the core detection
is the same.

You now know:
- Whether you have hardcoded secrets (fix these today)
- Whether your dependencies have known vulnerabilities (fix CRITICAL ones this week)
- Whether your code has security bugs (prioritize HIGH severity)

---

## Next Steps

- Understand what the findings mean → [02-read-your-results.md](02-read-your-results.md)
- Already know what you're doing? Skip to CI → [03-add-to-ci.md](03-add-to-ci.md)
