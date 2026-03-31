# Playbook 03: Add Scanning to CI

> Make GitHub Actions scan every pull request automatically. No more "I forgot to scan."
>
> **Time:** ~10 minutes
> **Prerequisites:** A GitHub repository with Actions enabled

---

## Why CI Scanning Matters

Running scanners manually is a start. But people forget. People skip.
People push to main at 11pm on a Friday and don't scan first.

CI scanning means every pull request gets scanned automatically. If a secret
gets committed, the PR fails. If a CRITICAL CVE gets introduced, the PR fails.
No human has to remember to run anything.

This is the difference between "we scan sometimes" and "we scan always."

---

## Step 1: Choose What to Scan

Start small. You can always add more scanners later.

| Level | Scanners | Run Time | Good For |
|-------|----------|----------|----------|
| **Starter** | Gitleaks (secrets only) | ~30 sec | Just getting started |
| **Standard** | Gitleaks + Trivy + Semgrep | ~3 min | Most teams |
| **Comprehensive** | All of the above + Bandit + Grype | ~5 min | Security-conscious teams |

**Recommendation:** Start with Standard. Add more later if needed.

---

## Step 2: Create the Workflow

```bash
cd /path/to/your/project
mkdir -p .github/workflows
```

Create `.github/workflows/security.yml`:

```yaml
name: Security Scan

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  schedule:
    - cron: '0 2 * * 1'  # Weekly Monday 2am UTC — catches new CVEs

permissions:
  contents: read

jobs:
  secrets:
    name: Secret Detection
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for git secret scanning

      - name: Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  sast:
    name: Code Security (SAST)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Semgrep
        uses: semgrep/semgrep-action@v1
        with:
          config: auto
        env:
          SEMGREP_RULES: p/security-audit p/owasp-top-ten

  dependencies:
    name: Dependency CVEs
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Trivy
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          scan-ref: .
          severity: CRITICAL,HIGH
          exit-code: 1  # Fail the job on CRITICAL/HIGH CVEs
```

**What this does:**
- `secrets` job: Scans for API keys, passwords, tokens. **Blocks the PR** if any are found.
- `sast` job: Scans code for vulnerabilities (SQLi, XSS, injection). Reports findings.
- `dependencies` job: Scans for known CVEs. **Blocks the PR** on CRITICAL/HIGH.

All three jobs run in parallel — total time is ~2-3 minutes.

---

## Step 3: What Blocks vs. What Warns

You need to decide: should a finding **block the merge** or just **warn**?

```yaml
# BLOCKS the PR (exit-code: 1)
# Use for: secrets, CRITICAL CVEs
exit-code: 1

# WARNS only (exit-code: 0)
# Use for: MEDIUM findings, advisory scanners
exit-code: 0
```

**Recommended setup:**

| Scanner | Blocks PR | Warns Only |
|---------|-----------|------------|
| Gitleaks | Any secret found | — |
| Trivy | CRITICAL + HIGH CVEs | MEDIUM + LOW |
| Semgrep | ERROR severity | WARNING severity |

Start with blocking on secrets and CRITICAL CVEs only. You can tighten the
gates later as your team gets used to fixing findings.

---

## Step 4: Set Up Branch Protection

The workflow is useless if developers can merge without it passing.

```
GitHub → Your repo → Settings → Branches → Branch protection rules → Add rule

Branch name pattern: main

Check these boxes:
  [x] Require a pull request before merging
  [x] Require status checks to pass before merging
      Required checks: (search for these after your first PR runs)
        - Secret Detection
        - Dependency CVEs
  [x] Require branches to be up to date before merging
```

Now nobody can merge to main without passing the security scans. Including you.

---

## Step 5: Test It

```bash
# Create a test branch
git checkout -b test/security-pipeline

# Add the workflow
git add .github/workflows/security.yml
git commit -m "ci: add security scanning pipeline"
git push -u origin test/security-pipeline

# Create a PR
gh pr create --title "Add security scanning" --body "Testing security pipeline"
```

Watch the Actions tab. You should see three jobs run:
- Secret Detection
- Code Security (SAST)
- Dependency CVEs

---

## Step 6: Verify It Actually Blocks

Test that the gates work by intentionally introducing a finding:

```bash
# Create a file with a fake AWS key
echo 'AWS_KEY = "AKIAIOSFODNN7EXAMPLE"' > test_secret.py
git add test_secret.py
git commit -m "test: verify secret detection blocks"
git push
```

The PR should show a failed check from Gitleaks. That's the gate working.

```bash
# Clean up after testing
git rm test_secret.py
git commit -m "test: remove test secret"
git push
```

---

## Step 7: Commit and Merge

Once the pipeline passes on itself:

```bash
git checkout main
git merge test/security-pipeline
git push
```

From now on, every PR gets scanned automatically.

---

## Adding More Scanners Later

When you're ready to expand coverage, add these jobs to the same workflow:

```yaml
  # Python-specific (add if you have Python code)
  python-sast:
    name: Python Security
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install bandit
      - run: bandit -r . -f json -o bandit-results.json --exit-zero
      - name: Check for HIGH findings
        run: |
          HIGH=$(python3 -c "import json; data=json.load(open('bandit-results.json')); print(len([r for r in data.get('results',[]) if r.get('issue_severity')=='HIGH']))")
          echo "HIGH findings: $HIGH"
          [ "$HIGH" -gt 0 ] && exit 1 || exit 0
```

---

## Nightly Scans

The `schedule` trigger in the workflow runs weekly by default. For daily scans:

```yaml
schedule:
  - cron: '0 2 * * *'  # Every night at 2am UTC
```

This catches new CVEs disclosed overnight — even if no code changed, a new
vulnerability might affect your existing dependencies.

---

## Next Steps

- Add pre-commit hooks for instant feedback → [04-pre-commit-hooks.md](04-pre-commit-hooks.md)
- Already fixing things? Track your progress → [05-track-progress.md](05-track-progress.md)
