# Playbook 05: Enforce and Track

> Move from audit mode to enforcement. Block non-compliant workloads.
> Measure improvement. Prove it worked.
>
> **Time:** ~10 minutes per enforcement phase
> **Prerequisites:** Kyverno deployed in audit mode ([03-deploy-admission-control.md](03-deploy-admission-control.md))

---

## The Rule

**Never enforce everything at once.** Progressive rollout:
1. Confirm violations = 0 for each policy
2. Enforce critical policies first
3. Wait a week. Confirm nothing broke.
4. Enforce the next batch.

If something breaks, you only broke one policy group — not everything.

---

## Step 1: Confirm Violations Are Zero

Before enforcing any policy, its violations must be zero:

```bash
# Check current violations per policy
kubectl get policyreports -A -o json | python3 -c "
import json, sys
from collections import Counter
data = json.load(sys.stdin)
violations = Counter()
for report in data.get('items', []):
    for result in report.get('results', []):
        if result.get('result') == 'fail':
            violations[result.get('policy', 'unknown')] += 1
if not violations:
    print('No violations found — ready to enforce!')
else:
    print('Violations found — fix these before enforcing:')
    for policy, count in violations.most_common():
        print(f'  {policy}: {count} violations')
"
```

**If violations > 0:** Go fix the workloads first.
- Add `securityContext` to pods that are missing it
- Add `resources.limits` to pods without them
- Pin image tags (replace `:latest` with specific versions)
- Drop capabilities, set `runAsNonRoot: true`

Then redeploy and check again. Don't enforce until clean.

---

## Step 2: Progressive Enforcement

### Week 1 — Critical Policies

These are the most important. If these aren't enforced, an attacker can
escalate from a compromised container to the entire node.

```bash
# Enforce: disallow privileged containers
kubectl patch clusterpolicy disallow-privileged \
    --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'

# Enforce: require non-root
kubectl patch clusterpolicy require-run-as-nonroot \
    --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'

# Verify
kubectl get clusterpolicies -o custom-columns=NAME:.metadata.name,ACTION:.spec.validationFailureAction
```

**Test it works:**
```bash
# Try to deploy a privileged container (should be rejected)
kubectl run test-privileged --image=nginx \
    --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}' \
    --dry-run=server

# Expected: Error from server: admission webhook denied the request
```

### Week 2 — High Severity

```bash
kubectl patch clusterpolicy require-drop-all-capabilities \
    --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'

kubectl patch clusterpolicy require-resource-limits \
    --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
```

### Week 3 — Everything Else

```bash
kubectl patch clusterpolicy disallow-latest-tag \
    --type merge -p '{"spec":{"validationFailureAction":"Enforce"}}'
```

---

## Step 3: Before vs. After Comparison

### Re-run the audit tools:

```bash
# From the 02-cluster directory
./scan-cis.sh
./scan-rbac.sh
./scan-policies.sh
```

### Compare scores:

```bash
BASELINE=".oss-copilot/cluster-baseline-YYYYMMDD"   # Your first audit
POSTFIX=".oss-copilot/cluster-postfix-$(date +%Y%m%d)"
mkdir -p "$POSTFIX"

# Save new results
polaris audit --format json > "$POSTFIX/polaris.json" 2>/dev/null

# Compare Polaris scores
BEFORE=$(python3 -c "import json; print(json.load(open('$BASELINE/polaris.json')).get('ClusterInfo',{}).get('Score','?'))" 2>/dev/null)
AFTER=$(python3 -c "import json; print(json.load(open('$POSTFIX/polaris.json')).get('ClusterInfo',{}).get('Score','?'))" 2>/dev/null)
echo "Polaris Score: $BEFORE → $AFTER"
```

### Full comparison:

```bash
python3 - "$BASELINE" "$POSTFIX" << 'PYTHON'
import json, sys, os

baseline = sys.argv[1]
postfix = sys.argv[2]

print(f"\n{'Metric':<35} {'Before':>8} {'After':>8}")
print("-" * 55)

# Polaris score
for label, path in [("Before", baseline), ("After", postfix)]:
    try:
        data = json.load(open(f"{path}/polaris.json"))
        score = data.get("ClusterInfo", {}).get("Score", "N/A")
    except:
        score = "N/A"
    if label == "Before":
        before_score = score
    else:
        print(f"{'Polaris Score':<35} {before_score:>8} {score:>8}")

# Policy violations
for label, path in [("Before", baseline), ("After", postfix)]:
    try:
        data = json.load(open(f"{path}/polaris.json"))
        results = data.get("Results", [])
        dangers = sum(1 for r in results
                      for m in r.get("PodResult", {}).get("Results", {}).values()
                      if not m.get("Success") and m.get("Severity") == "danger")
    except:
        dangers = "N/A"
    if label == "Before":
        before_dangers = dangers
    else:
        print(f"{'Polaris Danger Findings':<35} {str(before_dangers):>8} {str(dangers):>8}")

print()
PYTHON
```

---

## Step 4: What "Done" Looks Like

| Metric | Target |
|--------|--------|
| Polaris score | **80+** (from whatever you started at) |
| Kubescape compliance | **80%+** |
| Privileged containers (app) | **0** |
| cluster-admin bindings (non-system) | **Named individuals only** |
| Namespaces with NetworkPolicy | **All** |
| Kyverno enforcement | **Critical + High policies enforcing** |
| PSA labels on namespaces | **All non-system namespaces** |

---

## Step 5: Ongoing Monitoring

### Monthly audit:

```bash
# Re-run the full audit monthly
./scan-cis.sh
./scan-rbac.sh
./scan-policies.sh

# Save with date
MONTHLY=".oss-copilot/cluster-scan-$(date +%Y%m%d)"
mkdir -p "$MONTHLY"
polaris audit --format json > "$MONTHLY/polaris.json"
kubescape scan framework nsa --format json --output "$MONTHLY/kubescape.json" 2>/dev/null
```

### Watch Kyverno reports:

```bash
# Weekly check — any new violations since enforcement?
kubectl get policyreports -A -o json | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = sum(r.get('summary', {}).get('fail', 0) for r in data.get('items', []))
if total == 0:
    print('Clean — no policy violations')
else:
    print(f'WARNING: {total} policy violations detected')
"
```

### Track your trend:

```
Cluster Security Trend
──────────────────────
Date          Polaris   Kubescape   Violations   Enforcing
────────      ───────   ─────────   ──────────   ─────────
Mar 15        62/100    67%         47           0 policies
Mar 22        74/100    75%         12           3 policies (critical)
Mar 29        82/100    83%         3            5 policies (critical+high)
Apr 5         88/100    89%         0            5 policies (all)
```

That trend line is your proof. It shows continuous improvement backed by
policy enforcement — not just one-time scanning.

---

## Sharing Results

### For your team:

> "We went from Polaris 62 to 88 in three weeks. Five Kyverno policies are
> enforcing — no privileged containers, no root, resource limits required,
> capabilities dropped, no :latest tags. The cluster blocks non-compliant
> deployments at the API server."

### For auditors:

> "Admission control deployed with progressive enforcement over 3 weeks.
> CIS benchmark compliance improved from 67% to 89%. PolicyReports show
> zero active violations. All application namespaces have NetworkPolicy
> and PSA labels."

---

## When to Scan Other Layers

| Your Environment Has... | Next Step |
|------------------------|-----------|
| Application code | [01-code/](../../01-code/) — SAST, secrets, dependencies |
| Dockerfiles / container images | [03-container/](../../03-container/) — image CVEs, Dockerfile hardening, Falco |
| AWS / cloud infrastructure | [04-cloud/](../../04-cloud/) — Prowler, Checkov, IaC scanning |
| Compliance requirements | [05-compliance/](../../05-compliance/) — NIST mapping, evidence packaging |

---

## You Did It

If you followed all six playbooks, you now have:
1. A cluster profile (Playbook 00)
2. A security baseline with scores (Playbook 01)
3. Understanding of what the findings mean (Playbook 02)
4. Admission control preventing new issues (Playbook 03)
5. RBAC scoped to least privilege (Playbook 04)
6. Progressive enforcement with before/after proof (this playbook)

You just cleared the routine misconfigurations and deployed admission control
to prevent them from coming back. When Wiz or Prisma Cloud scan this cluster
now, they find only the cross-domain risks — attack paths connecting K8s
misconfig to cloud IAM to data exposure. That's what they're built for.

Open source handled the load. Enterprise tools handle the signal.
