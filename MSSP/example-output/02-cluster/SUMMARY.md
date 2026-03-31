# 02-Cluster — Pre-Deploy Audit Results

> Static manifest analysis of Portfolio's Kubernetes infrastructure.
> No cluster access needed — scanned Helm templates, kubectl manifests, RBAC, and OPA policies.

---

## Scores

| Tool | What It Scanned | Result |
|------|----------------|--------|
| **Polaris** | Helm chart templates | **100/100** — all best practices passing |
| **Checkov** | Rendered Helm manifests (597 lines YAML) | **256 PASS / 16 FAIL** (94% pass rate) |
| **Checkov** | Raw kubectl manifests (method1-simple-kubectl/) | **269 PASS / 6 FAIL** (98% pass rate) |
| **Conftest** | Rendered Helm vs Portfolio's OPA policies | **0 failures, 0 warnings** |
| **RBAC** | roles.yaml + service-accounts.yaml | **No wildcards, automount disabled** |

---

## Why Polaris Is 100/100

Every deployment in the Helm chart has:
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: ["ALL"]`
- CPU and memory requests + limits
- Liveness and readiness probes
- No `hostNetwork`, `hostPID`, `hostIPC`
- No privileged containers

This is the result of a prior hardening engagement. A fresh, unhardened project
typically scores 40-65.

---

## Checkov Findings — Rendered Helm (16 failures)

### Namespace Artifacts (6 findings — not real in production)

| Check | Count | Why It's Noise |
|-------|-------|---------------|
| CKV_K8S_21: Default namespace | 6 | `helm template` renders without namespace. `helm install -n portfolio` deploys correctly. |

### Real Findings (10 — low priority)

| Check | What It Means | Resources | Fix |
|-------|--------------|-----------|-----|
| **CKV_K8S_43** | Image should use digest | api, chroma, ui | Pin `image: repo@sha256:...` instead of `:tag` |
| **CKV_K8S_40** | Run as high UID (>10000) | api, chroma, ui | Set `runAsUser: 10000` to avoid host UID conflicts |
| **CKV_K8S_35** | Prefer secrets as files | api | Mount secrets as volumes, not env vars |
| **CKV_K8S_25** | Minimize added capabilities | chroma | Review `capabilities.add` or remove |
| **CKV_K8S_15** | Image pull policy Always | chroma | Set `imagePullPolicy: Always` |

**None of these are critical.** They're polish — supply chain hardening (digests),
defense-in-depth (high UIDs), and best practices (secrets as files).

---

## Checkov Findings — Raw kubectl Manifests (6 failures)

| Check | Resources |
|-------|-----------|
| CKV_K8S_35 | api — secrets as env vars |
| CKV_K8S_43 | api, ui — missing image digests |
| CKV2_K8S_6 | api, chroma, ui — NetworkPolicy not default-deny |

Fewer findings than the Helm chart — these manifests were hardened during
the cluster hardening engagement.

---

## Conftest — Clean

Portfolio's own OPA policies (`policies/conftest/`) found 0 violations:
- `kubernetes.rego` — pod security, resource limits
- `image-security.rego` — image tag, pull policy
- `secrets-management.rego` — secret handling
- `cicd-security.rego` — pipeline security
- `gateway-api.rego` — gateway configuration
- `03-prohibit-insecure-services.rego` — service exposure
- `05-require-resource-limits.rego` — resource enforcement

The manifests pass every policy the project defined for itself.

---

## RBAC — Clean

| Check | Result |
|-------|--------|
| Wildcard verbs | None — `app-role` has get/list only |
| Wildcard resources | None — scoped to configmaps, secrets, pods |
| automountServiceAccountToken | `false` — pods can't access K8s API |

---

## Key Lesson: Helm Templates Need Rendering

Checkov and Conftest cannot parse raw Helm templates (`{{ .Values.x }}`).
You must render first:

```bash
# Render Helm chart to plain YAML
helm template my-release ./charts/my-chart/ > rendered.yaml

# Then scan the rendered output
checkov --file rendered.yaml --framework kubernetes
conftest test rendered.yaml --policy ./policies/
polaris audit --audit-path rendered.yaml
```

Without this step, Checkov returns 0 findings (not because the chart is clean,
but because it can't parse the templates).

---

## Output Files

| File | Tool | What's In It |
|------|------|-------------|
| `polaris-static.json` | Polaris | Best practices audit (100/100) |
| `results_json.json` | Checkov | 256 pass / 16 fail with check details |
| `conftest-results.json` | Conftest | 0 failures (empty — clean) |
| `rendered-manifests.yaml` | Helm template | 597 lines of rendered K8s YAML |
