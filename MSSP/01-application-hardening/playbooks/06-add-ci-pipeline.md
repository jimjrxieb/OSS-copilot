# 06 — Add CI Pipeline

> Add security scanning to your GitHub Actions so every PR gets checked automatically.

Playbooks 00-04 fixed what was broken. This playbook prevents it from coming back. Every pull request gets scanned. Failed scans block the merge.

---

## What You Need

- Findings fixed (playbooks 00-04)
- Your project on GitHub with Actions enabled

---

## Step 1: Choose Your Pipeline

| Pipeline | Template File | Scanners | Run Time | Best For |
|----------|--------------|----------|----------|----------|
| **Full** | `full-security-pipeline.yml` | All 11 (src + infra) | 5-10 min | Default |
| **Source only** | `src-security-pipeline.yml` | Gitleaks, Semgrep, Bandit, Trivy, Grype, Hadolint | 3-5 min | Code-heavy repos, no K8s |
| **Infra only** | `infra-security-pipeline.yml` | Checkov, Kubescape, Polaris, Conftest | 2-4 min | IaC repos, K8s manifests |

Start with the full pipeline. Split later if run time becomes an issue.

---

## Step 2: Copy the Workflow

```bash
cd $TARGET_DIR
mkdir -p .github/workflows

# Full pipeline (recommended)
cp ../../MSSP/01-application-hardening/templates/ci-pipelines/full-security-pipeline.yml \
   .github/workflows/security.yml

# Or split pipelines
cp ../../MSSP/01-application-hardening/templates/ci-pipelines/src-security-pipeline.yml \
   .github/workflows/security-src.yml
cp ../../MSSP/01-application-hardening/templates/ci-pipelines/infra-security-pipeline.yml \
   .github/workflows/security-infra.yml
```

---

## Step 3: Configure (If Needed)

The workflows work out of the box. Customize the severity threshold if you want:

```yaml
env:
  SEVERITY_THRESHOLD: "HIGH"  # Options: LOW, MEDIUM, HIGH, CRITICAL
```

---

## Step 4: Set Up Branch Protection

The pipeline is useless if developers can merge without it passing.

```
GitHub repo > Settings > Branches > Add rule

Branch name pattern: main

Check these boxes:
  [x] Require a pull request before merging
  [x] Require status checks to pass before merging
      Required checks:
        secrets-scan
        sast-scan
        dependency-scan
  [x] Require branches to be up to date before merging
```

---

## Step 5: What Blocks vs What Warns

| Scanner | Blocks PR On | Warns Only |
|---------|-------------|------------|
| Gitleaks | Any finding | — |
| Semgrep | ERROR severity | WARNING |
| Bandit | HIGH+ | MEDIUM |
| Trivy | CRITICAL CVE | HIGH CVE |
| Grype | — | All (advisory) |
| Hadolint | WARNING+ | — |
| Checkov | HIGH IaC finding | MEDIUM |
| Kubescape | — | All (advisory) |
| Polaris | — | All (advisory) |
| Conftest | Any deny rule | warn rules |

---

## Step 6: Test It

```bash
git checkout -b test/security-pipeline
git add .github/workflows/
git commit -m "ci: add security scanning pipeline"
git push -u origin test/security-pipeline

# Create a PR and watch the checks run
gh pr create --title "Add security scanning" --body "Testing pipeline"
```

---

## Step 7: Verify It Blocks

Intentionally introduce a finding:

```bash
echo 'API_KEY = "AKIAIOSFODNN7EXAMPLE"' > test_secret.py
git add test_secret.py && git commit -m "test: verify blocking" && git push

# PR check should fail with Gitleaks finding
# After confirming, clean up:
git rm test_secret.py && git commit -m "test: remove test secret" && git push
```

---

## Nightly Scans

All templates include a scheduled run:

```yaml
on:
  schedule:
    - cron: '0 2 * * *'   # nightly at 2am UTC
```

This catches new CVEs disclosed overnight — even if no code changed.

---

## Next Steps

- Deploy scanner configs? > [07-add-security-configs.md](07-add-security-configs.md)
- Deploy pre-commit hooks? > [08-add-pre-commit.md](08-add-pre-commit.md)
