# 08 — Add Pre-Commit Hooks

> Install pre-commit hooks so findings are caught before they leave your machine.

CI catches findings on PRs. Pre-commit catches them on `git commit` — before they even leave the developer's machine. This is the fastest feedback loop.

---

## Step 1: Choose Your Config

| Config | What It Runs | Speed | Best For |
|--------|-------------|-------|----------|
| **Full** (`.pre-commit-config.yaml`) | Gitleaks, Semgrep, Hadolint, Conftest, Bandit | ~10 sec | Default |
| **Minimal** (`minimal.yaml`) | Gitleaks + trailing whitespace | ~3 sec | Large repos, impatient devs |
| **Python** (`python.yaml`) | Gitleaks, Bandit, Semgrep (Python) | ~8 sec | Python projects |
| **JavaScript** (`javascript.yaml`) | Gitleaks, Semgrep (JS) | ~8 sec | Node.js projects |
| **Go** (`go.yaml`) | Gitleaks, Semgrep (Go) | ~8 sec | Go projects |

---

## Step 2: Install

### Option A: Use the install script

```bash
cd $TARGET_DIR

# Full config (default)
bash ../../MSSP/01-application-hardening/templates/pre-commit/install.sh

# Specific config
bash ../../MSSP/01-application-hardening/templates/pre-commit/install.sh --config minimal
bash ../../MSSP/01-application-hardening/templates/pre-commit/install.sh --config python
```

### Option B: Manual install

```bash
cd $TARGET_DIR

# Install pre-commit
pip install pre-commit

# Copy the config
cp ../../MSSP/01-application-hardening/templates/pre-commit/.pre-commit-config.yaml .

# Install the hooks
pre-commit install

# Test (first run downloads hooks — takes ~30 sec)
pre-commit run --all-files
```

---

## Step 3: Test It

**Passing commit:**
```
$ git commit -m "Add feature"
Gitleaks................................................Passed
Semgrep (security)......................................Passed
Hadolint................................................Passed
[main abc123] Add feature
```

**Blocked commit:**
```
$ git commit -m "Add config"
Gitleaks................................................Failed
--- Finding ---
  RuleID: aws-access-token
  File:   config.py, line 42
  Secret: AKIA...

Action: Remove the secret, add to .env, re-commit.
```

---

## The "--no-verify" Problem

Developers can bypass hooks with `git commit --no-verify`. That's OK — the defense is layered:

1. **Pre-commit hooks** — catches 90% (this playbook)
2. **CI pipeline** — catches what slips past (playbook 06)
3. **Branch protection** — makes CI mandatory (can't merge without passing)

If someone uses `--no-verify`, CI still blocks the PR. The hook is a convenience, not the only gate.

---

## Step 4: Commit

```bash
git add .pre-commit-config.yaml
git commit -m "ci: add pre-commit security hooks"
```

---

## Updating Hooks

```bash
pre-commit autoupdate
pre-commit run --all-files
git add .pre-commit-config.yaml
git commit -m "ci: update pre-commit hook versions"
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `pre-commit: command not found` | `pip install pre-commit` or `brew install pre-commit` |
| Hook takes >30 sec | Switch to minimal config |
| Hook fails on files you didn't change | First run scans all staged files. Run `pre-commit run --all-files` once to baseline. |

---

## Next Step

Go to [09-harden-cicd.md](09-harden-cicd.md) to harden the CI/CD pipeline itself.
