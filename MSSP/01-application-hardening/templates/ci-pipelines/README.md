# CI/CD Pipeline Templates

> Drop-in GitHub Actions workflows for shift-left security.

---

## Quick Start

Copy the workflows you need to your repository:

```bash
# Copy all workflows
cp 03-templates/ci-pipelines/*.yml /path/to/your/repo/.github/workflows/

# Or copy specific workflows
cp 03-templates/ci-pipelines/gitleaks.yml /path/to/your/repo/.github/workflows/
cp 03-templates/ci-pipelines/semgrep.yml /path/to/your/repo/.github/workflows/
```

---

## Available Workflows

### Full Security Pipeline (Recommended)

**File:** `full-security-pipeline.yml`

Runs all 12 scanners on every push/PR. Best for comprehensive coverage.

```yaml
# Triggers: push, pull_request
# Duration: ~5-10 minutes
# Scanners: All 12 (Gitleaks, Semgrep, Trivy, etc.)
```

**Usage:**
```bash
cp 03-templates/ci-pipelines/full-security-pipeline.yml .github/workflows/security.yml
```

---

### Individual Scanner Workflows

Pick and choose which scanners to run separately:

| Workflow | Scanner | Speed | When to Use |
|----------|---------|-------|-------------|
| `gitleaks.yml` | Gitleaks | Fast (~30s) | Always — blocks secrets from merging |
| `semgrep.yml` | Semgrep | Medium (~2min) | SAST for all languages |
| `trivy-fs.yml` | Trivy | Medium (~2min) | Dependency CVEs |
| `policy-check.yml` | Conftest | Fast (~30s) | OPA policy enforcement |
| `deploy-dev.yml` | Helm + Trivy + Checkov | Medium (~5min) | Build, scan, deploy to dev cluster |

> **Note:** Container scanning, K8s scanning, Terraform scanning, and CIS benchmarks
> are all jobs inside `full-security-pipeline.yml`. They auto-skip via `hashFiles()`
> if the repo doesn't have the relevant file types. Use the full pipeline and comment
> out what you don't need rather than building individual workflows.

---

## Workflow Details

### gitleaks.yml

**Detects:** Secrets, API keys, tokens, credentials

```yaml
# When: Every push, every PR
# Action: BLOCK if secrets found
# Exit code: 1 if secrets detected
```

**Configuration:**
- Uses `.gitleaks.toml` from repo root
- Scans entire git history
- Comments on PRs with findings

---

### semgrep.yml

**Detects:** OWASP Top 10, CWE Top 25, code vulnerabilities

```yaml
# When: Every push, every PR
# Action: BLOCK on ERROR severity
# Languages: 30+ (Python, JS, Go, Java, etc.)
```

**Configuration:**
- Uses `semgrep.yaml` from repo root
- Uploads SARIF to GitHub Security tab
- Supports custom rules

---

### trivy-fs.yml

**Detects:** Dependency CVEs in package files

```yaml
# When: Every push, every PR
# Action: BLOCK on CRITICAL/HIGH with fix available
# Ecosystems: npm, pip, go, maven, bundler, etc.
```

**Configuration:**
- Uses `trivy.yaml` from repo root
- Generates SBOM (CycloneDX)
- Uploads to GitHub Dependency Graph

---

### policy-check.yml

**Detects:** OPA policy violations in K8s manifests and Terraform

```yaml
# When: On manifests/ or terraform/ changes
# Action: BLOCK on policy violations
# Policies: Custom OPA Rego policies from repo's policy/ directory
```

**Configuration:**
- Looks for `.rego` files in the repo's `policy/` directory
- Validates K8s manifests, Terraform
- Fails PR on DENY rules

---

## Customization Guide

### Change Trigger Events

```yaml
# Default: push + pull_request
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
```

### Change Severity Threshold

```yaml
# In trivy-fs.yml
- name: Run Trivy
  env:
    SEVERITY: CRITICAL,HIGH  # Only block on CRITICAL+HIGH
```

### Add Path Filters

```yaml
# Only run on specific paths
on:
  push:
    paths:
      - 'src/**'
      - 'manifests/**'
      - 'Dockerfile'
```

### Add Required Reviewers

```yaml
# Add to workflow
- name: Request review on findings
  if: failure()
  run: |
    gh pr edit ${{ github.event.pull_request.number }} \
      --add-reviewer security-team
```

---

## Branch Protection Setup

Configure these as required checks:

1. **Navigate to:** Repo Settings → Branches → Branch protection rules
2. **Add rule for:** `main` (or your default branch)
3. **Enable:** "Require status checks to pass"
4. **Select required checks:**
   - `Gitleaks` (always required)
   - `Semgrep` (recommended)
   - `Trivy filesystem scan` (recommended)
   - `Policy check` (if using OPA)

---

## Performance Optimization

### Parallel Execution

Workflows run in parallel by default. To run scanners sequentially:

```yaml
jobs:
  gitleaks:
    runs-on: ubuntu-latest
    # ...

  semgrep:
    runs-on: ubuntu-latest
    needs: gitleaks  # Wait for gitleaks to finish
    # ...
```

### Caching

Speed up workflows with caching:

```yaml
- name: Cache Trivy DB
  uses: actions/cache@v3
  with:
    path: ~/.cache/trivy
    key: ${{ runner.os }}-trivy-${{ github.run_id }}
    restore-keys: |
      ${{ runner.os }}-trivy-
```

### Matrix Strategy

Scan multiple versions in parallel:

```yaml
strategy:
  matrix:
    scanner: [gitleaks, semgrep, trivy]
steps:
  - name: Run ${{ matrix.scanner }}
    run: ./scripts/run-scanner.sh ${{ matrix.scanner }}
```

---

## Troubleshooting

### "Workflow runs too long"

1. Use individual workflows instead of full-pipeline
2. Add path filters to skip unnecessary scans
3. Use matrix strategy for parallel execution
4. Cache scanner databases

### "Too many false positives"

1. Add allowlists to scanner configs
2. Use `.trivyignore`, `.semgrepignore`
3. Adjust severity thresholds
4. Add exceptions to `conftest-policy.rego`

### "Blocking legitimate PRs"

1. Use `continue-on-error: true` for non-critical scanners
2. Change from `BLOCK` to `WARN` mode
3. Add exceptions for specific findings
4. Use `soft-fail: true` in scanner configs

---

## Migration from Other CI Systems

### From GitLab CI

```yaml
# GitLab (.gitlab-ci.yml)
gitleaks:
  image: zricethezav/gitleaks
  script: gitleaks detect

# GitHub Actions (gitleaks.yml)
- name: Run Gitleaks
  uses: gitleaks/gitleaks-action@v2
```

### From CircleCI

```yaml
# CircleCI (.circleci/config.yml)
- run:
    name: Run Semgrep
    command: semgrep --config=auto

# GitHub Actions (semgrep.yml)
- name: Run Semgrep
  uses: returntocorp/semgrep-action@v1
```

---

## GitHub Actions Secrets Required

These are the secrets you need to configure in the client repo under
**Settings > Secrets and variables > Actions** before the pipeline will work.

| Secret | Required? | Used By | How to Get It |
|--------|-----------|---------|---------------|
| `GITHUB_TOKEN` | Auto-provided | Gitleaks, SARIF uploads | GitHub provides this automatically — no setup needed |
| `SEMGREP_APP_TOKEN` | Optional | Semgrep | Free at [semgrep.dev](https://semgrep.dev) > Settings > Tokens. Without it, Semgrep still runs but uses local rules only (no Semgrep Cloud findings) |

That's it. Every other scanner runs without secrets — Trivy, Grype, Checkov, Kubescape,
Polaris, Hadolint, TFsec, Conftest, kube-bench, and Bandit all work out of the box.

### SARIF Uploads (GitHub Security Tab)

For SARIF uploads to show in the repo's **Security > Code scanning** tab, the repo needs:
- **GitHub Advanced Security** enabled (free for public repos, paid for private)
- Or the findings just upload as artifacts instead (still downloadable, just not in the Security tab)

If the client doesn't have GHAS on private repos, the pipeline still runs — the SARIF
upload steps will fail silently and findings are still available as workflow artifacts.

---

## Local Tool Installation (Client Machine Setup)

When you're on a client's machine and need to run scanners locally before setting up CI/CD,
or when you need to verify findings manually.

### Required (install these first)

```bash
# Gitleaks — secret detection
# macOS
brew install gitleaks
# Linux
curl -fsSL https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_linux_x86_64.tar.gz | tar xz
sudo mv gitleaks /usr/local/bin/

# Trivy — dependency + container + IaC scanning (does the most)
# macOS
brew install trivy
# Linux
curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

# Semgrep — SAST (multi-language)
pip install semgrep
# or: brew install semgrep
```

### Recommended (install if the repo has K8s/Terraform/Docker)

```bash
# Checkov — IaC scanning (Terraform, K8s, CloudFormation, Dockerfile)
pip install checkov

# Hadolint — Dockerfile linting
# macOS
brew install hadolint
# Linux
curl -fsSL https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64 -o /usr/local/bin/hadolint
chmod +x /usr/local/bin/hadolint

# Kubescape — K8s configuration auditing (NSA/CISA frameworks)
curl -fsSL https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | sudo /bin/bash

# Conftest — OPA policy validation
# macOS
brew install conftest
# Linux
curl -fsSL https://github.com/open-policy-agent/conftest/releases/latest/download/conftest_Linux_x86_64.tar.gz | tar xz
sudo mv conftest /usr/local/bin/
```

### Optional (for specific use cases)

```bash
# Bandit — Python-only SAST (skip if no Python in repo)
pip install bandit

# Grype — alternative dependency scanner (Trivy already covers this)
curl -fsSL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sudo sh -s -- -b /usr/local/bin

# TFsec — Terraform-specific scanner (Checkov already covers this)
# macOS
brew install tfsec
# Linux
curl -fsSL https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-linux-amd64 -o /usr/local/bin/tfsec
chmod +x /usr/local/bin/tfsec

# Polaris — K8s best practices (Kubescape already covers most of this)
# macOS
brew install FairwindsOps/tap/polaris
# Linux
curl -fsSL https://github.com/FairwindsOps/polaris/releases/latest/download/polaris_linux_amd64.tar.gz | tar xz
sudo mv polaris /usr/local/bin/

# kube-bench — CIS Kubernetes benchmark (needs cluster access)
curl -fsSL https://github.com/aquasecurity/kube-bench/releases/latest/download/kube-bench_linux_amd64.tar.gz | tar xz
sudo mv kube-bench /usr/local/bin/
```

### Quick Verify (confirm tools are working)

```bash
gitleaks version
trivy --version
semgrep --version
checkov --version 2>/dev/null && echo "checkov OK"
hadolint --version 2>/dev/null && echo "hadolint OK"
kubescape version 2>/dev/null && echo "kubescape OK"
conftest --version 2>/dev/null && echo "conftest OK"
```

### Minimum Viable Setup

If you only have 5 minutes on a client machine, install these 3:

1. **Gitleaks** — finds secrets (highest severity, fastest scan)
2. **Trivy** — covers dependencies, containers, IaC, and K8s configs in one tool
3. **Semgrep** — covers SAST across all languages

These three cover ~80% of findings. Everything else is supplemental.

---

*GP-Consulting — 01-APP-SEC CI/CD Templates*
