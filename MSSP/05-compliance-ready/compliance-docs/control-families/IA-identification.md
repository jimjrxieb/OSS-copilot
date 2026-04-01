# IA — Identification and Authentication

## IA-2: Identification and Authentication (Organizational Users)

**Requirement**: Uniquely identify and authenticate organizational users. Implement multi-factor authentication.

**Implementation**:
- Application-level: MFA required for all user accounts (TOTP, WebAuthn, or IdP-delegated)
- Session management: cryptographically random tokens (secrets module), idle + absolute timeouts
- Account lockout: 5 failed attempts triggers 30-minute lockout
- Password policy: NIST 800-63B compliant (12+ chars, breach-list check, no forced rotation)
- Kubernetes-level: OIDC/SAML federation for cluster access, no shared credentials
- CI/CD: service accounts with scoped tokens, no long-lived credentials

**Evidence**:
- `frontend/remediation/secure-authentication.md` — Implementation guide
- Application auth configuration screenshots
- IdP federation configuration
- `{{EVIDENCE_DIR}}/auth-config/` — Auth system documentation

**Tooling**:
- **CI Pipeline**: Semgrep rules detect weak session tokens, missing CSRF protection
- **Assessment Pipeline**: Reviews auth architecture decisions (B-rank — requires human approval)

---

## IA-5: Authenticator Management

**Requirement**: Manage information system authenticators by verifying the identity of individuals, groups, roles, or devices receiving the authenticator.

**Implementation**:
- **Secret Detection**: Gitleaks scans every commit for hardcoded credentials, API keys, tokens
- **Secret Rotation**: Kubernetes Secrets managed with rotation policies
- **No Hardcoded Secrets**: CI pipeline blocks commits containing secrets
- **Service Account Tokens**: Auto-mounted tokens disabled by default; explicitly bound where needed
- **Image Pull Secrets**: Scoped to specific namespaces

**Secret Detection Rules** (Gitleaks):

| Pattern | Description | Severity |
|---------|-------------|----------|
| AWS access keys | `AKIA[0-9A-Z]{16}` | Critical |
| Private keys | `-----BEGIN.*PRIVATE KEY-----` | Critical |
| API tokens | Generic high-entropy strings | High |
| Database passwords | Connection string passwords | High |
| JWT tokens | `eyJ...` base64 patterns | Medium |

**Evidence**:
- `01-scanning-configs/gitleaks-fedramp.toml` — Secret detection configuration
- `{{EVIDENCE_DIR}}/gitleaks-results.json` — Secret scan results
- `ci-templates/fedramp-compliance.yml` — CI gate blocking secret commits

**Tooling**:
- **CI Pipeline**: Gitleaks scanner detects secrets pre-commit/pre-merge (E-rank auto-block)
- **Runtime Monitoring**: Monitors Kubernetes Secrets for unauthorized access at runtime
- **Assessment Pipeline**: Escalates credential exposure as B-rank finding (human notification required)
