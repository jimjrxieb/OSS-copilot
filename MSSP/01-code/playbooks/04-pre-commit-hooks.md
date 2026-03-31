# Playbook 04: Pre-Commit Hooks

> Catch secrets and bugs before they ever leave your machine.
>
> **Time:** ~5 minutes
> **Prerequisites:** Python installed (`pip` available)

---

## Why Pre-Commit Hooks?

CI scanning catches issues when you push. Pre-commit hooks catch issues when you
commit — before the code ever leaves your machine. You get feedback in 3 seconds
instead of 3 minutes.

**The three-layer defense:**

```
Layer 1: Pre-commit hooks    → catches on your machine (3 seconds)
Layer 2: CI pipeline          → catches on push/PR (3 minutes)
Layer 3: Branch protection    → prevents merge without passing CI
```

Pre-commit hooks are Layer 1 — the fastest feedback loop. If you accidentally
hardcode an API key, you find out immediately, not after it's pushed to GitHub
where anyone with repo access can see it.

---

## Step 1: Install pre-commit

```bash
pip install pre-commit
```

That's it. One command.

---

## Step 2: Create the Config

In your project root, create `.pre-commit-config.yaml`:

```yaml
repos:
  # Secret detection — catches API keys, passwords, tokens
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks

  # Multi-language SAST — catches code vulnerabilities
  - repo: https://github.com/semgrep/semgrep
    rev: v1.67.0
    hooks:
      - id: semgrep
        args: ['--config', 'auto', '--error']
```

### Language-specific additions:

**Python projects** — add Bandit:
```yaml
  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.8
    hooks:
      - id: bandit
        args: ['-ll']  # Only HIGH and MEDIUM severity
```

**Projects with Dockerfiles** — add Hadolint:
```yaml
  - repo: https://github.com/hadolint/hadolint
    rev: v2.12.0
    hooks:
      - id: hadolint
```

### Minimal config (for large repos or impatient teams):

If the full config is too slow (>10 seconds per commit), use this instead:

```yaml
repos:
  # Just secret detection — fast, catches the worst issues
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

---

## Step 3: Install the Hooks

```bash
cd /path/to/your/project
pre-commit install
```

Done. Hooks now run automatically on every `git commit`.

### First run — test it:

```bash
# Run against all current files (first run downloads hooks — takes ~30 seconds)
pre-commit run --all-files
```

This scans everything. After this, hooks only scan files you changed in each commit.

---

## Step 4: See It in Action

### A clean commit:

```
$ git commit -m "Add new feature"
gitleaks................................................................Passed
semgrep.................................................................Passed
[main abc1234] Add new feature
 2 files changed, 45 insertions(+)
```

### A blocked commit:

```
$ git commit -m "Add config"
gitleaks................................................................Failed
- hook id: gitleaks
- exit code: 1

Finding:
  RuleID: aws-access-token
  File: config.py
  Line: 12
  Secret: AKIA...

Fix: Remove the secret, use an environment variable instead, then re-commit.
```

The commit is **rejected**. The secret never enters git history. This is exactly
what you want.

---

## Step 5: The "--no-verify" Problem

Developers can bypass hooks with `git commit --no-verify`. You can't prevent this
locally. But that's OK — this is why you have three layers:

1. Pre-commit hooks catch it on commit (most developers use them)
2. CI pipeline catches it on push (can't be bypassed)
3. Branch protection prevents merge without CI passing (the hard gate)

**Don't fight developers on `--no-verify`.** Instead, make sure CI catches
everything they skip. The hook is a convenience, not the only gate.

---

## Step 6: Commit the Config

The config file should be in your repo so every developer gets the same hooks:

```bash
git add .pre-commit-config.yaml
git commit -m "ci: add pre-commit security hooks"
```

### Team onboarding:

Add this to your README or onboarding docs:

```markdown
## Setup

1. Clone the repo
2. Run: `pip install pre-commit && pre-commit install`
3. Done — security hooks run automatically on every commit
```

---

## Keeping Hooks Updated

Hook versions get outdated. Update quarterly:

```bash
pre-commit autoupdate        # Updates all hook versions
pre-commit run --all-files   # Verify nothing breaks
git add .pre-commit-config.yaml
git commit -m "ci: update pre-commit hook versions"
```

---

## Troubleshooting

**"pre-commit: command not found"**
```bash
pip install pre-commit
# Or: brew install pre-commit
```

**Hooks take too long (>15 seconds)**
- Use the minimal config (Gitleaks only)
- Add large directories to the exclude list in `.pre-commit-config.yaml`:
```yaml
exclude: 'node_modules|vendor|\.terraform'
```

**"Hook fails on files I didn't change"**
- Run `pre-commit run --all-files` once to clear the backlog
- After that, hooks only run on staged files

---

## Next Steps

- Track your improvement over time → [05-track-progress.md](05-track-progress.md)
- Back to the overview → [../README.md](../README.md)
