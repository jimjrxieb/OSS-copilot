# Playbook 02: Read Your Audit

> Understand what the scanners found, what it means, and what to fix first.
>
> **Time:** 10 minutes
> **Prerequisites:** You've run [01-first-audit.md](01-first-audit.md)

---

## The Priority Order

Cluster security findings have a clear hierarchy:

```
1. PRIVILEGED CONTAINERS     ← Fix TODAY. Full host access = game over if compromised.
2. CLUSTER-ADMIN BINDINGS    ← Fix TODAY. Unnecessary god-mode accounts.
3. NO NETWORK POLICIES       ← Fix this week. Any pod can talk to any pod.
4. RUNNING AS ROOT           ← Fix this week. Attackers get root inside the container.
5. NO RESOURCE LIMITS        ← Fix this sprint. One pod can starve the node.
6. NO HEALTH PROBES          ← Fix this sprint. Orchestrator can't detect failures.
7. :LATEST TAGS              ← Fix over time. You don't know what version is running.
8. MISSING PSA LABELS        ← Fix over time. No namespace-level enforcement.
```

---

## Reading kube-bench Results

kube-bench maps directly to CIS Kubernetes Benchmark sections:

| Section | What It Checks | Who Owns It |
|---------|---------------|-------------|
| **1.x** | API server configuration | You (self-hosted) or Cloud provider (EKS/GKE) |
| **2.x** | etcd configuration | You (self-hosted) or Cloud provider |
| **3.x** | Control plane configuration | You (self-hosted) or Cloud provider |
| **4.1.x** | Worker node — kubelet | You (always) |
| **4.2.x** | Worker node — kubelet config | You (always) |
| **5.x** | Policies (RBAC, PSP, NetworkPolicy) | You (always) |

### Most critical FAIL items:

| Check | What It Means | Fix |
|-------|--------------|-----|
| `1.2.1 anonymous-auth` | Unauthenticated API access | `--anonymous-auth=false` in API server config |
| `4.2.1 authentication` | Kubelet accepts unauthenticated requests | `authentication.anonymous.enabled: false` |
| `4.2.6 protect-kernel-defaults` | Kubelet doesn't enforce sysctl | `protectKernelDefaults: true` |
| `5.1.1 cluster-admin` | Non-essential cluster-admin bindings | Remove or scope down |
| `5.2.x pod-security` | No pod security enforcement | Add PSA labels to namespaces |
| `5.3.2 network-policy` | Namespaces without NetworkPolicy | Add default-deny + service-specific rules |

**On EKS/GKE/AKS:** Sections 1-3 are managed by your cloud provider. Skip those
FAILs — you can't fix them (and don't need to). Focus on sections 4 and 5.

---

## Reading Kubescape Results

Kubescape maps findings to two frameworks:

### NSA/CISA Hardening Guide

| Control | What It Checks | Common Finding |
|---------|---------------|----------------|
| **Non-root containers** | containers running as root | Add `runAsNonRoot: true` |
| **Immutable filesystems** | writable root filesystem | Add `readOnlyRootFilesystem: true` |
| **Resource limits** | pods without CPU/memory limits | Add `resources.limits` |
| **Network segmentation** | namespaces without NetworkPolicy | Add default-deny per namespace |
| **Pod service account** | default SA with automount | `automountServiceAccountToken: false` |

### MITRE ATT&CK for Kubernetes

Kubescape maps to real attack techniques:

| Technique | What It Means | Plain English |
|-----------|--------------|---------------|
| **T1610** | Container escape via privileged mode | An attacker inside a container gets root on the node |
| **T1552** | Credentials in environment variables | Secrets passed as env vars instead of Secret mounts |
| **T1078** | Over-permissioned service accounts | Service account can do more than the app needs |
| **T1046** | No network segmentation | Compromised pod can scan and reach other pods |

---

## Reading Polaris Results

Polaris gives a score out of 100. Here's what the categories mean:

| Category | What It Checks | Weight |
|----------|---------------|--------|
| **Security** | runAsNonRoot, readOnlyRootFS, capabilities | High |
| **Reliability** | health probes, resource requests, replicas | Medium |
| **Efficiency** | resource limits, QoS class | Medium |
| **Networking** | hostNetwork, hostPort | Low |

### Common Polaris findings:

| Finding | Severity | What to Add to Your Manifest |
|---------|----------|------------------------------|
| `runAsNonRoot should be true` | Warning | `securityContext.runAsNonRoot: true` |
| `cpuLimitsMissing` | Warning | `resources.limits.cpu: "500m"` |
| `memoryLimitsMissing` | Warning | `resources.limits.memory: "512Mi"` |
| `readinessProbeMissing` | Warning | `readinessProbe.httpGet.path: /ready` |
| `livenessProbeMissing` | Warning | `livenessProbe.httpGet.path: /health` |
| `insecureCapabilities` | Danger | `capabilities.drop: ["ALL"]` |

---

## Making Sense of It All

After reading your results, fill in this scorecard:

```
Cluster Security Scorecard
──────────────────────────
Date: ___________
Platform: ___________

kube-bench:  ___ PASS / ___ FAIL / ___ WARN
Kubescape:   ___% compliance score
Polaris:     ___/100 score

Critical findings:
  Privileged containers:        ___  (target: 0)
  cluster-admin bindings:       ___  (target: system-only)
  Namespaces without NetPol:    ___  (target: 0)
  Pods running as root:         ___  (target: 0)
  Pods without resource limits: ___  (target: 0)
  Pods without health probes:   ___  (target: 0)
```

---

## Realistic Targets

| Metric | Good | Acceptable | Needs Work |
|--------|------|-----------|------------|
| Polaris score | 80+ | 60-79 | <60 |
| Kubescape compliance | 80%+ | 60-79% | <60% |
| Privileged containers | 0 (app) | 0 (app) | Any app container |
| NetworkPolicies | All namespaces | Most namespaces | <50% |
| Resource limits | All pods | Most pods | <50% |

**System components** (kube-proxy, CNI, Falco, metrics-server) legitimately need
elevated permissions. Count them separately from your application workloads.

---

## Next Steps

- Deploy admission control to prevent new issues → [03-deploy-admission-control.md](03-deploy-admission-control.md)
- Audit and fix RBAC → [04-harden-rbac.md](04-harden-rbac.md)
