# Example Output — Portfolio Scan

> Real scan results from running OSS-Copilot against
> [Portfolio](https://github.com/jimjrxieb/Portfolio), a production
> Python/Node.js application deployed on k3s with Helm and ArgoCD.
>
> **Date:** 2026-03-30
> **Mode:** Pre-deploy (static analysis — no cluster access needed)

---

## Executive Summary

| Layer | Tool | Findings | Status |
|-------|------|----------|--------|
| **Code — Secrets** | Gitleaks | 7 | 5 training examples, 2 to review |
| **Code — SAST** | Semgrep | 56 | 25 warnings (K8s examples), 6 errors (scan artifacts) |
| **Code — Dependencies** | Trivy | 4 HIGH | `tar@7.5.6` — fix with `npm update tar` |
| **Code — Dependencies** | Grype | 70 fixable | 7 critical, 32 high — `npm audit fix` |
| **Cluster — Best Practices** | Polaris | **100/100** | All security contexts, probes, limits present |
| **Cluster — IaC** | Checkov | 256 pass / 16 fail | 6 namespace artifacts, 10 real (low priority) |
| **Cluster — OPA Policies** | Conftest | **0 failures** | Passes all Portfolio Rego policies |
| **Cluster — RBAC** | Static review | **Clean** | No wildcards, automount disabled |

---

## What This Proves

**Code layer:** Most findings are dependency CVEs — fixable with `npm audit fix`
in under 5 minutes. The secrets are training material, not production credentials.
Semgrep's 56 findings drop to ~25 real ones after excluding scan artifacts and
intentional "bad example" manifests.

**Cluster layer:** Portfolio is already hardened. Polaris 100/100 means every
deployment has `runAsNonRoot`, `readOnlyRootFilesystem`, resource limits, and
health probes. Conftest 0 failures means the manifests pass the project's own
OPA policies. The 16 Checkov findings are mostly Helm rendering artifacts
(default namespace) and low-priority polish (image digests, high UIDs).

**The noise vs. signal breakdown:**

```
Total raw findings:          ~153
After removing noise:         ~35 real findings
Auto-fixable (npm/semgrep):   ~30
Needs manual review:           ~5
```

**An enterprise tool scanning this same environment would show the same ~35
real findings — plus the 120 it would flag as noise that drowns the signal.**
Running OSS-Copilot first means the enterprise tool (Wiz, Prisma, Snyk) only
shows what matters.

---

## Results by Layer

| Layer | Directory | What's In It |
|-------|-----------|-------------|
| [**01-code**](01-code/) | Gitleaks, Semgrep, Trivy, Grype JSON | [01-code/SUMMARY.md](01-code/SUMMARY.md) |
| [**02-cluster**](02-cluster/) | Polaris, Checkov, Conftest, rendered Helm | [02-cluster/SUMMARY.md](02-cluster/SUMMARY.md) |

---

## Enterprise Cost Comparison

| What We Ran (Free) | Enterprise Equivalent | Annual License |
|--------------------|----------------------|----------------|
| Gitleaks | GitGuardian | $15-50K |
| Semgrep | Checkmarx | $50-200K |
| Trivy + Grype | Snyk | $25-100K |
| Polaris + Checkov | Prisma Cloud IaC | $100-400K |
| Conftest | Styra DAS | $50-150K |

**Enterprise total: $240K-$900K/yr for equivalent pre-deploy coverage.**
**OSS-Copilot: $0.**

The 20% enterprise adds: dataflow SAST, reachability analysis, attack path
graphs, auto-fix PRs, continuous monitoring dashboards. For this project,
that gap doesn't change the outcome — the real findings are dependency
bumps and image digest pinning.
