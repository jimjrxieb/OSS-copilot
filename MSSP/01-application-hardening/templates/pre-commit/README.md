# Pre-Commit Hooks

> Catch security issues before they're committed - the ultimate shift-left.

---

## Why Pre-Commit Hooks?

Pre-commit hooks run on your local machine **before** code reaches CI/CD:

- ⚡ **Instant feedback** - Catch issues in seconds, not minutes
- 💰 **Save CI costs** - Don't waste CI minutes on obvious issues
- 🚫 **Block secrets** - Prevent credentials from ever reaching Git
- 🎯 **Better DX** - Fix issues while context is fresh

---

## Quick Start

### 1. Install pre-commit framework

```bash
# Using pip
pip install pre-commit

# Using Homebrew (Mac)
brew install pre-commit

# Using apt (Linux)
sudo apt install pre-commit
```

### 2. Copy a config to your repo

```bash
# Full config (recommended)
cp 03-templates/pre-commit/.pre-commit-config.yaml /path/to/your/repo/

# Or minimal config (secrets + SAST only)
cp 03-templates/pre-commit/minimal.yaml /path/to/your/repo/.pre-commit-config.yaml
```

### 3. Install hooks

```bash
cd /path/to/your/repo
pre-commit install
```

### 4. Test hooks

```bash
# Test on all files
pre-commit run --all-files

# Test on staged files only
pre-commit run
```

---

## Available Configurations

### Full Configuration (.pre-commit-config.yaml)

**Scanners:** Gitleaks, Semgrep, Hadolint, Conftest, YAML lint, Markdown lint

**When to use:** Production repositories, high-security requirements

**Speed:** ~30-60 seconds per commit

```bash
cp 03-templates/pre-commit/.pre-commit-config.yaml .pre-commit-config.yaml
```

---

### Minimal Configuration (minimal.yaml)

**Scanners:** Gitleaks, basic linters

**When to use:** Getting started, fast iteration

**Speed:** ~10-20 seconds per commit

```bash
cp 03-templates/pre-commit/minimal.yaml .pre-commit-config.yaml
```

---

### Language-Specific Configurations

**Python:** `python.yaml` - Black, isort, flake8, Bandit

**JavaScript:** `javascript.yaml` - ESLint, Prettier, npm audit

**Go:** `go.yaml` - gofmt, golangci-lint, gosec

```bash
cp 03-templates/pre-commit/python.yaml .pre-commit-config.yaml
```

---

## What Happens When You Commit

### Success Case

```bash
$ git commit -m "Add feature"

[INFO] Initializing environment for https://github.com/gitleaks/gitleaks
[INFO] Installing environment for https://github.com/gitleaks/gitleaks
Gitleaks................................................Passed
Semgrep (security)......................................Passed
Hadolint (Dockerfile)...................................Passed
Check YAML..............................................Passed
Check JSON..............................................Passed

[main abc123] Add feature
 3 files changed, 42 insertions(+), 5 deletions(-)
```

### Failure Case (Secret Detected)

```bash
$ git commit -m "Add config"

Gitleaks................................................Failed
- hook id: gitleaks
- exit code: 1

Finding:     AWS Access Key ID
File:        config.py:42
Line:        AWS_KEY = "AKIAIOSFODNN7EXAMPLE"
Fingerprint: abc123...

❌ Commit blocked - remove secrets and try again
```

### Auto-Fix Case

```bash
$ git commit -m "Add code"

black...................................................Failed
- hook id: black
- files were modified by this hook

Reformatted src/app.py
1 file reformatted.

Fix applied! Stage the changes and commit again:
  git add src/app.py
  git commit -m "Add code"
```

---

## Hook Details

### Gitleaks (Secret Detection)

```yaml
- repo: https://github.com/gitleaks/gitleaks
  rev: v8.18.0
  hooks:
    - id: gitleaks
      args: ['--config=.gitleaks.toml']
```

**Detects:** API keys, tokens, passwords, certificates

**Exit code:** 1 if secrets found

**Can auto-fix:** No (must manually remove)

---

### Semgrep (SAST)

```yaml
- repo: https://github.com/returntocorp/semgrep
  rev: v1.45.0
  hooks:
    - id: semgrep
      args: ['--config=auto', '--error']
```

**Detects:** OWASP Top 10, SQL injection, XSS, etc.

**Exit code:** 1 on ERROR severity

**Can auto-fix:** Some rules support auto-fix

---

### Hadolint (Dockerfile Linting)

```yaml
- repo: https://github.com/hadolint/hadolint
  rev: v2.12.0
  hooks:
    - id: hadolint
      args: ['--config=.hadolint.yaml']
```

**Detects:** Dockerfile best practice violations

**Exit code:** 1 on violations

**Can auto-fix:** No

---

### Conftest (Policy Checks)

```yaml
- repo: https://github.com/open-policy-agent/conftest
  rev: v0.47.0
  hooks:
    - id: conftest
      files: \.(yaml|yml|json|tf)$
      args: ['test', '--policy=conftest-policy.rego']
```

**Detects:** OPA policy violations in K8s, Terraform, etc.

**Exit code:** 1 on policy violations

**Can auto-fix:** No

---

## Customization

### Skip Hooks Temporarily

```bash
# Skip all hooks
git commit -m "Emergency fix" --no-verify

# Skip specific hook
SKIP=gitleaks git commit -m "Test data"
```

### Run Specific Hooks

```bash
# Run only Gitleaks
pre-commit run gitleaks

# Run only on specific files
pre-commit run --files src/app.py
```

### Update Hook Versions

```bash
# Update all hooks to latest versions
pre-commit autoupdate

# Update specific hook
pre-commit autoupdate --repo https://github.com/gitleaks/gitleaks
```

---

## CI Integration (Enforce Hooks)

Catch developers who skip hooks with `--no-verify`:

```yaml
# .github/workflows/pre-commit-ci.yml
name: Pre-commit CI

on: [pull_request]

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
      - uses: pre-commit/action@v3.0.0
```

---

## Troubleshooting

### "Hooks run too slow"

1. Use minimal config instead of full
2. Skip language-specific hooks you don't need
3. Use `fail_fast: true` to stop at first failure
4. Add `stages: [push]` to only run on push, not commit

### "Hook fails on unrelated files"

```yaml
# Add file filters
- id: semgrep
  files: \.(py|js|go)$  # Only Python, JS, Go
  exclude: ^tests/      # Skip tests directory
```

### "Want to disable a hook temporarily"

```yaml
# In .pre-commit-config.yaml
- repo: https://github.com/gitleaks/gitleaks
  rev: v8.18.0
  hooks:
    - id: gitleaks
      stages: [manual]  # Only run when explicitly called
```

---

## Installation Script

Use the provided script to auto-install:

```bash
./03-templates/pre-commit/install.sh

# Or with options
./03-templates/pre-commit/install.sh --config full --auto-update
```

---

*Part of the Iron Legion - CKS | CKA | CCSP Certified Standards*
