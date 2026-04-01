# SC — System and Communications Protection

## SC-5: Denial of Service Protection

**Requirement**: Protect against or limit the effects of denial of service attacks.

**Implementation**:
- Kubernetes resource limits: every container has CPU/memory requests and limits
- ResourceQuota per namespace: caps total resource consumption
- LimitRange per namespace: sets default limits for pods without explicit values
- HorizontalPodAutoscaler for critical services
- PodDisruptionBudget ensures minimum availability during voluntary disruptions
- Kyverno policy enforces resource limits on all new deployments

**Evidence**:
- `policies/kyverno/require-resource-limits.yaml` — Admission enforcement
- `backend/remediation/resource-limits.md` — Implementation guide
- `{{EVIDENCE_DIR}}/resource-quotas.json` — Namespace quota configuration
- `04-remediation/deployment.yaml` — Hardened deployment with limits

**Tooling**:
- **Runtime Monitoring**: Monitors resource utilization, alerts on quota exhaustion
- **CI Pipeline**: Validates resource limits in manifests pre-deploy (E-rank auto-fix)

---

## SC-7: Boundary Protection

**Requirement**: Monitor and control communications at the external boundary of the system and at key internal boundaries within the system.

**Implementation**:
- **Kubernetes NetworkPolicy**: Default deny all ingress/egress, explicit allow for required flows
- **Namespace Isolation**: Application deployed in dedicated namespace with PSS labels
- **Ingress Control**: Only application port exposed via Service, no host networking
- **Egress Control**: Only database egress allowed from application pods
- **Kyverno Policy**: Enforces NetworkPolicy existence for all namespaces

**Network Flow Rules** (customize per client):

| Source | Destination | Port | Action |
|--------|-------------|------|--------|
| External | {{APP_NAME}} Service | {{APP_PORT}}/TCP | Allow |
| {{APP_NAME}} Pod | {{DB_NAME}} Pod | {{DB_PORT}}/TCP | Allow |
| {{APP_NAME}} Pod | DNS | 53/UDP | Allow |
| Any | Any | * | Deny (default) |

**Evidence**:
- `04-remediation/networkpolicy.yaml` — NetworkPolicy manifests
- `04-remediation/network-policies.yaml` — Network policy templates
- `policies/conftest/fedramp-controls.rego` — Policy validation

**Tooling**:
- **CI Pipeline**: Validates NetworkPolicy exists in manifests pre-deploy
- **Runtime Monitoring**: Monitors network flows, detects policy gaps at runtime

---

## SC-8: Transmission Confidentiality and Integrity

**Requirement**: Implement cryptographic mechanisms to prevent unauthorized disclosure of information and detect changes to information during transmission.

**Implementation**:
- TLS termination at ingress controller (cert-manager with Let's Encrypt or private CA)
- mTLS between services via service mesh (Istio or Linkerd)
- All database connections require TLS (`sslmode=verify-full`)
- No plaintext HTTP endpoints in production (HSTS enforced)
- Certificate rotation automated via cert-manager

**Evidence**:
- `04-remediation/network-policies.yaml` — Network security templates
- `frontend/remediation/secure-headers.md` — HSTS and TLS configuration
- Ingress TLS configuration (cert-manager certificates)
- `{{EVIDENCE_DIR}}/tls-config/` — Certificate inventory, mTLS mesh configuration
- Service mesh configuration screenshots

**Tooling**:
- **Runtime Monitoring**: Monitors certificate expiration, validates mTLS is active
- **CI Pipeline**: Checkov/Conftest validate TLS configuration in IaC

---

## SC-28: Protection of Information at Rest

**Requirement**: Protect the confidentiality and integrity of information at rest.

**Implementation**:
- **Database**: Data volume encrypted via storage class (e.g., EBS encryption on AWS)
- **Kubernetes Secrets**: Stored encrypted in etcd (encryption-at-rest configuration)
- **Container Images**: Stored in authenticated registry
- **Evidence Files**: Stored in Git (integrity via SHA hashes)

**Status**: Implementation depends on infrastructure provider configuration.

**Evidence**:
- `04-remediation/deployment.yaml` — Volume configuration
- Infrastructure provider documentation for encryption settings
