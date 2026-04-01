# 03 — RBAC Audit

> Find and fix over-permissioned roles, cluster-admin bindings, and wildcard permissions.

Most clusters have more cluster-admin bindings than they need. This playbook finds them, assesses the risk, and replaces them with least-privilege roles.

In production, tools like Teleport and CyberArk handle identity and access. This gets your RBAC clean for staging.

---

## What You Need

- Playbook 02 completed (admission control deployed)
- `kubectl` access

---

## Step 1: Run the RBAC Audit

```bash
bash tools/rbac-audit.sh --output $OUTPUT_DIR
```

**What it checks:**
1. All ClusterRoleBindings bound to `cluster-admin`
2. ClusterRoles with wildcard (`*`) on verbs or resources
3. ServiceAccounts with `automountServiceAccountToken: true` (default)
4. Roles that can create/patch Roles or RoleBindings (privilege escalation)

---

## Step 2: Run Risk Analysis

```bash
bash tools/rbac-risk-analyzer.sh --output $OUTPUT_DIR
```

This goes deeper — finds escalation paths where a user or service account could grant themselves more permissions than they currently have.

---

## Step 3: Fix the Critical Ones

### cluster-admin Bindings

```bash
# List them
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name'
```

**Decision tree:**
- **System bindings** (eks:*, system:*) — don't touch. These are managed by the platform.
- **Human admin bindings** — replace with scoped roles. Nobody needs cluster-admin for daily work.
- **Service account bindings** — replace with the minimum permissions the app needs.

### Wildcard Permissions

```bash
kubectl get clusterroles -o json | \
  jq -r '.items[] | select(.rules[]? | select(.verbs[] == "*" and .resources[] == "*")) | .metadata.name'
```

For each one: either replace with specific verbs/resources, or document why the wildcard is needed.

---

## Step 4: Apply Least-Privilege Role Templates

We have three RBAC templates for common roles:

```bash
# Admin — can manage workloads and RBAC within namespaces (NOT cluster-admin)
kubectl apply -f templates/rbac/admin.yaml

# Platform engineer — can deploy and debug, can't change RBAC
kubectl apply -f templates/rbac/platform-eng.yaml

# Developer — can view resources, port-forward, exec into pods
kubectl apply -f templates/rbac/developer.yaml
```

Review each template before applying — adjust the permissions to match your team's actual needs.

---

## Step 5: Disable Default ServiceAccount Tokens

Most pods don't need to talk to the Kubernetes API. Disable the auto-mounted token:

```bash
# Find pods with tokens mounted (that probably don't need them)
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.automountServiceAccountToken != false) | "\(.metadata.namespace)/\(.metadata.name)"' | head -20
```

**Exception:** Pods that DO need the token — operators, controllers, monitoring agents that query the K8s API.

---

## Step 6: Verify

```bash
# Re-run the audit
bash tools/rbac-audit.sh --output $OUTPUT_DIR

# Check: no non-system cluster-admin bindings
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name=="cluster-admin") | select(.metadata.name | startswith("system:") | not) | select(.metadata.name | startswith("eks:") | not) | .metadata.name'
# Expected: 0 results (or only documented exceptions)
```

---

## Next Step

Go to [04-network-policies.md](04-network-policies.md) to lock down network traffic.
