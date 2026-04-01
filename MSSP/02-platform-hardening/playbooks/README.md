# 02 — Platform Hardening Playbooks

> Harden your Kubernetes cluster for dev and staging. Enterprise tools take over in production.

This is training camp for your cluster. Open source tools (Kyverno, Kubescape, kube-bench, Polaris) cover 80-90% of what enterprise platforms charge for. Get everything passing here, and the production tools (Prisma Cloud, Wiz, Styra, Calico Enterprise) inherit a clean cluster.

---

## Follow the Playbooks in Order

| Phase | # | Playbook | What You Do | Time |
|-------|---|----------|-------------|------|
| **Assess** | 00 | [Audit Your Cluster](00-audit-your-cluster.md) | Baseline scan — know what you're working with | 15 min |
| **Fix** | 01 | [Auto-Fix Cluster](01-auto-fix-cluster.md) | Batch-fix NetworkPolicy, PSS, limits | 15 min |
| **Gate** | 02 | [Deploy Admission Control](02-deploy-admission-control.md) | Kyverno policies — audit then enforce | 30 min |
| **Lock Down** | 03 | [RBAC Audit](03-rbac-audit.md) | Find and fix over-permissioned roles | 20 min |
| **Lock Down** | 04 | [Network Policies](04-network-policies.md) | Per-service ingress/egress rules | 30 min |
| **Lock Down** | 05 | [Secrets Management](05-secrets-management.md) | External Secrets Operator | 20 min |
| **Verify** | 06 | [Scan and Verify](06-scan-and-verify.md) | Prove the fixes worked | 15 min |
| **Prevent** | 07 | [Wire CI/CD](07-wire-cicd.md) | Conftest policies in GitHub Actions | 10 min |
| **Deploy** | 08 | [Deploy Staging](08-deploy-staging.md) | Helm deploy with security validation | 20 min |
| **Evidence** | 09 | [Compliance Report](09-compliance-report.md) | Before/after proof | 15 min |

**Total: ~3 hours for the full pass.**

---

## Setup

### 1. Set your paths

```bash
export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
```

### 2. Confirm cluster access

```bash
kubectl cluster-info
kubectl config current-context
```

### 3. Follow playbook 00

---

## The Tools

| Tool | What It Does | Install |
|------|-------------|---------|
| **Kubescape** | NSA/CISA + MITRE hardening scan | `brew install kubescape` |
| **kube-bench** | CIS Kubernetes Benchmark | `brew install kube-bench` |
| **Polaris** | K8s best practices audit | `brew install polaris` |
| **Kyverno** | Admission control (policy enforcement) | Helm chart |
| **Conftest** | OPA policy checks in CI | `brew install conftest` |
| **ESO** | External Secrets Operator | Helm chart |
| **Trivy** | Container image CVE scanning | `brew install trivy` |

---

## What's in This Directory

```
02-platform-hardening/
  playbooks/        <- You are here
  tools/            <- Scripts the playbooks call
  policies/         <- Kyverno + Conftest policy files
  templates/        <- External Secrets + Helm templates
```

---

## How This Connects to Production

| This Package (Dev/Staging) | Production |
|---------------------------|------------|
| Kubescape, kube-bench, Polaris | Prisma Cloud, Wiz, ARMO |
| Kyverno | Styra DAS, Nirmata |
| Conftest (CI gate) | Kyverno/Gatekeeper (admission) |
| Network Policy generator | Calico Enterprise, Cilium Enterprise |
| External Secrets Operator | CyberArk, Akeyless |
| RBAC audit scripts | Teleport, CyberArk |

Same controls, different tools. Get everything passing here and the enterprise tools have nothing to complain about.
