# Scanner Configurations

> Drop-in configuration files for all 16 jsa-devsec scanners.

---

## Quick Start

Copy the configs you need to your repository root:

```bash
# Copy all configs
cp 01-scanners/configs/* /path/to/client/repo/

# Or copy individual configs
cp 01-scanners/configs/.gitleaks.toml /path/to/client/repo/
cp 01-scanners/configs/semgrep.yaml /path/to/client/repo/
cp 01-scanners/configs/trivy.yaml /path/to/client/repo/
```

---

## Configuration Files

| Scanner | Config File | Purpose |
|---------|-------------|---------|
| **Gitleaks** | `.gitleaks.toml` | Secret detection rules, allowlists |
| **Semgrep** | `semgrep.yaml` | SAST rulesets, paths to scan |
| **Bandit** | `.bandit` | Python SAST config, exclusions |
| **Trivy** | `trivy.yaml` | Vulnerability severity, ignore policies |
| **Checkov** | `.checkov.yaml` | IaC frameworks, skip checks |
| **Kubescape** | `kubescape.json` | NSA/CISA frameworks, exceptions |
| **Polaris** | `polaris.yaml` | K8s best practice checks |
| **Hadolint** | `.hadolint.yaml` | Dockerfile linting rules |
| **Conftest** | `conftest-policy.rego` | Custom OPA policies for CI |

---

## Configuration Details

### Gitleaks (.gitleaks.toml)

**What it does:**
- Detects secrets in code, commits, and history
- Supports allowlists for test data
- Integrates with pre-commit and CI

**Key sections:**
```toml
[extend]
  useDefault = true  # Use Gitleaks default rules

[allowlist]
  description = "Allowlist for test files"
  paths = ['''tests/''', '''fixtures/''']

[[rules]]
  id = "custom-api-key"
  description = "Custom API Key Pattern"
  regex = '''api[_-]?key[_-]?[=:]\s*['"]?([a-zA-Z0-9]{32,})['"]?'''
```

---

### Semgrep (semgrep.yaml)

**What it does:**
- Multi-language SAST scanning
- OWASP Top 10 coverage
- Custom rule support

**Key sections:**
```yaml
rules:
  - p/security-audit      # General security
  - p/owasp-top-ten      # OWASP coverage
  - p/cwe-top-25         # CWE coverage
  - p/kubernetes         # K8s manifests
  - p/dockerfile         # Container security

paths:
  include:
    - "src/"
    - "app/"
  exclude:
    - "tests/"
    - "node_modules/"
```

---

### Trivy (trivy.yaml)

**What it does:**
- CVE scanning for dependencies
- IaC misconfiguration detection
- Secret detection in images

**Key sections:**
```yaml
severity:
  - CRITICAL
  - HIGH
  - MEDIUM

vulnerability:
  type:
    - os
    - library
  ignore-unfixed: true

secret:
  config: .gitleaks.toml
```

---

### Checkov (.checkov.yaml)

**What it does:**
- Terraform, K8s, CloudFormation scanning
- CIS benchmark checks
- Custom policy support

**Key sections:**
```yaml
framework:
  - terraform
  - kubernetes
  - dockerfile

skip-check:
  - CKV_AWS_23  # Example: Skip specific check

output:
  - cli
  - json
  - sarif
```

---

### Kubescape (kubescape.json)

**What it does:**
- NSA/CISA K8s hardening checks
- MITRE ATT&CK mappings
- CIS benchmark validation

**Key sections:**
```json
{
  "frameworks": [
    "nsa",
    "cisa",
    "mitre"
  ],
  "exceptions": {
    "namespace": ["kube-system"]
  },
  "severityThreshold": "medium"
}
```

---

## Customization Guide

### Add Allowlists (Gitleaks)

```toml
# .gitleaks.toml
[allowlist]
  description = "Test data and examples"
  paths = [
    '''tests/''',
    '''fixtures/''',
    '''examples/''',
    '''docs/'''
  ]

  # Allowlist specific strings
  regexes = [
    '''(sk_test_|pk_test_)''',  # Stripe test keys
    '''xoxb-test-'''            # Slack test tokens
  ]
```

### Exclude Paths (Semgrep)

```yaml
# semgrep.yaml
paths:
  exclude:
    - "tests/"
    - "vendor/"
    - "node_modules/"
    - "*.min.js"
    - "dist/"
    - "build/"
```

### Ignore Specific Vulnerabilities (Trivy)

```yaml
# trivy.yaml
vulnerability:
  ignore:
    - CVE-2021-12345  # Document why ignored
    - CVE-2022-67890  # Accepted risk, documented in POA&M
```

### Skip Checks (Checkov)

```yaml
# .checkov.yaml
skip-check:
  - CKV_AWS_23  # S3 bucket logging - not required for dev
  - CKV_K8S_8   # Liveness probe - covered by custom policy
```

---

## Integration Patterns

### Pre-Commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
        args: ['--config=.gitleaks.toml']

  - repo: https://github.com/returntocorp/semgrep
    rev: v1.45.0
    hooks:
      - id: semgrep
        args: ['--config=semgrep.yaml']
```

### GitHub Actions

```yaml
# .github/workflows/security.yml
- name: Run Gitleaks
  uses: gitleaks/gitleaks-action@v2
  with:
    config-path: .gitleaks.toml

- name: Run Semgrep
  uses: returntocorp/semgrep-action@v1
  with:
    config: semgrep.yaml
```

### CLI Usage

```bash
# Gitleaks
gitleaks detect --config .gitleaks.toml --source .

# Semgrep
semgrep --config semgrep.yaml

# Trivy
trivy fs --config trivy.yaml .

# Checkov
checkov --config-file .checkov.yaml

# Kubescape
kubescape scan --framework nsa,cisa --config kubescape.json
```

---

## Configuration Templates by Use Case

### Strict (Production)

```bash
cp 01-scanners/configs/strict/.gitleaks.toml .
# - No allowlists
# - All severity levels
# - Scan all paths including tests
```

### Balanced (Recommended)

```bash
cp 01-scanners/configs/.gitleaks.toml .
# - Test path allowlists
# - HIGH + CRITICAL only
# - Ignore test fixtures
```

### Permissive (Development)

```bash
cp 01-scanners/configs/permissive/.gitleaks.toml .
# - Broad allowlists
# - CRITICAL only
# - Focus on quick feedback
```

---

## Troubleshooting

### "Too many false positives"

1. Add paths to allowlist
2. Add specific regex patterns to allowlist
3. Skip specific checks by ID
4. Adjust severity threshold

### "Scan too slow"

1. Exclude large directories (node_modules, vendor)
2. Use parallel scanning
3. Limit scan depth
4. Cache scan results

### "Breaking existing workflows"

1. Start with permissive config
2. Gradually tighten over sprints
3. Use `--severity-threshold` to focus on critical first
4. Document exceptions in config files

---

*Part of the Iron Legion - CKS | CKA | CCSP Certified Standards*
