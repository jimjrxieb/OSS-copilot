# 02 — Deploy Admission Control

> Deploy Kyverno so bad deployments get blocked at the API server.

Playbook 01 fixed what was broken. Kyverno prevents it from coming back. Every `kubectl apply` and every Helm install gets validated against your policies before the resource is created.

In production, tools like Styra DAS and Nirmata handle this. This is your staging version — same Kyverno engine, same policies.

---

## What You Need

- Playbook 01 completed (cluster fixes applied)
- Helm v3+ installed

---

## Step 1: Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set admissionController.replicas=1 \
  --set backgroundController.replicas=1
```

Wait for it to be ready:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=kyverno -n kyverno --timeout=120s
```

---

## Step 2: Deploy Policies in Audit Mode

Start in audit mode — logs violations without blocking anything:

```bash
bash tools/deploy-policies.sh --mode audit
```

This deploys all policies from `policies/kyverno/`:

**Baseline policies (always deploy):**
- Disallow privileged containers
- Disallow privilege escalation
- Require drop ALL capabilities
- Require run as non-root
- Require read-only root filesystem
- Disallow host namespaces

**Custom policies:**
- Disallow `:latest` image tags
- Require resource limits
- Require semver image tags
- Require PSS labels on namespaces
- Require External Secrets (ban native Opaque secrets)

**Restricted policies (optional, stricter):**
- Require AppArmor profile
- Require Seccomp strict
- Require RuntimeClass

---

## Step 3: Let It Observe

Leave Kyverno in audit mode for at least a few days. Check what it would block:

```bash
# View policy violations (what WOULD be blocked)
kubectl get policyreport --all-namespaces -o wide

# Count violations per policy
kubectl get policyreport --all-namespaces -o json | \
  jq -r '.items[].results[]? | select(.result=="fail") | .policy' | sort | uniq -c | sort -rn
```

---

## Step 4: Fix Violations

Before enforcing, fix everything the audit found:

```bash
# Generate a report of all violations
bash tools/generate-fix-report.sh
```

Common violations and their fixes:
- **Privileged container** — add `securityContext.privileged: false`
- **Running as root** — add `securityContext.runAsNonRoot: true`
- **No resource limits** — add `resources.requests` and `resources.limits`
- **`:latest` tag** — pin to a specific version

For legitimate exceptions (monitoring agents, logging DaemonSets), create PolicyExceptions:

```yaml
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: allow-monitoring-privileged
  namespace: monitoring
spec:
  exceptions:
  - policyName: disallow-privileged
    ruleNames:
    - require-non-privileged
  match:
    any:
    - resources:
        kinds:
        - DaemonSet
        namespaces:
        - monitoring
```

---

## Step 5: Enforce

When violations are at zero (or only documented exceptions remain):

```bash
bash tools/audit-to-enforce.sh --mode enforce
```

**Progressive enforcement** (recommended):
```bash
# Week 1 — critical policies only
bash tools/audit-to-enforce.sh --mode enforce --tier critical

# Week 2 — add high severity
bash tools/audit-to-enforce.sh --mode enforce --tier high

# Week 3 — all policies
bash tools/audit-to-enforce.sh --mode enforce --tier all
```

---

## Step 6: Verify Enforcement

Try deploying something that violates a policy:

```bash
# This should be BLOCKED
kubectl run test-privileged --image=nginx --overrides='{
  "spec":{"containers":[{"name":"test","image":"nginx",
  "securityContext":{"privileged":true}}]}
}'
# Expected: Error from server (the policy blocked it)

# Clean up
kubectl delete pod test-privileged --ignore-not-found
```

---

## The Policies

All policies live in `policies/kyverno/`. Each one is a standalone YAML file you can review:

```bash
ls policies/kyverno/baseline/    # 6 policies — deploy everywhere
ls policies/kyverno/custom/      # 6 policies — org-specific rules
ls policies/kyverno/restricted/  # 3 policies — high-security environments
ls policies/kyverno/exceptions/  # exception templates
```

---

## Next Step

Go to [03-rbac-audit.md](03-rbac-audit.md) to lock down who can do what.
