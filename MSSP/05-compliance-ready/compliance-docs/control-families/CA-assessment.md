# CA — Security Assessment and Authorization

## CA-2: Security Assessments

**Requirement**: Develop a security assessment plan, assess security controls, produce a security assessment report, and remediate findings.

**Implementation**:
- **Assessment Plan**: Automated security scanning on every code push and on schedule
- **Assessment Execution**: Multi-tool scanning pipeline (Trivy, Semgrep, Gitleaks, Conftest)
- **Assessment Report**: scan-and-map.py generates security reports with NIST 800-53 control mapping
- **Remediation**: Auto-remediate E-D rank findings; C-rank requires security review; B-S escalated to human

**Assessment Workflow**:
```
Code Push → CI/CD triggers scan pipeline
  → Trivy (container vulnerabilities, SI-2)
  → Semgrep (code vulnerabilities, RA-5)
  → Gitleaks (secret detection, IA-5)
  → Conftest (policy compliance, CM-6)
  → scan-and-map.py (NIST 800-53 mapping)
  → gap-analysis.py classifies findings (E-S priority)
  → Auto-remediate (E-D) or escalate (B-S)
  → Generate evidence artifacts
```

**Evidence**:
- `{{EVIDENCE_DIR}}/scan-reports/` — Assessment results
- `ci-templates/fedramp-compliance.yml` — Automated assessment pipeline
- `tools/scan-and-map.py` — NIST control mapping tool

**Tooling**:
- **Assessment Pipeline**: Primary owner — orchestrates assessments, classifies risk, generates reports
- **CI Pipeline**: Executes pre-deployment scans
- **Runtime Monitoring**: Executes runtime assessments
- **Risk Prioritization**: Maps findings to risk levels (RA-2 supporting CA-2)

---

## CA-7: Continuous Monitoring

**Requirement**: Develop a continuous monitoring strategy and implement a continuous monitoring program.

**Implementation**:
- **Ongoing Assessments**: CI/CD runs scans on every push and weekly schedule
- **Runtime Monitoring**: Falco watchers for syscall-level detection
- **Policy Enforcement**: OPA/Gatekeeper + Kyverno continuously enforce admission policies
- **Drift Detection**: Kubescape detects configuration drift from declared baseline
- **Status Reporting**: Scan results auto-mapped to NIST controls, POA&M updated

**Monitoring Frequency**:

| Activity | Frequency | Tool |
|----------|-----------|------|
| SAST scanning | Every push | Semgrep |
| Container scanning | Every push | Trivy |
| Secret detection | Every push | Gitleaks |
| Policy validation | Every push | Conftest |
| Runtime threat detection | Continuous | Falco |
| Admission enforcement | Continuous | OPA/Kyverno |
| Drift detection | Hourly | Kubescape |
| NIST control mapping | Every push | scan-and-map.py |

**Evidence**:
- `ci-templates/fedramp-compliance.yml` — CI/CD continuous monitoring
- `policies/` — Policy-as-code enforcement
- `{{EVIDENCE_DIR}}/scan-reports/` — Historical evidence trail
