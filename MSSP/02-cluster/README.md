# 02-Cluster — Kubernetes Security

> This is what Wiz K8s, Prisma Cloud, and Styra DAS do.
> Here's kube-bench + Kubescape + Polaris + Kyverno doing 85% of it.

---

## Start Here

Kubernetes security has four layers. Most teams do zero of them.

```
LAYER 0 — Node Hardening        sysctl, auditd, kubelet config
LAYER 1 — CI/CD Gates           Block bad manifests before merge
LAYER 2 — Admission Control     Block bad workloads at kubectl apply
LAYER 3 — Runtime Audit         CIS benchmarks, RBAC, policy posture
```

Enterprise tools like Wiz ($100-400K/yr) and Prisma Cloud ($100-400K/yr) scan
your cluster and show you what's wrong. Open source tools do the same scans —
and also let you **fix and enforce** with admission control, which Wiz doesn't do.

**Follow the playbooks in order. Each one builds on the last.**

| # | Playbook | What You'll Do | Time |
|---|----------|---------------|------|
| 00 | [Know Your Cluster](playbooks/00-know-your-cluster.md) | Identify platform, GitOps, resource ownership | 5 min |
| 01 | [Your First Audit](playbooks/01-first-audit.md) | Run CIS benchmarks + Kubescape + Polaris | 15 min |
| 02 | [Read Your Audit](playbooks/02-read-your-audit.md) | Understand findings, score your cluster, know what to fix | 10 min |
| 03 | [Deploy Admission Control](playbooks/03-deploy-admission-control.md) | Install Kyverno in audit mode — watch before you block | 15 min |
| 04 | [Harden RBAC](playbooks/04-harden-rbac.md) | Find and fix over-permissioned roles and service accounts | 15 min |
| 05 | [Enforce and Track](playbooks/05-enforce-and-track.md) | Go from audit to enforce, measure improvement | 10 min |

---

## The Tools

| Tool | What It Does | One-Liner Install | Enterprise Equivalent |
|------|-------------|-------------------|----------------------|
| **kube-bench** | CIS Kubernetes Benchmark — node + control plane config | `brew install kube-bench` | Wiz K8s ($100K+/yr) |
| **Kubescape** | NSA/CISA hardening, MITRE ATT&CK, CIS misconfigs | [install](https://github.com/kubescape/kubescape) | Prisma Cloud ($100K+/yr) |
| **Polaris** | Deployment best practices — security, reliability score | `brew install polaris` | Built into Wiz/Prisma |
| **Kyverno** | Admission control — block non-compliant workloads | [helm install](https://kyverno.io) | Styra DAS ($50K+/yr) |
| **Gatekeeper/OPA** | Rego-based admission control | [helm install](https://open-policy-agent.github.io/gatekeeper/) | Styra DAS ($50K+/yr) |

---

## Quick Start (Skip the Playbooks)

```bash
cd 02-cluster

# CIS Kubernetes Benchmark
./scan-cis.sh

# RBAC analysis — who has too much access?
./scan-rbac.sh

# Admission control + policy posture
./scan-policies.sh
```

---

## What the Big 4 Run (and What You Can Run Instead)

When GuidePoint, Deloitte, or PwC run a Kubernetes hardening engagement, this is
the tooling behind it. They deploy $200-600K/yr in enterprise licenses. You can
cover 85% of it with open source.

| Engagement Phase | What the Big 4 Use | What You Run (Free) | Coverage |
|-----------------|-------------------|---------------------|----------|
| **CIS Benchmarks** | Wiz K8s ($100-400K/yr) | kube-bench | 95% — identical CIS checks |
| **Misconfiguration** | Prisma Cloud ($100-400K/yr) | Kubescape + Polaris | 85% — NSA/CISA + MITRE ATT&CK |
| **Admission Control** | Styra DAS ($50-150K/yr) | Kyverno (or Gatekeeper) | 90% — same enforcement, less lifecycle mgmt |
| **RBAC Analysis** | Teleport ($30-100K/yr) | kubectl + scripts | 60% — finds over-permissions, no session recording |
| **Network Segmentation** | Calico Enterprise ($50-200K/yr) | Calico OSS + Cilium | 75% — policies work, no flow visualization |
| **Policy-as-Code (CI)** | Styra DAS + Snyk IaC | Conftest + Checkov | 85% — same Rego policies, free |
| **Attack Path Analysis** | Wiz ($100-400K/yr) | (nothing equivalent) | 10% — this is where Wiz earns its money |
| **Drift Detection** | Wiz / Prisma ($100-400K/yr) | ArgoCD sync status + scripts | 60% — works for GitOps, not agentless |

### The math:

```
Big 4 K8s engagement tool stack:   $200K - $600K/yr in licenses
                                   + $250-500/hr consultant time

OSS-Copilot tool stack:            $0 in licenses
                                   + your time following these playbooks

Coverage delta:                    ~85% of the same detection + enforcement
The 15% gap:                       Attack path graphs, continuous dashboards,
                                   multi-cluster view, session recording,
                                   network flow visualization
```

### How a real engagement works:

1. **Discover** — Identify platform (k3s/EKS/kubeadm), GitOps (ArgoCD/Flux), ownership
2. **Audit** — kube-bench + Kubescape + Polaris → baseline scores
3. **Harden manifests** — securityContext, limits, probes, pin image tags
4. **Deploy admission control** — Kyverno in audit mode, observe for 1 week
5. **Fix violations** — Drive violation count to zero
6. **Enforce** — Progressive rollout (critical → high → all)
7. **RBAC** — Remove unnecessary cluster-admin, scope wildcards, disable SA automount
8. **Deliverable** — Before/after Polaris scores, violation trend, enforcement status

That's what these playbooks walk you through. Same methodology, same tools.

---

## CKS Exam Alignment

These playbooks map directly to CKS (Certified Kubernetes Security Specialist)
exam domains. If you're studying for CKS, this is hands-on practice.

| CKS Domain | Weight | OSS-Copilot Coverage | Playbooks |
|-----------|--------|---------------------|-----------|
| **Cluster Setup** — CIS, network policies, GUI access | 10% | kube-bench, NetworkPolicy, dashboard restrictions | 01, 02 |
| **Cluster Hardening** — RBAC, service accounts, admission control | 15% | RBAC audit, SA automount, Kyverno/Gatekeeper | 03, 04 |
| **System Hardening** — host OS, kernel, minimize footprint | 15% | Kubescape checks, seccomp/AppArmor references | 01, 02 |
| **Minimize Microservice Vulnerabilities** — PSS, OPA, secrets, runtime | 20% | PSA labels, Kyverno policies, securityContext hardening | 03, 05 |
| **Supply Chain Security** — image scanning, signing, Dockerfile | 20% | Trivy image scan, Hadolint, pinned tags | See [03-container](../03-container/) |
| **Monitoring, Logging, Runtime** — Falco, audit logs, immutable containers | 20% | Falco deployment, readOnlyRootFilesystem | See [03-container](../03-container/) |

### What each playbook covers per CKS domain:

```
Playbook 00 (Know Your Cluster)
  └─ CKS: Cluster Setup — understand the environment before hardening

Playbook 01 (First Audit)
  └─ CKS: Cluster Setup — CIS benchmarks (kube-bench)
  └─ CKS: System Hardening — NSA/CISA checks (Kubescape)

Playbook 02 (Read Your Audit)
  └─ CKS: All domains — interpret findings mapped to MITRE ATT&CK

Playbook 03 (Admission Control)
  └─ CKS: Cluster Hardening — Kyverno/Gatekeeper (admission webhooks)
  └─ CKS: Microservice Vulnerabilities — PSS enforcement, OPA/Kyverno policies

Playbook 04 (Harden RBAC)
  └─ CKS: Cluster Hardening — RBAC, service account restrictions
  └─ CKS: Cluster Hardening — least privilege, disable SA token automount

Playbook 05 (Enforce and Track)
  └─ CKS: Cluster Hardening — progressive policy enforcement
  └─ CKS: Monitoring — PolicyReport tracking, violation trending
```

### CKS domains covered in other packages:

| Domain | Where |
|--------|-------|
| Supply chain (image scanning, signing, Dockerfile) | [03-container/](../03-container/) playbooks 01, 02, 05 |
| Runtime security (Falco, syscall monitoring) | [03-container/](../03-container/) playbook 04 |
| Cloud security (IAM, VPC, GuardDuty) | [04-cloud/](../04-cloud/) |

---

## What These Tools Actually Catch

**Real examples from a production k3s cluster:**

```
kube-bench   →  FAIL: API server --anonymous-auth is set to true
                FAIL: kubelet certificate rotation is not enabled
                FAIL: etcd data directory permissions are 777

Kubescape    →  Risk score: 67/100
                27/37 pods have no resource limits
                9/12 namespaces have no NetworkPolicy
                3 cluster-admin bindings (2 are unnecessary)

Polaris      →  Score: 62/100
                12 deployments running as root
                8 deployments missing health probes
                15 images using :latest tag

Kyverno      →  (in audit mode) 47 policy violations found:
                23 containers without securityContext
                11 containers without resource limits
                8 containers running as root
                5 containers with privilege escalation allowed
```

---

## The Defense-in-Depth Model

```
DEVELOPER writes YAML
        ↓
    CI/CD checks with conftest       ← LAYER 1: block before merge
        ↓ (pass)
    kubectl apply / ArgoCD sync
        ↓
    Kyverno/Gatekeeper checks        ← LAYER 2: block at API server
        ↓ (pass)
    Pod scheduled and running
        ↓
    kube-bench + Kubescape audit     ← LAYER 3: detect in production
        ↓
    Falco monitors runtime           ← LAYER 4: detect behavior (see 03-container)
```

The further left you catch it, the cheaper it is to fix.
Admission control (Layer 2) is the most important layer — it prevents
misconfigurations from ever reaching the cluster.

---

## What Enterprise Does Better (the Honest 20%)

| Gap | What Enterprise Does | Why It Matters |
|-----|---------------------|----------------|
| **Attack path analysis** | Wiz connects K8s misconfig → IAM → data stores | Shows which misconfigs are actually exploitable |
| **Agentless scanning** | Wiz reads config via API, no agent needed | Less operational burden |
| **Continuous monitoring** | Wiz rescans automatically with trend dashboards | Scripts scan when you run them |
| **Multi-cluster view** | Single pane across all clusters and clouds | Open source scans one cluster at a time |
| **Policy lifecycle** | Styra DAS: authoring, testing, distribution, monitoring | Raw Kyverno/OPA requires you to build this yourself |

**When to buy enterprise:**
- You need attack path analysis (Wiz graph — nothing else does this)
- You manage >10 clusters and need centralized posture management
- Compliance requires continuous monitoring with historical trends
- You need 24/7 monitoring evidence for auditors

**When open source is enough:**
- Teams running 1-10 clusters
- Admission control (Kyverno = Styra for policy enforcement)
- CIS benchmarks (kube-bench = Wiz for CIS compliance)
- Pre-SOC 2 environments proving basic hardening

---

## How This Connects to GP-Copilot

This directory is the open source version of
GP-CONSULTING/02-CLUSTER-HARDEN in the [GP-Copilot](https://github.com/jimjrxieb/GP-copilot) repo — the
full K8s hardening package with 23 playbooks, 13 Kyverno policies, 18 audit scripts,
Ansible node hardening, and progressive enforcement.

| You're Here (OSS-Copilot) | Full Framework (GP-Copilot) |
|---------------------------|----------------------------|
| 3 scanners + 6 playbooks | 5 scanners + 23 playbooks |
| Manual Kyverno install | Automated deployment + progressive enforcement |
| Basic RBAC audit | RBAC risk analyzer (privilege escalation paths) |
| Manual fixes | 18 automated fix scripts |
| Point-in-time scans | Drift detection (git vs cluster) |
| No node hardening | Ansible-based CIS node hardening |

OSS-Copilot gives you the audit and basic enforcement for free.
The full framework adds automated fixes, node hardening, GitOps integration,
cost optimization, and CKS/CKA exam alignment.
