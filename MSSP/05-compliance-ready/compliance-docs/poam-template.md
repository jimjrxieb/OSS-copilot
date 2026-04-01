# Plan of Action & Milestones (POA&M) — {{CLIENT_NAME}}

## Document Control

| Field | Value |
|-------|-------|
| **System** | {{APP_NAME}} |
| **Organization** | {{CLIENT_NAME}} |
| **Date** | {{DATE}} |
| **Prepared By** | {{PREPARED_BY}} |

---

## Finding Template

| Field | Description |
|-------|-------------|
| **ID** | POAM-NNNN |
| **Title** | Brief description of the finding |
| **Control** | NIST 800-53 control (e.g., RA-5) |
| **Source** | Scanner that found it (Trivy, Semgrep, etc.) |
| **Priority** | Remediation priority (E/D/C/B/S) |
| **Severity** | FedRAMP severity (Critical / High / Medium / Low) |
| **Status** | OPEN / IN-PROGRESS / CLOSED |
| **Detected** | Date first identified |
| **Milestone** | Target remediation date |
| **Closed** | Date resolved (if applicable) |
| **Remediation** | What was done to fix it |
| **Evidence** | Path to evidence artifact |

---

## SLA by Priority

| Priority | Target Remediation | Automation Level |
|------|-------------------|-----------------|
| **E** | Immediate | Auto-fix, no approval |
| **D** | < 24 hours | Auto-fix with logging |
| **C** | < 72 hours | Security review approval |
| **B** | < 7 days | Human review required |
| **S** | Risk-based | Executive decision |

## FedRAMP Remediation Timelines

| Severity | FedRAMP SLA | Priority |
|----------|-------------|-----------------|
| Critical | 30 days | B / S |
| High | 30 days | C / B |
| Medium | 90 days | D |
| Low | 180 days | E |

> The priority system maps to FedRAMP severity levels. When reporting to 3PAO, use the FedRAMP severity column. The priority column is for internal automation routing.

---

## Findings

### POAM-0001: {{FINDING_TITLE}}

| Field | Value |
|-------|-------|
| **Control** | {{NIST_CONTROL}} |
| **Source** | {{SCANNER}} |
| **Priority** | {{RANK}} |
| **Status** | OPEN |
| **Detected** | {{DATE}} |
| **Milestone** | {{TARGET_DATE}} |
| **Remediation** | {{REMEDIATION_DESCRIPTION}} |
| **Evidence** | `evidence/scan-reports/{{EVIDENCE_FILE}}` |

---

*Add additional findings following the same format.*
