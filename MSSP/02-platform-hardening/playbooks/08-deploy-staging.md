# 08 — Deploy Staging

> Deploy to staging with full security validation. If it passes here, it's ready for production.

Dev deployment (01-application-hardening playbook 10) proved the app runs. Staging deployment proves it runs securely — with admission control, NetworkPolicies, PSS enforcement, and proper RBAC all active.

---

## What You Need

- Playbooks 00-07 completed (cluster hardened, policies enforced, CI gated)
- `kubectl` and `helm` access
- Container images built and pushed

---

## Step 1: Pre-Flight Check

```bash
bash tools/pre-flight-check.sh
```

Verifies:
- Kyverno is running and policies are in enforce mode
- PSS labels are applied to the staging namespace
- NetworkPolicies exist
- RBAC is scoped (no unnecessary cluster-admin)

---

## Step 2: Create Staging Namespace

```bash
kubectl create namespace staging --dry-run=client -o yaml | \
  kubectl label --local -f - \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/warn=restricted \
    -o yaml | kubectl apply -f -
```

---

## Step 3: Prepare Helm Values

```bash
cd $TARGET_DIR
cp ../../MSSP/02-platform-hardening/tools/helm-values-staging.yaml helm/values-staging.yaml
```

**Staging values differ from dev:**

| Field | Dev | Staging | Why |
|-------|-----|---------|-----|
| `replicaCount` | 1 | 2 | Test HA |
| `resources` | low | prod-equivalent | Test real limits |
| `ingress.enabled` | false | true | Test real routing |
| `securityContext` | same | same | Must match prod |

---

## Step 4: Lint and Scan Before Deploy

```bash
# Render manifests
helm template my-app helm/ -f helm/values-staging.yaml --namespace staging > /tmp/staging-rendered.yaml

# Scan with Checkov
checkov -f /tmp/staging-rendered.yaml --framework kubernetes

# Scan with Kubescape
kubescape scan /tmp/staging-rendered.yaml --format pretty-printer

# Run Conftest policies
conftest test /tmp/staging-rendered.yaml --policy policy/
```

Fix any findings before deploying.

---

## Step 5: Deploy

```bash
# Dry-run first
helm upgrade --install my-app helm/ \
  -f helm/values-staging.yaml \
  --namespace staging \
  --dry-run

# Deploy
helm upgrade --install my-app helm/ \
  -f helm/values-staging.yaml \
  --namespace staging \
  --wait \
  --timeout 5m
```

---

## Step 6: Verify Security Posture

```bash
# Pods running with correct security context?
kubectl get pods -n staging -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext}{"\n"}{end}'

# No :latest tags?
kubectl get pods -n staging -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | grep -E ':latest$' && echo "FAIL" || echo "PASS"

# Resource limits set?
kubectl get pods -n staging -o jsonpath='{range .items[*].spec.containers[*]}{.name}{"\tCPU:"}{.resources.limits.cpu}{"\tMEM:"}{.resources.limits.memory}{"\n"}{end}'

# NetworkPolicy applied?
kubectl get networkpolicy -n staging

# SA tokens disabled?
kubectl get pods -n staging -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.automountServiceAccountToken}{"\n"}{end}'
```

---

## Step 7: Smoke Test

```bash
kubectl port-forward svc/my-app 8080:80 -n staging &
curl -sf http://localhost:8080/healthz && echo "HEALTHY" || echo "UNHEALTHY"
kill %1
```

---

## Rollback

```bash
helm history my-app -n staging
helm rollback my-app <revision> -n staging --wait
```

---

## Next Step

Go to [09-compliance-report.md](09-compliance-report.md) to produce the evidence.
