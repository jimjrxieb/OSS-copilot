# Security Assessment Report (SAR) — {{CLIENT_NAME}}

> **Note:** In FedRAMP, the Security Assessment Report (SAR) is produced by the Third Party Assessment Organization (3PAO). This template provides a self-assessment framework to prepare for the 3PAO engagement. Pre-populate with scan evidence so the assessor can validate.

## Document Control

| Field | Value |
|-------|-------|
| **System** | {{APP_NAME}} |
| **Organization** | {{CLIENT_NAME}} |
| **Assessment Date** | {{DATE}} |
| **Assessor** | {{ASSESSOR_NAME}} (3PAO) |
| **Authorization Type** | FedRAMP Moderate |

---

## 1. Executive Summary

A comprehensive security assessment was conducted on {{CLIENT_NAME}}'s {{APP_NAME}} system. The assessment evaluated {{TOTAL_CONTROLS}} NIST 800-53 Rev 5 controls across {{TOTAL_FAMILIES}} control families against FedRAMP Moderate baseline requirements.

**Key Results**:
- **Controls Assessed**: {{TOTAL_CONTROLS}}
- **Controls Satisfied**: {{SATISFIED_CONTROLS}}
- **Controls Partial**: {{PARTIAL_CONTROLS}}
- **Controls Not Satisfied**: {{NOT_SATISFIED_CONTROLS}}
- **Findings**: {{TOTAL_FINDINGS}} total ({{CRITICAL}} Critical, {{HIGH}} High, {{MEDIUM}} Medium, {{LOW}} Low)
- **Remediated**: {{REMEDIATED_FINDINGS}} ({{REMEDIATION_RATE}}%)

---

## 2. Assessment Scope

### 2.1 Systems Tested
- {{APP_NAME}} application ({{APP_TECHNOLOGY_STACK}})
- Kubernetes cluster deployment manifests
- CI/CD pipeline (GitHub Actions)
- Policy-as-code enforcement (OPA/Kyverno)

### 2.2 Assessment Tools

| Tool | Purpose | Controls |
|------|---------|----------|
| **Trivy** | Container vulnerability scanning | SI-2, CM-8 |
| **Semgrep** | Static application security testing | RA-5 |
| **Gitleaks** | Secret detection | IA-5 |
| **Conftest** | Policy validation (OPA) | CM-6 |
| **Kubescape** | K8s security posture | CM-6, AC-6 |
| **Kyverno** | Admission policy enforcement | AC-6, CM-6 |
| **scan-and-map.py** | NIST 800-53 control mapping | CA-2 |

### 2.3 Assessment Coverage

| File Type | Count | Description |
|-----------|-------|-------------|
| Application source | {{APP_FILE_COUNT}} | {{APP_LANGUAGE}} source files |
| Kubernetes manifests | {{K8S_FILE_COUNT}} | Deployment, service, RBAC, network policy |
| Policies | {{POLICY_FILE_COUNT}} | OPA Rego, Kyverno YAML, Gatekeeper constraints |
| CI/CD workflows | {{WORKFLOW_COUNT}} | GitHub Actions pipelines |

---

## 3. Findings Summary

| Severity | Count | Remediated | Open |
|----------|-------|-----------|------|
| **Critical** | {{CRITICAL}} | {{CRITICAL_REMEDIATED}} | {{CRITICAL_OPEN}} |
| **High** | {{HIGH}} | {{HIGH_REMEDIATED}} | {{HIGH_OPEN}} |
| **Medium** | {{MEDIUM}} | {{MEDIUM_REMEDIATED}} | {{MEDIUM_OPEN}} |
| **Low** | {{LOW}} | {{LOW_REMEDIATED}} | {{LOW_OPEN}} |

### By Remediation Priority

| Priority | Count | Handler | Status |
|----------|-------|---------|--------|
| **E** | {{E_COUNT}} | Auto-remediate | {{E_STATUS}} |
| **D** | {{D_COUNT}} | Auto-remediate + log | {{D_STATUS}} |
| **C** | {{C_COUNT}} | Security review | {{C_STATUS}} |
| **B** | {{B_COUNT}} | Human review | {{B_STATUS}} |
| **S** | {{S_COUNT}} | Executive decision | {{S_STATUS}} |

---

## 4. Detailed Findings

*Reference POA&M (poam-template.md) for individual finding details.*

---

## 5. Remediation Verification

Post-remediation scans were conducted to verify fixes:

| Scan | Pre-Fix Findings | Post-Fix Findings | Status |
|------|-----------------|-------------------|--------|
| Trivy | {{PRE_TRIVY}} | {{POST_TRIVY}} | {{TRIVY_STATUS}} |
| Semgrep | {{PRE_SEMGREP}} | {{POST_SEMGREP}} | {{SEMGREP_STATUS}} |
| Gitleaks | {{PRE_GITLEAKS}} | {{POST_GITLEAKS}} | {{GITLEAKS_STATUS}} |
| Conftest | {{PRE_CONFTEST}} | {{POST_CONFTEST}} | {{CONFTEST_STATUS}} |

---

## 6. Recommendations

1. {{RECOMMENDATION_1}}
2. {{RECOMMENDATION_2}}
3. {{RECOMMENDATION_3}}

---

## 7. Conclusion

Based on the assessment, {{CLIENT_NAME}}'s {{APP_NAME}} system demonstrates {{CONCLUSION_STATEMENT}}.

The continuous monitoring pipeline (GitHub Actions + Falco + admission policies) ensures ongoing compliance verification.

---

*Pre-assessment conducted using the GP-Copilot security platform. Final SAR to be produced by {{ASSESSOR_NAME}} (3PAO).*
