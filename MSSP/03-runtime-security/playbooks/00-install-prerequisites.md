# 00 — Install Prerequisites

> Install the tools you need before deploying runtime security.

This gets kubectl, helm, jq, yq, and python3 verified and ready. Everything else in this package depends on these.

---

## Step 1: Run the Installer

```bash
bash tools/install-prerequisites.sh
```

**What it checks/installs:**
- `kubectl` — Kubernetes CLI
- `helm` — Helm v3+
- `jq` — JSON processing
- `yq` — YAML processing
- `python3` — for report generation

Missing tools get installed. Already-installed tools get version-checked.

---

## Step 2: Check-Only Mode

If you just want to verify without installing:

```bash
bash tools/install-prerequisites.sh --check-only
```

---

## Step 3: Verify Cluster Access

```bash
kubectl cluster-info
kubectl get nodes
helm version --short
```

---

## Next Step

Go to [01-deploy-falco.md](01-deploy-falco.md) to deploy runtime detection.
