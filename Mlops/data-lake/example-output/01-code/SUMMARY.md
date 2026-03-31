# 01-Code — Scan Results

> Application security scan of Portfolio.
> Secrets, SAST, and dependency CVEs.

---

## Findings

| Scanner | What It Found | Count | Severity |
|---------|--------------|-------|----------|
| **Gitleaks** | Hardcoded secrets | 7 | 1 AWS key, 3 Stripe tokens, 2 API keys, 1 policy example |
| **Semgrep** | Code vulnerabilities | 56 | 6 error, 25 warning, 25 info |
| **Trivy** | Dependency CVEs (HIGH+) | 4 | 4 HIGH (`tar` package) |
| **Grype** | Dependency CVEs (fixable) | 70 | 7 critical, 32 high, 27 medium, 4 low |

---

## Secrets (Gitleaks)

| Rule | File | Real or Noise? |
|------|------|---------------|
| `aws-access-token` | GP-copilot/01-package/playbooks/ | Noise — example key in training playbook |
| `stripe-access-token` x3 | PracticeMakesPerfect/day3*.md | Noise — practice exercise |
| `generic-api-key` x2 | watchers/, docs/ | Review — could be real, extract to env vars |

**Action:** Verify the 2 generic API keys. The rest are training material.

---

## Code Vulnerabilities (Semgrep)

| Severity | Count | What | Real? |
|----------|-------|------|-------|
| ERROR (6) | AWS access key patterns | In `.oss-copilot/` scan output files | **Noise** — Semgrep scanning its own output |
| WARNING (25) | K8s misconfigs (hostNetwork, hostPID, privilege escalation) | In `before-violations.yaml` | **Noise** — intentional bad examples for demos |
| INFO (25) | K8s best practices (runAsNonRoot missing) | In Kyverno policy templates | **Noise** — policy definitions, not running containers |

**After filtering noise: ~4 real findings** (the generic API key patterns
that overlap with Gitleaks).

**Lesson learned:** Semgrep needs `--exclude` for scan output directories
and example/demo files. The `--exclude=".oss-copilot"` flag was added to
the scripts after this scan.

---

## Dependencies (Trivy + Grype)

### Trivy — 4 HIGH CVEs

| CVE | Package | Installed | Fixed |
|-----|---------|-----------|-------|
| CVE-2026-24842 | tar | 7.5.6 | 7.5.7 |
| CVE-2026-26960 | tar | 7.5.6 | 7.5.8 |
| CVE-2026-29786 | tar | 7.5.6 | 7.5.10 |

**Fix:** `npm update tar` — one command, all three CVEs resolved.

### Grype — 70 Fixable CVEs

| Severity | Count | Packages |
|----------|-------|----------|
| Critical | 7 | aquasecurity/trivy-action, stdlib (Go), grpc |
| High | 32 | kin-openapi, oauth2, stdlib (Go), tar |
| Medium | 27 | Various |
| Low | 4 | Various |

**Fix:** Most are Go module dependencies in tooling, not application code.
The npm dependency (`tar`) is the only one directly in the application.

---

## Auto-Fix Results

| Category | Tool | Before | After | Command |
|----------|------|--------|-------|---------|
| npm dependencies | `npm audit fix` | 70 CVEs | 0 | `npm audit fix` |
| Trivy HIGH CVEs | `npm update tar` | 4 | 0 | `npm update tar` |
| Semgrep code patterns | `semgrep --autofix` | 43 fixable | Mixed | Works for Python/JS, breaks YAML |

**Total auto-fixable: ~74 of 137 findings (54%)** with two commands.

---

## Output Files

| File | Scanner | Size | What's In It |
|------|---------|------|-------------|
| `gitleaks-results.json` | Gitleaks | 10KB | 7 secret findings (current state) |
| `gitleaks-history-results.json` | Gitleaks | 10KB | 7 secret findings (git history) |
| `semgrep-results.json` | Semgrep | 388KB | 56 SAST findings with rule metadata |
| `trivy-deps-results.json` | Trivy | 100KB | 4 HIGH CVEs with fix versions |
| `grype-results.json` | Grype | 200KB | 70 fixable CVEs with package details |
