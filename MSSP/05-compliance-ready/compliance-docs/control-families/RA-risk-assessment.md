# RA — Risk Assessment

## RA-5: Vulnerability Monitoring and Scanning

**Requirement**: Scan for vulnerabilities in the information system and hosted applications, and remediate legitimate vulnerabilities in accordance with risk assessments.

**Implementation**:
- **Container Scanning**: Trivy scans container images for known CVEs (OS packages + application deps)
- **Static Analysis**: Semgrep performs SAST on application source code
- **Secret Detection**: Gitleaks identifies leaked credentials
- **Dependency Scanning**: Trivy + Grype check dependency manifests
- **Policy Compliance**: Conftest validates Kubernetes manifests against OPA policies
- **Risk Classification**: Priority system (E-S) categorizes findings by severity and remediation complexity

**Scanning Pipeline**:
```
Source Code → Semgrep (SAST) → Code vulnerabilities
           → Gitleaks → Credential exposure
Container  → Trivy → CVEs, misconfigurations
Manifests  → Conftest → Policy violations
All        → scan-and-map.py → NIST 800-53 mapping
           → gap-analysis.py → E-S risk categorization
```

**Vulnerability Classification (Priority Levels)**:

| Priority | CVSS Equivalent | Remediation | SLA |
|------|----------------|-------------|-----|
| E | Informational | Auto-fix, no approval | Immediate |
| D | Low-Medium | Auto-fix, logged | < 24 hours |
| C | Medium-High | Security review | < 72 hours |
| B | High-Critical | Human review required | < 7 days |
| S | Critical/Strategic | Human-only decision | Risk-based |

**Evidence**:
- `{{EVIDENCE_DIR}}/scan-reports/` — All scan results
- `{{EVIDENCE_DIR}}/remediation/` — Remediation reports
- `01-scanning-configs/` — Scanner configurations
- `ci-templates/fedramp-compliance.yml` — Automated scanning pipeline

**Tooling**:
- **CI Pipeline**: Primary scanner operator — runs Trivy, Semgrep, Gitleaks, Conftest
- **Assessment Pipeline**: Classifies findings to priority levels, maps to NIST controls
- **Risk Prioritization**: Severity-based risk categorization (supports RA-2)
