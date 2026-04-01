# FedRAMP Control Families

Detailed control implementations for FedRAMP Moderate baseline. Each file covers one NIST 800-53 Rev 5 control family with specific controls mapped to GP-Copilot tooling.

## Families Documented

| File | Family | Controls Covered |
|------|--------|-----------------|
| `AC-access-control.md` | Access Control | AC-2, AC-3, AC-6, AC-17 |
| `AU-audit.md` | Audit & Accountability | AU-2, AU-3 |
| `CA-assessment.md` | Security Assessment | CA-2, CA-7 |
| `CM-config-mgmt.md` | Configuration Management | CM-2, CM-6, CM-8 |
| `IA-identification.md` | Identification & Auth | IA-5 |
| `RA-risk-assessment.md` | Risk Assessment | RA-5 |
| `SC-system-comms.md` | System & Comms Protection | SC-7, SC-28 |
| `IR-incident-response.md` | Incident Response | IR-4, IR-5 |
| `SA-system-acquisition.md` | System & Services Acquisition | SA-10, SA-11 |
| `SI-system-integrity.md` | System & Info Integrity | SI-2 |

## Placeholders

Replace throughout:
- `{{CLIENT_NAME}}` — Organization name
- `{{APP_NAME}}` — Application name
- `{{NAMESPACE}}` — Kubernetes namespace
- `{{EVIDENCE_DIR}}` — Path to evidence artifacts

## Tool Mapping

| Tool | Primary Controls |
|------|-----------------|
| CI Pipeline (Trivy, Semgrep, Gitleaks, Conftest) | RA-5, SI-2, CM-6, IA-5, SA-10, SA-11 |
| Runtime Monitoring (Falco, Kubescape, kube-bench) | CA-7, SC-7, AC-3, AU-2, IR-4, IR-5, SA-10 |
| Assessment Pipeline (scan-and-map.py, gap-analysis.py) | CA-2, RA-2 (risk classification) |
| Risk Prioritization (gap-analysis.py) | RA-2 (risk categorization) |
