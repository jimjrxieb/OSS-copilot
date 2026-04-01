# System Security Plan (SSP) — {{CLIENT_NAME}}

## Document Control

| Field | Value |
|-------|-------|
| **System Name** | {{APP_NAME}} |
| **Organization** | {{CLIENT_NAME}} |
| **Authorization Type** | FedRAMP Moderate |
| **Date** | {{DATE}} |
| **Prepared By** | {{PREPARED_BY}} |

---

## 1. System Description

{{CLIENT_NAME}} operates {{APP_NAME}}, a {{SYSTEM_DESCRIPTION}}.

See [system-description.md](system-description.md) for full details.

## 2. FIPS 199 Security Categorization

| Impact Area | Level | Justification |
|-------------|-------|---------------|
| **Confidentiality** | Moderate | {{CONFIDENTIALITY_JUSTIFICATION}} |
| **Integrity** | Moderate | {{INTEGRITY_JUSTIFICATION}} |
| **Availability** | Moderate | {{AVAILABILITY_JUSTIFICATION}} |

**Overall System Categorization**: Moderate

## 3. System Interconnections

| System | Type | Direction | Data |
|--------|------|-----------|------|
| {{EXTERNAL_SYSTEM_1}} | {{TYPE}} | {{DIRECTION}} | {{DATA_DESCRIPTION}} |

## 4. Authorization Boundary

See [authorization-boundary.md](authorization-boundary.md).

---

## 5. Control Implementation Summary

27 controls across 10 families.

### Access Control (AC)

| Control | Status | Implementation |
|---------|--------|---------------|
| AC-2 | Implemented | Kubernetes service accounts, RBAC bindings, namespace scoping |
| AC-3 | Implemented | RBAC roles with least-privilege verbs, namespace isolation, NetworkPolicy |
| AC-6 | Implemented | Pod security contexts (runAsNonRoot, drop ALL), PSS labels |
| AC-17 | Implemented | API server RBAC, kubectl audit logging |

See [control-families/AC-access-control.md](control-families/AC-access-control.md).

### Audit and Accountability (AU)

| Control | Status | Implementation |
|---------|--------|---------------|
| AU-2 | Implemented | Kubernetes audit policy, Falco runtime detection, GHA workflow logs |
| AU-3 | Implemented | Structured audit log format (verb, timestamp, sourceIPs, user, objectRef, status) |
| AU-9 | Implemented | RBAC restricts log access, immutable log storage |
| AU-12 | Implemented | Falco DaemonSet + K8s audit policy enabled |

See [control-families/AU-audit.md](control-families/AU-audit.md).

### Security Assessment and Authorization (CA)

| Control | Status | Implementation |
|---------|--------|---------------|
| CA-2 | Implemented | Multi-scanner pipeline (Trivy, Semgrep, Gitleaks, Conftest) + scan-and-map.py classification |
| CA-7 | Implemented | GitHub Actions continuous monitoring + Falco runtime + admission enforcement |

See [control-families/CA-assessment.md](control-families/CA-assessment.md).

### Configuration Management (CM)

| Control | Status | Implementation |
|---------|--------|---------------|
| CM-2 | Implemented | Git-tracked IaC baseline, drift detection |
| CM-6 | Implemented | OPA/Kyverno admission control, Conftest CI checks |
| CM-7 | Implemented | Kyverno blocks privileged containers, Conftest validates minimal images |
| CM-8 | Implemented | Trivy SBOM + Kubernetes API inventory |

See [control-families/CM-config-mgmt.md](control-families/CM-config-mgmt.md).

### Identification and Authentication (IA)

| Control | Status | Implementation |
|---------|--------|---------------|
| IA-2 | Implemented | MFA required, OIDC/SAML federation, K8s RBAC user identity |
| IA-5 | Implemented | Gitleaks secret detection, rotation policies, no hardcoded secrets |

See [control-families/IA-identification.md](control-families/IA-identification.md).

### Incident Response (IR)

| Control | Status | Implementation |
|---------|--------|---------------|
| IR-4 | Implemented | Falco alerts, automated response, documented incident runbooks |
| IR-5 | Implemented | Runtime monitoring via Falco, Prometheus alerting, alert routing |

See [control-families/IR-incident-response.md](control-families/IR-incident-response.md).

### Risk Assessment (RA)

| Control | Status | Implementation |
|---------|--------|---------------|
| RA-2 | Implemented | FIPS 199 categorization documented in SSP |
| RA-5 | Implemented | Multi-scanner pipeline (Trivy, Semgrep, Gitleaks, Conftest) |

See [control-families/RA-risk-assessment.md](control-families/RA-risk-assessment.md).

### System and Services Acquisition (SA)

| Control | Status | Implementation |
|---------|--------|---------------|
| SA-10 | Implemented | Git-tracked IaC, branch protection, Gitleaks pre-commit |
| SA-11 | Implemented | SAST in CI (Semgrep, Trivy), policy validation (Conftest) |

See [control-families/SA-system-acquisition.md](control-families/SA-system-acquisition.md).

### System and Communications Protection (SC)

| Control | Status | Implementation |
|---------|--------|---------------|
| SC-5 | Implemented | Kyverno resource limits, ResourceQuota per namespace |
| SC-7 | Implemented | Default-deny NetworkPolicy, namespace isolation, PSS |
| SC-8 | Implemented | TLS on ingress, mTLS between services (Istio/Linkerd) |
| SC-28 | Implemented | KMS encryption at rest, Sealed Secrets, encrypted PVCs |

See [control-families/SC-system-comms.md](control-families/SC-system-comms.md).

### System and Information Integrity (SI)

| Control | Status | Implementation |
|---------|--------|---------------|
| SI-2 | Implemented | Container image scanning + auto-patch pipeline |
| SI-3 | Implemented | Trivy container scanning, Falco runtime detection |
| SI-4 | Implemented | Falco DaemonSet, Kubescape posture monitoring, Prometheus alerting |

See [control-families/SI-system-integrity.md](control-families/SI-system-integrity.md).

---

## 6. Continuous Monitoring Strategy

- **Coverage**: 27 controls across 10 NIST 800-53 families
- **Frequency**: Security scans on every code push + weekly scheduled scan
- **Runtime**: Falco syscall detection, admission policy enforcement, drift detection
- **Reporting**: Automated NIST control mapping via scan-and-map.py
- **Evidence**: Scan artifacts uploaded to evidence/ directory with timestamps
- **Review**: Monthly control effectiveness review

---

## Appendices

- [Control Matrix](control-matrix-template.md)
- [POA&M](poam-template.md)
- [SAR](sar-template.md)
- [Control Families](control-families/)
