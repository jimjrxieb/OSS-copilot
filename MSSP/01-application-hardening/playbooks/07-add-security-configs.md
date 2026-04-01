# 07 — Add Security Configs

> Drop tuned scanner configs into your repo so scanners run consistently everywhere.

The CI pipeline and pre-commit hooks reference config files. Without them, scanners run with noisy defaults. This playbook deploys the configs we've already tested.

---

## Step 1: Copy Scanning Configs

```bash
cd $TARGET_DIR

# Copy the configs that scanners reference
cp ../../MSSP/01-application-hardening/scan-configs/.gitleaks.toml .
cp ../../MSSP/01-application-hardening/scan-configs/.bandit .
cp ../../MSSP/01-application-hardening/scan-configs/.hadolint.yaml .
cp ../../MSSP/01-application-hardening/scan-configs/semgrep.yaml .
cp ../../MSSP/01-application-hardening/scan-configs/trivy.yaml .

# Only if your project has K8s manifests
cp ../../MSSP/01-application-hardening/scan-configs/kubescape.json .
cp ../../MSSP/01-application-hardening/scan-configs/polaris.yaml .
```

---

## Step 2: Create Allowlists

### `.gitleaksignore` — suppress known false positives

```bash
cat > .gitleaksignore << 'EOF'
# Format: fingerprint (file:rule:line)
# Only add findings you've VERIFIED are not real secrets

# Example: test fixtures with fake credentials
# tests/fixtures/config.py:generic-api-key:42
EOF
```

### `.trivyignore` — accepted CVE risks

```bash
cat > .trivyignore << 'EOF'
# Format: CVE-YYYY-NNNNN
# Each entry needs a comment explaining why

# Example:
# CVE-2024-12345  # No fix available, transitive dep, not reachable
EOF
```

---

## Step 3: Wire Into CI

If your CI workflow (from playbook 06) doesn't already reference these, add:

```yaml
    - name: Gitleaks
      uses: gitleaks/gitleaks-action@v2
      with:
        config: .gitleaks.toml

    - name: Hadolint
      run: hadolint --config .hadolint.yaml Dockerfile

    - name: Trivy
      run: trivy fs . --config trivy.yaml
```

The pipeline templates from playbook 06 already reference these paths.

---

## Step 4: Add Scanner Artifacts to .gitignore

```bash
cat >> .gitignore << 'EOF'

# Scanner outputs (generated, not source)
*.sarif
*.sarif.json

# Scanner caches
.semgrep/
.trivy/
EOF
```

---

## Step 5: Verify

```bash
gitleaks detect --source . --no-git --config .gitleaks.toml 2>&1 | tail -3
hadolint --config .hadolint.yaml Dockerfile 2>&1 | head -5
trivy fs . --config trivy.yaml 2>&1 | tail -5
```

---

## Step 6: Commit

```bash
git add .gitleaks.toml .gitleaksignore .bandit .hadolint.yaml semgrep.yaml trivy.yaml .trivyignore
git commit -m "security: add scanner configs and allowlists"
```

---

## What Gets Deployed

| File | Used By | Purpose |
|------|---------|---------|
| `.gitleaks.toml` | CI, pre-commit, scanners | Secret detection patterns |
| `.gitleaksignore` | Gitleaks | False positive suppression |
| `.bandit` | CI, scanners | Python SAST config |
| `.hadolint.yaml` | CI, pre-commit | Dockerfile lint rules |
| `semgrep.yaml` | Reference | SAST ruleset docs |
| `trivy.yaml` | CI, scanners | CVE scanner config |
| `.trivyignore` | Trivy | Accepted CVE risks |

Same configs everywhere — local, pre-commit, CI. No gaps.

---

## Next Step

Go to [08-add-pre-commit.md](08-add-pre-commit.md) to install pre-commit hooks.
