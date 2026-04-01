# 00 — Audit Your Cluster

> Before you harden anything, understand what you're working with.

You don't deploy Kyverno policies on a cluster you haven't audited. That's how you break production workloads. This playbook runs the baseline audit so you know exactly what needs fixing.

In production, tools like Prisma Cloud and Wiz do continuous posture management. This is your staging version — get the cluster clean here first.

---

## What You Need

- `kubectl` access to your cluster
- Your paths set:
  ```bash
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

---

## Step 1: Install the Audit Tools

```bash
bash tools/install-scanners.sh
```

This installs (or checks for): Kubescape, kube-bench, Polaris, and the RBAC audit tools. Anything already installed gets skipped.

---

## Step 2: Detect Your Platform

Different platforms have different quirks. Know which one you're on:

```bash
# k3s
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' | grep k3s && echo "k3s"

# EKS
kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' | grep aws && echo "EKS"

# kubeadm / self-hosted
kubectl get pods -n kube-system -l component=kube-apiserver 2>/dev/null && echo "Self-hosted"
```

**Why this matters:**
- **EKS** — you can't change API server flags (managed control plane). kube-bench will flag these as failures but they're not actionable.
- **k3s** — ships with Traefik and ServiceLB by default. PSA labels may conflict with system workloads.
- **Docker Desktop** — single-node, no real networking. Good for testing policies, not for benchmarks.

---

## Step 3: Run the Audit

```bash
bash tools/run-cluster-audit.sh --output $OUTPUT_DIR
```

**What it does:**
1. CIS benchmark (kube-bench) — checks node and control plane config
2. NSA/CISA hardening (Kubescape) — checks workload security posture
3. Best practices (Polaris) — checks deployments for missing limits/probes/security
4. RBAC overview — lists cluster-admin bindings and wildcard permissions
5. NetworkPolicy coverage — which namespaces have policies vs open
6. PSS label check — which namespaces have Pod Security Standards

**Output:** `$OUTPUT_DIR/cluster-audit/` with JSON results and a `SUMMARY.md`.

---

## Step 4: Review the Summary

```bash
cat $OUTPUT_DIR/cluster-audit/SUMMARY.md
```

**What to look for:**
- How many namespaces have no NetworkPolicy? (common: all of them)
- How many deployments are running as root? (common: most)
- How many cluster-admin bindings exist? (common: too many)
- Are PSS labels applied? (common: no)
- CIS benchmark score (most clusters start around 40-60%)

---

## Step 5: Document Your Baseline

Write down:
- Cluster type (EKS/k3s/kubeadm)
- Node count and version
- Namespace count
- Findings by severity
- Known exceptions (monitoring agents that need privileged, etc.)

This is your "before" snapshot. Everything from here forward makes this better.

---

## Platform-Specific Notes

| Platform | Can't Fix (Managed) | Focus On |
|----------|-------------------|----------|
| **EKS** | API server flags, etcd encryption config | Workload security, RBAC, NetworkPolicy |
| **k3s** | Traefik/ServiceLB conflicts with PSA | Disable defaults or add exceptions |
| **kubeadm** | Nothing — full control | Everything |
| **Docker Desktop** | Single-node, no real HA | Policy testing only |

---

## Next Step

Go to [01-auto-fix-cluster.md](01-auto-fix-cluster.md) to batch-fix the findings.
