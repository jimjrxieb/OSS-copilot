# Playbook 00: Understand Your Repo

> Run BEFORE any scanner. Look at what you're scanning before you scan it.
>
> **Time:** 5 minutes
> **Prerequisites:** None — just a terminal and your repo

---

## Why This Matters

Scanning without understanding is how you waste an afternoon chasing 85 false
positives from build artifacts that aren't even your code. A senior engineer
walks the codebase first. You should too.

This playbook teaches you to do what a senior engineer does instinctively:
look at the codebase, understand what's source code vs. generated files, and
configure the scanners to ignore the noise.

---

## Step 1: Look at Your Project Structure

```bash
cd /path/to/your/project

# What files are in here?
find . -type f -not -path './.git/*' | head -50

# What languages are you working with?
find . -name "*.py" | wc -l        # Python
find . -name "*.js" | wc -l        # JavaScript
find . -name "*.go" | wc -l        # Go
find . -name "*.tf" | wc -l        # Terraform
find . -name "*.yaml" -o -name "*.yml" | wc -l  # YAML (K8s, CI, configs)
find . -name "Dockerfile*" | wc -l  # Dockerfiles
```

**What you're looking for:**
- Which languages does this project use? (This tells you which scanners to run)
- Are there build artifacts? (`node_modules/`, `.terraform/`, `vendor/`, `__pycache__/`)
- Are there Dockerfiles? Kubernetes manifests? Terraform configs?

---

## Step 2: Identify Noise Sources

These directories will generate hundreds of false positives if you scan them.
They're not your code — they're downloaded dependencies or build outputs.

| Directory | What It Is | Why It's Noise |
|-----------|-----------|----------------|
| `node_modules/` | npm packages (JavaScript) | Thousands of third-party files |
| `.terraform/` | Terraform provider binaries | Compiled Go — not your code |
| `vendor/` | Go/PHP vendor dependencies | Third-party source code |
| `__pycache__/` | Python compiled bytecode | Generated files |
| `venv/` or `.venv/` | Python virtual environment | Installed packages |
| `dist/` or `build/` | Build output | Compiled/bundled code |
| `.next/` | Next.js build output | Generated React code |

```bash
# Check which of these exist in your project
for dir in node_modules .terraform vendor __pycache__ venv .venv dist build .next; do
    [ -d "$dir" ] && echo "FOUND: $dir (exclude this from scans)"
done
```

---

## Step 3: Check for Existing Security Configs

Your project might already have security scanning configured. Check for these:

```bash
# Existing scanner configs
ls -la .gitleaks.toml 2>/dev/null        # Gitleaks config
ls -la .semgrep.yml 2>/dev/null          # Semgrep config
ls -la .bandit 2>/dev/null               # Bandit config
ls -la .hadolint.yaml 2>/dev/null        # Hadolint config
ls -la .trivyignore 2>/dev/null          # Trivy ignore list
ls -la .pre-commit-config.yaml 2>/dev/null  # Pre-commit hooks

# CI security workflows
ls -la .github/workflows/*security* 2>/dev/null
ls -la .github/workflows/*scan* 2>/dev/null
```

If any of these exist, read them. They tell you what the previous team already set up
(or tried to set up).

---

## Step 4: Make a Mental Map

Before scanning, answer these questions:

```
1. What languages?           → Determines which SAST scanners to run
   Python → Bandit + Semgrep
   JavaScript → Semgrep
   Go → Semgrep
   Any language → Semgrep covers 30+ languages

2. Any Dockerfiles?          → Run Hadolint (from 02-container)
3. Any Kubernetes YAMLs?     → Run Kubescape/Polaris (from 03-cluster)
4. Any Terraform?            → Run Checkov/tfsec (from 04-cloud)
5. Any .env files?           → These probably have real secrets — Gitleaks will flag them
6. Any hardcoded URLs?       → Might indicate hardcoded API endpoints
```

---

## Step 5: You're Ready to Scan

Now you know:
- What languages you're scanning (which tools to use)
- What directories to exclude (avoid false positives)
- Whether security scanning already exists (don't duplicate)

Go to: [01-first-scan.md](01-first-scan.md)

---

## What a Senior Engineer Does Differently

A junior runs every scanner against the entire repo and gets 300 findings.
A senior spends 5 minutes understanding the repo and gets 40 real findings.

The difference isn't the tools — it's the 5 minutes of understanding first.

This is the **Understand** phase of Understand → Secure → Optimize → Outcome.
You don't secure what you haven't understood.
