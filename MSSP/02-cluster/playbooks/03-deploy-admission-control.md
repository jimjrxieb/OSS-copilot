# Playbook 03: Deploy Admission Control

> Install Kyverno and start blocking non-compliant workloads.
> Audit first, enforce later. Never enforce without observing.
>
> **Time:** ~15 minutes
> **Prerequisites:** Helm installed, kubectl cluster-admin access

---

## What Admission Control Is

Every time someone runs `kubectl apply`, the Kubernetes API server can check the
resource against policies before accepting it. If the resource violates a policy,
it gets rejected — the workload never runs.

This is the most important layer of cluster security. Scanning finds problems.
Admission control **prevents** them.

```
kubectl apply -f deployment.yaml
        ↓
  API Server receives request
        ↓
  Kyverno checks against policies
        ↓
  ✅ PASS → resource created
  ❌ FAIL → rejected with message explaining why
```

---

## Step 1: Choose Your Engine

| Engine | Choose If | Learning Curve |
|--------|----------|---------------|
| **Kyverno** | You're starting fresh. YAML-native, no new language. | Low |
| **Gatekeeper/OPA** | Your team already knows Rego. | Medium |

**Recommendation: Kyverno.** Unless you have existing Rego policies, Kyverno
is simpler to write, read, and debug. Policies are just YAML.

---

## Step 2: Install Kyverno

```bash
# Add the Helm repo
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Install in audit mode (logs violations, blocks nothing)
helm install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    --set admissionController.replicas=1

# Verify
kubectl get pods -n kyverno
# All pods should be Running
```

---

## Step 3: Deploy Policies in Audit Mode

Start with these 5 critical policies. In `audit` mode, they log violations
but don't block anything.

### Policy 1: Disallow Privileged Containers

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: Audit
  rules:
    - name: privileged-containers
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "Privileged containers are not allowed."
        pattern:
          spec:
            containers:
              - securityContext:
                  privileged: "false"
EOF
```

### Policy 2: Require Non-Root

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-run-as-nonroot
spec:
  validationFailureAction: Audit
  rules:
    - name: run-as-non-root
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "Containers must run as non-root."
        pattern:
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
EOF
```

### Policy 3: Require Resource Limits

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Audit
  rules:
    - name: require-limits
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "CPU and memory limits are required."
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    memory: "?*"
                    cpu: "?*"
EOF
```

### Policy 4: Disallow :latest Tag

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Audit
  rules:
    - name: disallow-latest
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "Using ':latest' image tag is not allowed. Pin to a specific version."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
EOF
```

### Policy 5: Require Drop All Capabilities

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-drop-all-capabilities
spec:
  validationFailureAction: Audit
  rules:
    - name: drop-all-capabilities
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "Containers must drop all capabilities."
        pattern:
          spec:
            containers:
              - securityContext:
                  capabilities:
                    drop: ["ALL"]
EOF
```

---

## Step 4: Verify Policies Are Active

```bash
# List all policies
kubectl get clusterpolicies

# Check for violations (give it a few minutes to scan existing resources)
kubectl get policyreports -A

# Count violations
kubectl get policyreports -A -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
total_fail = 0
for report in data.get('items', []):
    ns = report['metadata'].get('namespace', 'cluster')
    fails = report.get('summary', {}).get('fail', 0)
    if fails > 0:
        total_fail += fails
        print(f'  {ns}: {fails} violations')
print(f'\nTotal violations: {total_fail}')
"
```

---

## Step 5: Let It Observe (1 Week)

Leave the policies in audit mode for at least a week. During that time:
- Developers deploy as normal — nothing is blocked
- Kyverno logs every violation in PolicyReports
- You build a picture of what needs fixing before enforcement

**Check weekly:**
```bash
# Which policies have the most violations?
kubectl get policyreports -A -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
from collections import Counter
violations = Counter()
for report in data.get('items', []):
    for result in report.get('results', []):
        if result.get('result') == 'fail':
            violations[result.get('policy', 'unknown')] += 1
for policy, count in violations.most_common():
    print(f'  {policy}: {count} violations')
"
```

---

## Step 6: Fix Violations, Then Enforce

**The rule: violations must equal zero before you enforce.**

1. Fix the manifests (add securityContext, limits, pin image tags)
2. Redeploy
3. Check PolicyReports — violations should be 0
4. Then flip to enforce (see [05-enforce-and-track.md](05-enforce-and-track.md))

**Never skip from audit straight to enforce.** If you enforce with existing
violations, legitimate deployments will start failing.

---

## Gatekeeper Alternative

If your team prefers OPA/Rego:

```bash
# Install Gatekeeper
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper \
    --namespace gatekeeper-system \
    --create-namespace
```

Gatekeeper uses ConstraintTemplates (Rego) + Constraints (parameters). More
flexible but requires learning Rego. For most teams, Kyverno is simpler.

---

## Next Steps

- Audit and fix RBAC permissions → [04-harden-rbac.md](04-harden-rbac.md)
- Ready to enforce? → [05-enforce-and-track.md](05-enforce-and-track.md)
