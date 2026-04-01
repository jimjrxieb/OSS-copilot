# AU — Audit and Accountability

## AU-2: Audit Events

**Requirement**: Determine that the information system is capable of auditing defined events.

**Implementation**:
- Kubernetes audit logging enabled with comprehensive audit policy
- API server requests logged: create, update, delete, patch on security-sensitive resources
- Container stdout/stderr captured by cluster logging
- CI/CD workflow logs retained for pipeline audit trail
- Falco generates real-time syscall-level audit events

**Auditable Events**:

| Event | Source | Retention |
|-------|--------|-----------|
| API server requests | K8s audit log | 90 days |
| Pod creation/deletion | K8s events + audit | 90 days |
| Policy violations | OPA/Kyverno admission logs | 90 days |
| Security scan results | CI/CD artifacts | 90 days |
| Syscall anomalies | Falco alerts | 30 days |
| Configuration changes | Git history | Permanent |

**Evidence**:
- `04-remediation/audit-logging.yaml` — Audit policy configuration
- `ci-templates/fedramp-compliance.yml` — CI/CD audit trail
- `{{EVIDENCE_DIR}}/scan-reports/` — Historical scan artifacts

**Tooling**:
- **CI Pipeline**: Validates audit logging is configured in manifests pre-deploy
- **Runtime Monitoring**: Monitors that audit logs are flowing at runtime
- **Assessment Pipeline**: Aggregates findings for AU control evidence

---

## AU-3: Content of Audit Records

**Requirement**: Audit records contain information about what type of event occurred, when it occurred, where it occurred, the source, the outcome, and the identity of individuals/subjects.

**Implementation**:
- Kubernetes audit log format includes:
  - `verb` (what): create, update, delete, patch
  - `requestReceivedTimestamp` (when): ISO 8601 timestamp
  - `sourceIPs` (where/who): Client IP address
  - `user.username` (identity): Authenticated user/SA
  - `objectRef` (what resource): Namespace, resource, name
  - `responseStatus.code` (outcome): Success/failure code
- Falco alerts include: rule name, priority, output fields, container info, process details

**Evidence**:
- `04-remediation/audit-logging.yaml` — Audit policy defining captured fields
- `{{EVIDENCE_DIR}}/audit-logs/` — Sample audit log entries

---

## AU-9: Protection of Audit Information

**Requirement**: Protect audit information and audit logging tools from unauthorized access, modification, and deletion.

**Implementation**:
- RBAC: dedicated `audit-log-reader` Role scoped to security team only
- No application workloads have access to log namespaces
- Immutable storage: audit logs shipped to S3 with Object Lock (WORM compliance)
- CloudWatch Logs with resource-based policy restricting delete operations
- Separate logging namespace with its own NetworkPolicy (no ingress from app namespaces)

**Evidence**:
- `04-remediation/audit-logging.yaml` — RBAC for log access
- `backend/remediation/audit-logging.md` — Implementation guide
- `{{EVIDENCE_DIR}}/log-rbac-policy.json` — RBAC dump for logging namespace
- S3 Object Lock configuration screenshots

**Tooling**:
- **Runtime Monitoring**: Monitors RBAC changes affecting log access
- **Assessment Pipeline**: Alerts on any modification to audit log storage configuration

---

## AU-12: Audit Record Generation

**Requirement**: Provide audit record generation capability for auditable events. Allow authorized personnel to select events for auditing.

**Implementation**:
- Kubernetes API server audit policy captures: authentication, RBAC changes, secret access, pod exec
- Falco DaemonSet generates runtime audit events at syscall level
- Application-level structured logging (JSON format) for security events
- CI/CD pipeline logs captured as workflow artifacts with timestamps
- Configurable audit verbosity per resource type (Metadata vs RequestResponse)

**Evidence**:
- `04-remediation/audit-logging.yaml` — K8s audit policy configuration
- Falco deployment manifests and rule sets
- `{{EVIDENCE_DIR}}/audit-logs/` — Sample audit log entries
- `ci-templates/fedramp-compliance.yml` — Pipeline audit trail

**Tooling**:
- **Runtime Monitoring**: Validates Falco is running and generating events
- **CI Pipeline**: Validates audit policy exists in manifests pre-deploy
