# OSS-Copilot Pre-Deploy Cluster Audit — Portfolio

**Target:** GP-PROJECTS/02-instance/slot-3/Portfolio
**Date:** 2026-03-30
**Mode:** Pre-deploy (static manifest analysis — no cluster needed)
**Tools:** Polaris, Checkov, Conftest, RBAC static review

---

## Scores

| Tool | Target | Result |
|------|--------|--------|
| **Polaris** | Helm templates | **100/100** — all best practices passing |
| **Checkov** | Rendered Helm manifests | **256 PASS / 16 FAIL** (94% pass rate) |
| **Checkov** | Raw kubectl manifests | **269 PASS / 6 FAIL** (98% pass rate) |
| **Conftest** | Rendered Helm vs OPA policies | **0 failures, 0 warnings** — clean |
| **RBAC** | Static review | **No wildcards, automount=false** — clean |

---

## Checkov Findings — Rendered Helm Chart (16 failures)

| Check | Finding | Resources | Severity | Fix |
|-------|---------|-----------|----------|-----|
| **CKV_K8S_21** | Default namespace should not be used | 6 resources (SA, Services, Deployments) | Medium | Set `namespace:` in Helm values or `helm install -n portfolio` |
| **CKV_K8S_43** | Image should use digest | 3 Deployments (api, chroma, ui) | Medium | Pin `image: repo@sha256:abc...` instead of `:tag` |
| **CKV_K8S_40** | Containers should run as high UID | 3 Deployments | Low | Set `runAsUser: 10000` (high UID avoids host conflict) |
| **CKV_K8S_35** | Prefer secrets as files over env vars | 1 Deployment (api) | Low | Mount secrets as volumes instead of `env.valueFrom.secretKeyRef` |
| **CKV_K8S_25** | Minimize added capabilities | 1 Deployment (chroma) | Medium | Remove `capabilities.add` or justify |
| **CKV_K8S_15** | Image pull policy should be Always | 1 Deployment (chroma) | Low | Set `imagePullPolicy: Always` |

### Analysis:

**6 of 16** are the same finding (CKV_K8S_21 — default namespace). This is a Helm
rendering artifact — `helm template` renders without a namespace, but `helm install -n portfolio`
deploys to the right namespace. **Not a real finding in production.**

**3 of 16** are image digest pinning (CKV_K8S_43). This is best practice for supply
chain security but requires a SHA digest workflow. **Real finding, medium priority.**

**Remaining 7** are legitimate hardening gaps — high UID, secrets as env vars, added
capabilities, pull policy. **Real findings, low priority.**

---

## Checkov Findings — Raw kubectl Manifests (6 failures)

| Check | Finding | Resources |
|-------|---------|-----------|
| **CKV_K8S_35** | Prefer secrets as files over env vars | api Deployment |
| **CKV_K8S_43** | Image should use digest | api + ui Deployments |
| **CKV2_K8S_6** | Ensure NetworkPolicy deny by default | api, chroma, ui Pods |

The raw kubectl manifests have **fewer** findings than the Helm chart because they
were hardened during the 02-CLUSTER-HARDEN engagement (March 2026).

---

## Conftest OPA Policy Check — CLEAN

Portfolio's own Rego policies (`policies/conftest/`) found **0 violations** against
the rendered Helm manifests. This means the manifests comply with:
- cicd-security.rego
- image-security.rego
- secrets-management.rego
- kubernetes.rego
- gateway-api.rego
- prohibit-insecure-services.rego
- require-resource-limits.rego

---

## RBAC Static Audit — CLEAN

| Check | Result |
|-------|--------|
| Wildcard verbs in roles | **None** — `app-role` only has get/list |
| Wildcard resources | **None** — scoped to configmaps, secrets, pods |
| Service account automount | **Disabled** — `automountServiceAccountToken: false` |

RBAC is properly scoped. No cluster-admin bindings in the static manifests.

---

## Polaris Static Audit — PERFECT SCORE

Polaris **100/100** on the Helm chart templates means all of these are present:
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: ["ALL"]`
- Resource requests and limits
- Liveness and readiness probes
- No `hostNetwork`, `hostPID`, `hostIPC`
- No privileged containers

---

## Pre-Deploy vs. Enterprise Comparison

| What We Ran | Enterprise Equivalent | Cost | Same Result? |
|-------------|----------------------|------|-------------|
| Polaris (static) | Wiz K8s scan | $100-400K/yr | Yes — same best practice checks |
| Checkov (rendered Helm) | Prisma Cloud IaC | $100-400K/yr | Yes — same CKV checks |
| Conftest (OPA policies) | Styra DAS | $50-150K/yr | Yes — same Rego engine |
| RBAC static review | Teleport RBAC | $30-100K/yr | Partial — no session recording |

**Total enterprise cost for equivalent pre-deploy coverage: $280K-$1.05M/yr**
**OSS-Copilot cost: $0**

---

## What Pre-Deploy Doesn't Catch

These require a live cluster (runtime phase):
- CIS benchmarks against running nodes (kube-bench)
- Actual RBAC bindings vs. what's in git (drift)
- Runtime behavior (Falco — see 03-container)
- NetworkPolicy enforcement validation
- Pod Security Standards enforcement status
- Attack path analysis (Wiz — no OSS equivalent)

---

## Summary

Portfolio is in excellent shape for pre-deploy:
- **Polaris 100/100** — all security contexts, probes, limits present
- **Conftest 0 violations** — passes its own OPA policies
- **RBAC clean** — scoped roles, automount disabled
- **16 Checkov findings** — 6 are namespace artifacts, 3 are digest pinning, 7 are low-priority hardening

The 02-CLUSTER-HARDEN engagement already hardened this project. What's left is
polish (image digests, high UIDs, secrets-as-files) — not critical gaps.
