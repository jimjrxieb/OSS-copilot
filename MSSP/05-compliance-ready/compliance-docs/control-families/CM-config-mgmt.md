# CM — Configuration Management

## CM-2: Baseline Configuration

**Requirement**: Develop, document, and maintain a current baseline configuration of the information system.

**Implementation**:
- All Kubernetes manifests tracked in Git — Git history IS the baseline
- `04-remediation/` contains the declared-state manifests (deployment, service, networkpolicy, rbac, namespace)
- Any drift from declared state detected by Kubescape
- Infrastructure changes require PR review + CI security scan pass before merge

**Evidence**:
- `04-remediation/` — Baseline Kubernetes manifests
- Git history — Full change audit trail
- `ci-templates/fedramp-compliance.yml` — Gate that validates baseline before merge

**Tooling**:
- **CI Pipeline**: Validates manifests against baseline before deployment
- **Runtime Monitoring**: Detects runtime drift from baseline

---

## CM-6: Configuration Settings

**Requirement**: Establish and document configuration settings for IT products using security configuration checklists.

**Implementation**:
- OPA/Gatekeeper constraints enforce security configuration requirements at admission
- Kyverno ClusterPolicies enforce pod security, resource limits, image policies
- Conftest validates configuration settings in CI before deployment

**Configuration Requirements Enforced**:

| Setting | Policy | Tool |
|---------|--------|------|
| Non-root containers | `require-run-as-nonroot` | Kyverno |
| Drop all capabilities | `require-drop-all` | Kyverno |
| Resource limits | `require-resource-limits` | Kyverno |
| Trusted registries | `restrict-image-registries` | Kyverno |
| No privilege escalation | `disallow-privilege-escalation` | Kyverno |
| No host networking | `disallow-host-namespaces` | Conftest |
| Read-only rootfs | recommended | Conftest (warn) |

**Evidence**:
- `policies/kyverno/` — ClusterPolicy definitions
- `policies/conftest/fedramp-controls.rego` — CI-time configuration checks
- `policies/gatekeeper/` — Admission constraints

---

## CM-7: Least Functionality

**Requirement**: Configure the system to provide only essential capabilities. Prohibit or restrict the use of functions, ports, protocols, and/or services.

**Implementation**:
- Kyverno policies block privileged containers and unnecessary capabilities
- Conftest validates minimal base images (no package managers in production)
- Pod Security Standards (PSS) Restricted profile enforced via namespace labels
- NetworkPolicy restricts ports to only those required by each service
- No hostNetwork, hostPID, or hostIPC allowed on application pods
- Container images use multi-stage builds — build tools removed from production

**Evidence**:
- `policies/kyverno/disallow-privileged.yaml` — Block privileged containers
- `policies/kyverno/require-drop-all.yaml` — Drop all Linux capabilities
- `policies/conftest/fedramp-controls.rego` — CI-time policy checks
- `backend/remediation/container-hardening.md` — Minimal image guide
- `04-remediation/deployment.yaml` — Hardened deployment manifest

**Tooling**:
- **CI Pipeline**: Validates manifests and Dockerfiles for unnecessary functionality pre-deploy
- **Runtime Monitoring**: Detects containers with excess capabilities at runtime

---

## CM-8: Information System Component Inventory

**Requirement**: Develop and document an inventory of information system components.

**Implementation**:
- Kubernetes API provides real-time component inventory (pods, services, deployments, configmaps, secrets)
- Container images tracked with Trivy scan results (SBOM generation)
- `scan-and-map.py` enumerates components and maps to NIST controls
- Git tracks all infrastructure-as-code components

**Evidence**:
- `tools/scan-and-map.py` — Component enumeration
- `{{EVIDENCE_DIR}}/sbom.json` — Container image inventory (CycloneDX)
- `04-remediation/` — Declared component manifests
