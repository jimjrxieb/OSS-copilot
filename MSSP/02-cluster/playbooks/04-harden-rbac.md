# Playbook 04: Harden RBAC

> Find and fix over-permissioned roles, unnecessary cluster-admin bindings,
> and service accounts that have more access than they need.
>
> **Time:** ~15 minutes
> **Prerequisites:** kubectl cluster-admin access

---

## Why RBAC Matters

RBAC (Role-Based Access Control) determines who can do what in your cluster.
If RBAC is too loose, a compromised pod can read secrets from other namespaces,
create new deployments, or even take over the entire cluster.

The #1 RBAC problem: **cluster-admin bindings that shouldn't exist.**

---

## Step 1: Find cluster-admin Bindings

```bash
# Who has cluster-admin?
kubectl get clusterrolebindings -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('=== cluster-admin Bindings ===')
for binding in data.get('items', []):
    if binding.get('roleRef', {}).get('name') == 'cluster-admin':
        subjects = binding.get('subjects', [])
        name = binding['metadata']['name']
        for s in subjects:
            kind = s.get('kind', '?')
            ns = s.get('namespace', 'cluster-scoped')
            sname = s.get('name', '?')
            system = '(SYSTEM)' if name.startswith('system:') or sname.startswith('system:') else '← REVIEW THIS'
            print(f'  {kind}:{ns}/{sname} via {name} {system}')
"
```

### What to do with each binding:

| Subject | Action |
|---------|--------|
| `system:masters` | **Keep** — Kubernetes needs this |
| `system:kube-controller-manager` | **Keep** — system component |
| `system:kube-scheduler` | **Keep** — system component |
| Your admin user/group | **Keep** — but limit to named individuals |
| Helm tiller (legacy) | **Remove** — Helm 3 doesn't need this |
| CI/CD service account | **Scope down** — CI needs deploy, not admin |
| Application service account | **Remove** — apps should never be cluster-admin |
| Unknown or old bindings | **Remove** — if nobody knows why it exists, it shouldn't |

---

## Step 2: Find Wildcard Permissions

Wildcards (`*`) in ClusterRoles mean "can do everything." Sometimes legitimate
(system roles), usually not (custom roles).

```bash
# ClusterRoles with wildcard verbs or resources
kubectl get clusterroles -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('=== ClusterRoles with Wildcards ===')
for role in data.get('items', []):
    name = role['metadata']['name']
    if name.startswith('system:'):
        continue  # Skip system roles
    for rule in role.get('rules', []):
        verbs = rule.get('verbs', [])
        resources = rule.get('resources', [])
        if '*' in verbs or '*' in resources:
            print(f'  {name}:')
            print(f'    verbs: {verbs}')
            print(f'    resources: {resources}')
            print()
"
```

### How to fix wildcards:

```yaml
# BAD: can do anything to any resource
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]

# GOOD: scoped to what the app actually needs
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get"]
```

---

## Step 3: Audit Service Account Token Automount

By default, every pod gets a Kubernetes API token mounted. Most pods don't
need API access. An attacker who compromises a pod gets the token for free.

```bash
# Pods using default service account with automounted token
kubectl get pods --all-namespaces -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
risky = 0
for pod in data.get('items', []):
    ns = pod['metadata'].get('namespace', 'default')
    name = pod['metadata']['name']
    sa = pod['spec'].get('serviceAccountName', 'default')
    automount = pod['spec'].get('automountServiceAccountToken', True)
    if sa == 'default' and automount:
        risky += 1
        if risky <= 20:
            print(f'  {ns}/{name}: default SA + automount=true')
print(f'\nTotal pods at risk: {risky}')
print('Fix: set automountServiceAccountToken: false in pod spec')
"
```

### How to fix:

```yaml
# In your pod spec
spec:
  automountServiceAccountToken: false  # Unless your app needs K8s API access
  serviceAccountName: my-app-sa        # Use a dedicated SA, not default
```

---

## Step 4: Check for Dangerous Permissions

Some verbs are more dangerous than others:

```bash
# Roles that can escalate privileges
kubectl get clusterroles -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
dangerous_verbs = ['bind', 'escalate', 'impersonate', 'create']
dangerous_resources = ['clusterrolebindings', 'clusterroles', 'secrets']
print('=== Privilege Escalation Risks ===')
for role in data.get('items', []):
    name = role['metadata']['name']
    if name.startswith('system:'):
        continue
    for rule in role.get('rules', []):
        verbs = rule.get('verbs', [])
        resources = rule.get('resources', [])
        risky_verbs = [v for v in verbs if v in dangerous_verbs or v == '*']
        risky_resources = [r for r in resources if r in dangerous_resources or r == '*']
        if risky_verbs and risky_resources:
            print(f'  {name}: can {risky_verbs} on {risky_resources}')
"
```

| Verb | Risk |
|------|------|
| `bind` | Can grant themselves any role |
| `escalate` | Can escalate their own privileges |
| `impersonate` | Can act as any user/group |
| `create` on `secrets` | Can create secrets in any namespace |
| `*` on `*` | Can do anything (cluster-admin equivalent) |

---

## Step 5: Build a Three-Tier RBAC Model

For most teams, you need three roles:

### Cluster Admin (platform team only)

```yaml
# Use the built-in cluster-admin, bind to specific users only
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
  - kind: User
    name: alice@company.com  # Named individuals, not groups
  - kind: User
    name: bob@company.com
```

### Developer (namespace-scoped)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: my-app
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]  # Only in dev namespace
```

### CI/CD Service Account (deploy only)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ci-deployer
  namespace: my-app
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch", "update"]
  - apiGroups: [""]
    resources: ["services", "configmaps"]
    verbs: ["get", "list", "create", "update", "patch"]
```

---

## RBAC Scorecard

```
RBAC Security Scorecard
───────────────────────
Date: ___________

cluster-admin bindings (non-system):  ___  (target: named individuals only)
ClusterRoles with wildcards:          ___  (target: 0 non-system)
Pods with default SA + automount:     ___  (target: 0)
Roles with bind/escalate/impersonate: ___  (target: 0 non-system)
```

---

## Next Steps

- Enforce policies and track improvement → [05-enforce-and-track.md](05-enforce-and-track.md)
- Back to overview → [../README.md](../README.md)
