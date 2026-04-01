# AC — Access Control

## AC-2: Account Management

**Requirement**: Manage information system accounts including establishing, activating, modifying, reviewing, disabling, and removing accounts.

**Implementation**:
- Kubernetes ServiceAccount per application (no default SA usage)
- RBAC RoleBindings scoped to specific namespaces
- `automountServiceAccountToken: false` by default
- Separate roles for read-only monitoring vs deployment operations

**Evidence**:
- `04-remediation/rbac.yaml` — RBAC configuration
- `{{EVIDENCE_DIR}}/rbac-state.json` — Cluster RBAC dump

**Tooling**:
- **Runtime Monitoring**: Monitors RBAC changes at runtime, alerts on privilege escalation
- **CI Pipeline**: Validates RBAC manifests pre-deploy against least-privilege policies

---

## AC-3: Access Enforcement

**Requirement**: Enforce approved authorizations for logical access to information and system resources.

**Implementation**:
- Kubernetes RBAC enforces verb-level access (get, list, create, update, delete)
- Namespace isolation prevents cross-tenant access
- NetworkPolicy enforces network-level access controls (SC-7 supporting AC-3)
- No wildcard verbs (`*`) in any role definition

**Evidence**:
- `04-remediation/rbac.yaml` — Role definitions
- `04-remediation/networkpolicy.yaml` — Network access controls
- `policies/conftest/fedramp-controls.rego` — Policy validation for wildcard verbs

---

## AC-6: Least Privilege

**Requirement**: Employ the principle of least privilege, allowing only authorized accesses that are necessary.

**Implementation**:
- Pod Security Contexts: `runAsNonRoot: true`, `runAsUser: {{RUN_AS_USER}}`
- Capabilities: `drop: ["ALL"]`, add back only what's required
- `allowPrivilegeEscalation: false` on all containers
- PSS labels: enforce baseline, warn restricted
- Kyverno/Gatekeeper admission policies enforce these at deploy time

**Evidence**:
- `04-remediation/deployment.yaml` — Security context configuration
- `policies/kyverno/` — Admission enforcement policies
- `policies/gatekeeper/fedramp-constraints.yaml` — OPA constraints
- `04-remediation/pod-security-context.yaml` — Security context templates

---

## AC-17: Remote Access

**Requirement**: Establish usage restrictions, configuration/connection requirements, and implementation guidance for remote access.

**Implementation**:
- Kubernetes API server access controlled via RBAC
- kubectl operations logged via audit policy (AU-2)
- No direct SSH to cluster nodes; all access via kubectl with identity
- API server access audit captures: user, sourceIP, verb, resource

**Evidence**:
- `04-remediation/audit-logging.yaml` — Audit policy configuration
- `{{EVIDENCE_DIR}}/audit-logs/` — API server audit trail
