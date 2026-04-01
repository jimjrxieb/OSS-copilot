# 09 — Compliance Report

> Produce before/after evidence that the cluster is hardened.

This is your deliverable. It shows what the cluster looked like before, what was fixed, and what the posture looks like now. Auditors, managers, and the team taking over in production all need this.

---

## What You Need

- All previous playbooks completed
- Baseline audit from playbook 00
- Post-fix scan from playbook 06

---

## Step 1: Generate Coverage Report

```bash
python3 tools/policy-coverage-report.py --output $OUTPUT_DIR/compliance-report.md
```

This maps your Kyverno policies and scan results to compliance frameworks:
- CIS Kubernetes Benchmark
- NIST 800-53 (AC, CM, AU controls)
- SOC 2 (CC6, CC7, CC8)

---

## Step 2: Run Final Audit

```bash
bash tools/run-cluster-audit.sh --output $OUTPUT_DIR --label final
```

---

## Step 3: Before/After Comparison

```bash
BEFORE=$OUTPUT_DIR/cluster-audit
AFTER=$OUTPUT_DIR/final

echo "=== Platform Hardening Results ==="

echo "--- CIS Benchmark ---"
echo "Before: $(jq '[.Controls[].tests[].results[] | select(.status=="FAIL")] | length' $BEFORE/kube-bench.json 2>/dev/null) failures"
echo "After:  $(jq '[.Controls[].tests[].results[] | select(.status=="FAIL")] | length' $AFTER/kube-bench.json 2>/dev/null) failures"

echo "--- Kubescape ---"
echo "Before: $(jq '[.results[]? | select(.status=="failed")] | length' $BEFORE/kubescape.json 2>/dev/null) failed controls"
echo "After:  $(jq '[.results[]? | select(.status=="failed")] | length' $AFTER/kubescape.json 2>/dev/null) failed controls"

echo "--- Policy Violations ---"
echo "Active: $(kubectl get policyreport --all-namespaces -o json | jq '[.items[].results[]? | select(.result=="fail")] | length') violations"
```

---

## Step 4: Write the Report

```markdown
# Platform Hardening Report — <CLUSTER_NAME>
Date: <DATE>

## Cluster Info
- Type: <EKS/k3s/kubeadm>
- Version: <version>
- Nodes: <count>
- Namespaces: <count>

## Before / After

| Category | Baseline | Post-Hardening | Change |
|----------|----------|----------------|--------|
| CIS Benchmark Failures | ___ | ___ | -___% |
| Kubescape Failed Controls | ___ | ___ | -___% |
| Namespaces with NetworkPolicy | ___ | ___ | ___% |
| Namespaces with PSS Labels | ___ | ___ | ___% |
| cluster-admin Bindings (non-system) | ___ | ___ | ___ |
| Pods Running as Root | ___ | ___ | ___ |
| Pods Without Resource Limits | ___ | ___ | ___ |
| Kyverno Policies Enforcing | 0 | ___ | ___ |

## What Was Deployed
- [x] Kyverno admission control (___ policies enforcing)
- [x] NetworkPolicies (default-deny + per-service)
- [x] PSS labels (restricted on all app namespaces)
- [x] LimitRanges and ResourceQuotas
- [x] External Secrets Operator
- [x] RBAC least-privilege roles
- [x] CI/CD policy gates (Conftest)

## Remaining Items
- ___ findings accepted as exceptions (documented)
- ___ findings deferred to production team

## Evidence Files
All scan results in: Target-Projects/slot-1/mssp-outputs/
```

---

## What "Done" Looks Like

- CIS benchmark > 80%
- 0 Kyverno violations in enforce mode
- Every namespace has NetworkPolicy + PSS labels
- RBAC scoped to least privilege
- Secrets managed via ESO
- CI pipeline blocks policy violations
- Before/after evidence documented

The enterprise tools (Prisma Cloud, Wiz, ARMO) take over from here. They inherit a clean cluster instead of starting from scratch.

---

## What's Next

Platform hardening is done. Next packages:
- **03-runtime-security** — Falco, watchers, detection, incident response
- **04-cloud-security** — AWS controls, Terraform, IAM, GuardDuty
- **05-compliance-ready** — NIST mapping, FedRAMP evidence, POA&M
