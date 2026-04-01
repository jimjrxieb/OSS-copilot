# 01 — Auto-Fix Cluster Security

> Batch-fix the common findings: NetworkPolicy, Pod Security Standards, LimitRanges, ResourceQuotas.

You ran the audit (playbook 00). Now fix what it found. This script handles the cluster-wide defaults that every namespace needs — the stuff that Prisma Cloud and Wiz would flag on every scan.

---

## What You Need

- Playbook 00 completed (cluster audit done)
- `kubectl` access with permission to create NetworkPolicies, LimitRanges, and label namespaces

---

## Step 1: Dry Run

Always preview what would change:

```bash
bash tools/fix-cluster-security.sh --dry-run
```

**What it checks and fixes (per namespace):**
1. **Default-deny NetworkPolicy** — blocks all traffic unless explicitly allowed
2. **LimitRange** — sets default resource requests/limits for pods that don't specify them
3. **ResourceQuota** — caps total resource usage per namespace
4. **PSS labels** — applies Pod Security Standards (restricted/baseline) to namespaces

---

## Step 2: Review the Dry Run

The script outputs a plan for each namespace:
```
Namespace: app-dev
  [WOULD CREATE] NetworkPolicy default-deny
  [WOULD CREATE] LimitRange default-limits
  [WOULD LABEL]  pod-security.kubernetes.io/enforce=restricted
  [SKIP]         ResourceQuota (already exists)
```

**Check:**
- Are system namespaces excluded? (kube-system, kube-public, etc. should be)
- Do any namespaces need exceptions? (monitoring, logging agents that need elevated permissions)
- Are the default limits reasonable for your workloads?

---

## Step 3: Apply

```bash
bash tools/fix-cluster-security.sh
```

---

## Step 4: Right-Size Existing Workloads

If you have running workloads, profile their actual usage and set proper limits:

```bash
bash tools/profile-and-set-limits.sh --namespace <namespace>
```

This looks at actual CPU/memory usage over time and sets requests/limits accordingly. Much better than guessing.

---

## Step 5: Verify

```bash
# Check NetworkPolicies exist in all namespaces
kubectl get networkpolicy --all-namespaces

# Check PSS labels
kubectl get ns --show-labels | grep pod-security

# Check LimitRanges
kubectl get limitrange --all-namespaces

# Re-run the audit to compare
bash tools/run-cluster-audit.sh --output $OUTPUT_DIR --label post-fix
```

---

## What Gets Fixed

| Finding | What the Script Does |
|---------|---------------------|
| No NetworkPolicy | Creates default-deny ingress + egress |
| No LimitRange | Sets default CPU/memory requests and limits |
| No PSS labels | Applies `pod-security.kubernetes.io/enforce=restricted` |
| No ResourceQuota | Creates namespace-level resource caps |
| Open DNS egress | Creates allow-dns-egress NetworkPolicy |

---

## Namespaces to Skip

The script auto-skips these system namespaces:
- `kube-system`, `kube-public`, `kube-node-lease`
- `argocd`, `kyverno` (need elevated permissions)

For other namespaces that need exceptions (monitoring, logging), pass `--exclude <namespace>`.

---

## Next Step

Go to [02-deploy-admission-control.md](02-deploy-admission-control.md) to prevent these issues from coming back.
