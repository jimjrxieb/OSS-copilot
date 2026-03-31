# Playbook 00: Know Your Cluster

> Before you audit, understand what you're working with. Platform, GitOps,
> who owns what. 5 minutes now saves hours of confusion later.
>
> **Time:** 5 minutes
> **Prerequisites:** kubectl access to a cluster

---

## Why This Matters

Kubernetes clusters are not all the same. k3s, EKS, kubeadm, and Docker Desktop
have different config paths, different defaults, and different gotchas. If you
run kube-bench on EKS expecting control plane results, you'll get confused —
AWS manages the control plane.

A senior engineer asks "what am I working with?" before running tools.

---

## Step 1: Identify Your Platform

```bash
# What Kubernetes distribution is this?
kubectl version --short 2>/dev/null || kubectl version

# Check for managed K8s identifiers
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'
# k3s: contains "k3s"
# EKS: contains "eks"
# GKE: contains "gke"
# AKS: contains "1.xx.x" (vanilla, check cloud provider)
```

### What this means for your audit:

| Platform | CIS Control Plane | CIS Worker Node | Node Access |
|----------|------------------|-----------------|-------------|
| **EKS** | AWS manages it (skip) | Scan worker nodes | No SSH by default |
| **GKE** | Google manages it (skip) | Scan worker nodes | No SSH by default |
| **AKS** | Azure manages it (skip) | Scan worker nodes | No SSH by default |
| **k3s** | You own it (scan it) | You own it (scan it) | SSH required |
| **kubeadm** | You own it (scan it) | You own it (scan it) | SSH required |
| **Docker Desktop** | Dev only (skip) | Dev only (skip) | Not applicable |

---

## Step 2: Check for GitOps Controllers

```bash
# Is ArgoCD managing resources?
kubectl get applications.argoproj.io -A 2>/dev/null
# If this returns results → ArgoCD is deployed

# Is Flux managing resources?
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A 2>/dev/null
# If this returns results → Flux is deployed
```

### Why this matters (critical):

If ArgoCD or Flux manages a resource, **you cannot kubectl patch it.**
The GitOps controller will revert your change on the next sync.
You must fix it in git instead.

```bash
# Check if a specific resource is ArgoCD-managed
kubectl get deployment <name> -n <namespace> \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}'
# Returns app name → managed by ArgoCD → fix in git
# Returns nothing → kubectl-managed → safe to kubectl patch
```

---

## Step 3: Inventory What's Running

```bash
# How big is this cluster?
echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"
echo "Namespaces: $(kubectl get ns --no-headers | wc -l)"
echo "Pods: $(kubectl get pods -A --no-headers | wc -l)"
echo "Deployments: $(kubectl get deployments -A --no-headers | wc -l)"
echo "Services: $(kubectl get svc -A --no-headers | wc -l)"

# What namespaces exist?
kubectl get ns --no-headers | awk '{print $1}'

# Any admission controllers already deployed?
kubectl get pods -A | grep -iE 'kyverno|gatekeeper|opa'

# Any monitoring?
kubectl get pods -A | grep -iE 'prometheus|grafana|falco'
```

---

## Step 4: Check Existing Security Posture

```bash
# Pod Security Standards — which namespaces have labels?
kubectl get ns -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for ns in data.get('items', []):
    name = ns['metadata']['name']
    labels = ns['metadata'].get('labels', {})
    enforce = labels.get('pod-security.kubernetes.io/enforce', '')
    if enforce:
        print(f'  {name}: enforce={enforce}')
    elif not name.startswith('kube-'):
        print(f'  {name}: NO PSA label')
"

# Any NetworkPolicies?
echo "NetworkPolicies: $(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)"

# Any ResourceQuotas?
echo "ResourceQuotas: $(kubectl get resourcequotas -A --no-headers 2>/dev/null | wc -l)"

# Any LimitRanges?
echo "LimitRanges: $(kubectl get limitranges -A --no-headers 2>/dev/null | wc -l)"
```

---

## Step 5: Build Your Cluster Profile

Fill this in before proceeding:

```
Cluster Profile
───────────────
Platform:               ___  (k3s / EKS / GKE / AKS / kubeadm)
K8s version:            ___
Nodes:                  ___
Namespaces:             ___
Total pods:             ___

GitOps:                 ___  (ArgoCD / Flux / None)
Admission control:      ___  (Kyverno / Gatekeeper / None)
Monitoring:             ___  (Prometheus / Grafana / None)
Runtime detection:      ___  (Falco / None)

PSA-labeled namespaces: ___  / ___ total
NetworkPolicies:        ___
ResourceQuotas:         ___
LimitRanges:            ___
```

If admission control says "None" and NetworkPolicies is 0, you have work to do.
That's OK — that's why you're here.

---

## Next Steps

Now you know what you're working with. Time to audit it.

Go to: [01-first-audit.md](01-first-audit.md)
