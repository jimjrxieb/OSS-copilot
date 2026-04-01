# Control Traceability Matrix — {{CLIENT_NAME}}

## FedRAMP Moderate Baseline — NIST 800-53 Rev 5

| Control | Name | Tool | Priority | Evidence | Status |
|---------|------|------|------|----------|--------|
| AC-2 | Account Management | K8s RBAC | D | `{{EVIDENCE_DIR}}/rbac-state.json` | {{STATUS}} |
| AC-3 | Access Enforcement | K8s RBAC + NetworkPolicy | D | `04-remediation/rbac.yaml` | {{STATUS}} |
| AC-6 | Least Privilege | Kyverno/Gatekeeper | D | `policies/kyverno/` | {{STATUS}} |
| AC-17 | Remote Access | K8s Audit | C | `04-remediation/audit-logging.yaml` | {{STATUS}} |
| AU-2 | Audit Events | Falco + K8s Audit | D | `04-remediation/audit-logging.yaml` | {{STATUS}} |
| AU-3 | Content of Records | K8s Audit | D | `{{EVIDENCE_DIR}}/audit-logs/` | {{STATUS}} |
| AU-9 | Protection of Audit Info | K8s RBAC + immutable log storage | D | `{{EVIDENCE_DIR}}/rbac-audit-logs.json` | {{STATUS}} |
| AU-12 | Audit Record Generation | Falco DaemonSet + K8s audit policy | D | `04-remediation/audit-logging.yaml` | {{STATUS}} |
| CA-2 | Security Assessments | scan-and-map.py | C | `{{EVIDENCE_DIR}}/nist-mapping-report.json` | {{STATUS}} |
| CA-7 | Continuous Monitoring | GHA + Falco + Kyverno | D | `ci-templates/fedramp-compliance.yml` | {{STATUS}} |
| CM-2 | Baseline Config | Git | E | Git history | {{STATUS}} |
| CM-6 | Config Settings | OPA/Kyverno/Conftest | D | `policies/` | {{STATUS}} |
| CM-7 | Least Functionality | Kyverno/Conftest block unnecessary services | D | `policies/kyverno/` | {{STATUS}} |
| CM-8 | Component Inventory | Trivy SBOM | D | `{{EVIDENCE_DIR}}/sbom.json` | {{STATUS}} |
| IA-2 | Identification & Authentication | MFA + OIDC federation + K8s RBAC identity | B | `frontend/remediation/secure-authentication.md` | {{STATUS}} |
| IA-5 | Authenticator Mgmt | Gitleaks | B | `{{EVIDENCE_DIR}}/gitleaks-results.json` | {{STATUS}} |
| IR-4 | Incident Handling | Falco alerts + automated response + runbooks | C | `03-RUNTIME-SECURITY/ENGAGEMENT-GUIDE.md` | {{STATUS}} |
| IR-5 | Incident Monitoring | Falco + Prometheus alerts | C | `{{EVIDENCE_DIR}}/incident-logs/` | {{STATUS}} |
| RA-2 | Security Categorization | FIPS 199 documented in SSP | B | `02-compliance-docs/ssp-skeleton.md` | {{STATUS}} |
| RA-5 | Vulnerability Scan | Trivy/Semgrep/Gitleaks | D | `{{EVIDENCE_DIR}}/scan-reports/` | {{STATUS}} |
| SA-10 | Developer Config Management | Git + branch protection + Gitleaks pre-commit | D | `ci-templates/fedramp-compliance.yml` | {{STATUS}} |
| SA-11 | Developer Testing & Evaluation | SAST in CI (Semgrep, Trivy, Conftest) | D | `ci-templates/sast-analysis.yml` | {{STATUS}} |
| SC-5 | DoS Protection | Kyverno resource limits + ResourceQuota | E | `policies/kyverno/require-resource-limits.yaml` | {{STATUS}} |
| SC-7 | Boundary Protection | K8s NetworkPolicy | D | `04-remediation/networkpolicy.yaml` | {{STATUS}} |
| SC-8 | Transmission Confidentiality | TLS ingress + mTLS between services | C | `04-remediation/network-policies.yaml` | {{STATUS}} |
| SC-28 | Protection at Rest | KMS/EBS | C | `backend/remediation/secrets-encryption.md` | {{STATUS}} |
| SI-2 | Flaw Remediation | Trivy + auto-patch | D | `{{EVIDENCE_DIR}}/trivy-latest.json` | {{STATUS}} |
| SI-3 | Malicious Code Protection | Trivy container scanning + Falco runtime | D | `ci-templates/container-scan.yml` | {{STATUS}} |
| SI-4 | System Monitoring | Falco + Kubescape + Prometheus | D | `03-RUNTIME-SECURITY/ENGAGEMENT-GUIDE.md` | {{STATUS}} |

---

## Tool Responsibility Summary

| Tool | Controls | Role |
|------|----------|------|
| **CI Pipeline (Trivy, Semgrep, Gitleaks, Conftest)** | RA-5, SI-2, SI-3, CM-6, CM-7, CM-8, IA-5, AC-6, CM-2, SA-10, SA-11 | Pre-deployment scanning |
| **Runtime Monitoring (Falco, Kubescape, kube-bench)** | CA-7, SC-5, SC-7, SC-8, AC-2, AC-3, AC-17, AU-2, AU-3, AU-9, AU-12, IR-4, IR-5, SI-4 | Runtime monitoring |
| **Assessment Pipeline (scan-and-map.py, gap-analysis.py)** | CA-2 | Risk classification + assessment |
| **Risk Prioritization (gap-analysis.py)** | RA-2 (supporting) | Severity categorization |

---

## Coverage Summary

- **27 controls** documented across **10 families**
- **FedRAMP Moderate** baseline
- **27 controls, 10 families, FedRAMP Moderate**

---

## Placeholders

Replace `{{EVIDENCE_DIR}}` with the path to your evidence directory (e.g., `evidence/scan-reports`).
Replace `{{STATUS}}` with: Implemented, Partial, Planned, or Not Applicable.
