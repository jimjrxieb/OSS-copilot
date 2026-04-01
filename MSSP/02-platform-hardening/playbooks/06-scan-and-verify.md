# 06 — Scan and Verify

> Scan the live cluster after hardening. Prove the fixes worked.

You've applied fixes, deployed admission control, locked down RBAC, added NetworkPolicies, and set up secrets management. Now scan the live cluster to prove it's actually hardened.

Same scanners that enterprise tools (Wiz, Prisma Cloud, ARMO) use under the hood.

---

## What You Need

- Playbooks 00-05 completed
- Scanning tools installed (playbook 00 handled this)

---

## Step 1: Run Kubescape (NSA/CISA + MITRE)

```bash
kubescape scan --format pretty-printer --output $OUTPUT_DIR/kubescape-live.json
```

This scans live workloads (not YAML files) against the NSA/CISA hardening guide and MITRE ATT&CK framework.

---

## Step 2: Run kube-bench (CIS Benchmark)

```bash
kube-bench run --json > $OUTPUT_DIR/kube-bench-live.json
kube-bench run 2>/dev/null | tail -20
```

**Note:** On EKS, many control plane checks will fail because you can't change managed API server flags. Focus on the worker node and workload checks.

---

## Step 3: Run Polaris (Best Practices)

```bash
polaris audit --format=pretty --only-show-failed-tests
polaris audit --format=json > $OUTPUT_DIR/polaris-live.json
```

---

## Step 4: Scan Running Images

```bash
# Get all images running in the cluster
kubectl get pods --all-namespaces -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' | sort -u > $OUTPUT_DIR/running-images.txt

# Scan each for CVEs
while read img; do
  echo "=== $img ==="
  trivy image --severity HIGH,CRITICAL "$img" 2>/dev/null | tail -5
done < $OUTPUT_DIR/running-images.txt
```

---

## Step 5: Check Exposed Services

```bash
# LoadBalancer services (publicly reachable)
kubectl get svc --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name) \(.status.loadBalancer.ingress[0].hostname // "pending")"'

# NodePort services (reachable on node IPs)
kubectl get svc --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.type=="NodePort") | "\(.metadata.namespace)/\(.metadata.name) port:\(.spec.ports[0].nodePort)"'
```

Every exposed service should be intentional and documented.

---

## Step 6: Compare Before and After

```bash
BEFORE=$OUTPUT_DIR/cluster-audit
AFTER=$OUTPUT_DIR

echo "=== Kubescape ==="
echo "Before: $(jq '[.results[]? | select(.status=="failed")] | length' $BEFORE/kubescape.json 2>/dev/null || echo N/A)"
echo "After:  $(jq '[.results[]? | select(.status=="failed")] | length' $AFTER/kubescape-live.json 2>/dev/null || echo N/A)"

echo "=== CIS Benchmark ==="
echo "Before: $(jq '[.Controls[].tests[].results[] | select(.status=="FAIL")] | length' $BEFORE/kube-bench.json 2>/dev/null || echo N/A)"
echo "After:  $(jq '[.Controls[].tests[].results[] | select(.status=="FAIL")] | length' $AFTER/kube-bench-live.json 2>/dev/null || echo N/A)"
```

---

## What "Clean" Looks Like

- 0 pods running as root (except documented exceptions)
- 0 missing resource limits
- 0 namespaces without NetworkPolicy
- 0 non-system cluster-admin bindings
- All namespaces have PSS labels
- CIS benchmark score > 80%
- Kubescape score > 80%
- No CRITICAL CVEs in running images

---

## Next Step

Go to [07-wire-cicd.md](07-wire-cicd.md) to add policy checks to CI/CD.
