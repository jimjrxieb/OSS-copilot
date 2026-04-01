# 10 — Deploy Dev

> Deploy to dev so hardened code runs in a real cluster.

This validates that your security fixes actually work at runtime — not just in YAML linting. If securityContext blocks the app, better to find out in dev than in staging.

This is the last step in application hardening. After this, the platform hardening package (02-platform-hardening) takes over for cluster-level controls.

---

## What You Need

- Playbooks 00-09 completed
- `kubectl` configured to reach a dev cluster
- `helm` v3.12+ installed
- Container images built and pushed to a registry
- Dev namespace exists or you can create one

```bash
kubectl cluster-info
helm version --short
```

---

## Step 1: Confirm You're on the Dev Cluster

```bash
# Double-check the context — NOT staging or prod
kubectl config current-context

# Verify or create namespace
kubectl get ns dev 2>/dev/null || kubectl create ns dev
```

---

## Step 2: Prepare Helm Values

```bash
cd $TARGET_DIR

# Use the dev values template
cp ../../MSSP/01-application-hardening/tools/helm-values-dev.yaml helm/values-dev.yaml
```

**Review and customize:**

| Field | Dev Default | Why |
|-------|------------|-----|
| `replicaCount` | 1 | Save resources in dev |
| `image.tag` | `dev-latest` | Tracks dev branch builds |
| `resources.limits.cpu` | `500m` | Enough for testing |
| `resources.limits.memory` | `512Mi` | Enough for testing |
| `securityContext.runAsNonRoot` | `true` | Must match prod |
| `securityContext.readOnlyRootFilesystem` | `true` | Must match prod |
| `ingress.enabled` | `false` | Port-forward for dev |
| `autoscaling.enabled` | `false` | No HPA in dev |

---

## Step 3: Lint and Scan

```bash
# Lint
helm lint helm/ -f helm/values-dev.yaml

# Render and scan the manifests
helm template my-app helm/ -f helm/values-dev.yaml --namespace dev > /tmp/dev-rendered.yaml
checkov -f /tmp/dev-rendered.yaml --framework kubernetes
kubescape scan /tmp/dev-rendered.yaml --format pretty-printer
```

Fix any findings before deploying.

---

## Step 4: Deploy

```bash
# Dry-run first — always
helm upgrade --install my-app helm/ \
  -f helm/values-dev.yaml \
  --namespace dev \
  --create-namespace \
  --dry-run

# Deploy
helm upgrade --install my-app helm/ \
  -f helm/values-dev.yaml \
  --namespace dev \
  --create-namespace \
  --wait \
  --timeout 5m
```

---

## Step 5: Verify

```bash
# Pods running?
kubectl get pods -n dev

# Security context applied?
kubectl get pods -n dev -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext}{"\n"}{end}'

# Ready?
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=my-app -n dev --timeout=120s

# No :latest tags?
kubectl get pods -n dev -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | grep -E ':latest$' && echo "FAIL" || echo "PASS"
```

---

## Step 6: Smoke Test

```bash
kubectl port-forward svc/my-app 8080:80 -n dev &
curl -sf http://localhost:8080/healthz && echo "HEALTHY" || echo "UNHEALTHY"
kill %1
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `CrashLoopBackOff` | `readOnlyRootFilesystem` blocks writes | Add `emptyDir` volumes for `/tmp`, `/var/cache` |
| `CreateContainerConfigError` | Missing secrets/configmaps | Create them: `kubectl create secret generic <name> -n dev --from-file=...` |
| `ImagePullBackOff` | Registry auth missing | Create imagePullSecret |
| Health probe fails | Wrong port or path | Check `livenessProbe.httpGet.path` and `port` |
| `FailedScheduling` | Resource requests > node capacity | Lower requests in values-dev.yaml |

---

## Rollback

```bash
helm history my-app -n dev
helm rollback my-app <revision> -n dev --wait

# Nuclear option
helm uninstall my-app -n dev
```

---

## What's Next

Application hardening is done. Your code is scanned, fixed, gated, and deployed to dev.

Next packages:
- **02-platform-hardening** — Kyverno, RBAC, admission control, CIS benchmarks
- **03-runtime-security** — Falco, watchers, detection, response
