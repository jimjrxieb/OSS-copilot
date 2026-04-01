# 04 — Verify Container Hardening

> Run a final check on all containers before the application deploys. This is the gate.

01-application-hardening fixed the YAML. 02-platform-hardening hardened the cluster. This playbook verifies that every running container actually meets the security bar — at runtime, not just in config files.

---

## What You Need

- Playbooks 00-03 completed (runtime tools deployed)
- Application containers built and available in the registry

---

## Step 1: Run the Verifier

```bash
bash tools/verify-container-hardening.sh --namespace <namespace>
```

**What it checks (15 controls):**

| # | Control | What It Looks For |
|---|---------|-------------------|
| 1 | Non-root user | Container runs as non-root UID |
| 2 | Read-only rootfs | `readOnlyRootFilesystem: true` |
| 3 | No privilege escalation | `allowPrivilegeEscalation: false` |
| 4 | Drop ALL capabilities | `capabilities.drop: ["ALL"]` |
| 5 | Seccomp profile | RuntimeDefault or Localhost profile |
| 6 | Resource limits | CPU and memory limits set |
| 7 | Resource requests | CPU and memory requests set |
| 8 | Liveness probe | Probe configured |
| 9 | Readiness probe | Probe configured |
| 10 | Image tag | Not `:latest` |
| 11 | Image pull policy | `Always` |
| 12 | SA token disabled | `automountServiceAccountToken: false` |
| 13 | No host namespaces | hostNetwork/hostPID/hostIPC all false |
| 14 | No privileged mode | `privileged: false` |
| 15 | No dangerous capabilities | No SYS_ADMIN, NET_ADMIN, etc. |

---

## Step 2: Review Results

```
Container Hardening Report — namespace: app
================================================
  [PASS] non-root-user          api-server (uid=10001)
  [PASS] readonly-rootfs        api-server
  [FAIL] resource-limits        worker (no memory limit)
  [PASS] seccomp-profile        api-server (RuntimeDefault)
  [FAIL] liveness-probe         worker (not configured)
================================================
Score: 13/15 (87%)
```

---

## Step 3: Fix Failures

The verifier outputs fix hints:

```bash
bash tools/verify-container-hardening.sh --namespace <namespace> --fix-hints
```

Example output:
```
FAIL: worker — missing memory limit
  FIX: Add to container spec:
    resources:
      limits:
        memory: "512Mi"
```

Fix in git (not kubectl) if the resources are managed by ArgoCD or Helm.

---

## Step 4: Skip System Containers

System containers (kube-proxy, CoreDNS, Falco) have legitimate reasons to run privileged:

```bash
bash tools/verify-container-hardening.sh --namespace <namespace> --skip-system
```

---

## Step 5: Re-verify Until Clean

```bash
# Loop until 100% on app containers
bash tools/verify-container-hardening.sh --namespace app --skip-system
# Target: 15/15 on every application container
```

---

## The Gate

This is the last check before deploying. If containers don't pass here, they don't deploy. The same controls are enforced by:
- **Kyverno** (02-platform-hardening) at admission time
- **Falco** (this package) at runtime

This verifier catches anything that slipped through.

---

## Next Step

Go to [05-deploy-application.md](05-deploy-application.md) to deploy the application via ArgoCD.
