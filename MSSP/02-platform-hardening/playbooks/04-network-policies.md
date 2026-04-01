# 04 — Network Policies

> Generate and deploy per-service NetworkPolicies so pods can only talk to what they need.

By default, every pod in Kubernetes can talk to every other pod. That means if one pod gets compromised, the attacker can reach everything. NetworkPolicies fix this.

In production, Calico Enterprise or Cilium Enterprise manage this with GUI dashboards and flow visualization. This gets your policies written and tested in staging.

---

## What You Need

- Playbook 01 completed (default-deny already applied by `fix-cluster-security.sh`)
- `kubectl` access

---

## Step 1: Check Current Coverage

```bash
# Which namespaces have NetworkPolicies?
kubectl get networkpolicy --all-namespaces

# Which namespaces are wide open?
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get networkpolicy -n $ns --no-headers 2>/dev/null | wc -l)
  [ "$count" -eq 0 ] && echo "OPEN: $ns"
done
```

If you ran playbook 01, every namespace should have a default-deny policy. Now you add the per-service "allow" rules.

---

## Step 2: Generate Policies

```bash
# Dry-run — see what would be generated
bash tools/network-policy-generator.sh --namespace <namespace> --dry-run

# Generate for one namespace
bash tools/network-policy-generator.sh --namespace <namespace> --output $OUTPUT_DIR/network-policies/
```

**What it generates:**
1. **Default deny** — blocks all ingress and egress (if not already present)
2. **Allow DNS egress** — pods need to resolve DNS
3. **Per-service ingress** — allows traffic from services that actually call this one
4. **Per-service egress** — allows traffic to services this one actually calls

---

## Step 3: Review the Generated Policies

```bash
ls $OUTPUT_DIR/network-policies/
cat $OUTPUT_DIR/network-policies/<service>-netpol.yaml
```

**Check:**
- Does the ingress list match who actually calls this service?
- Does the egress list match what this service actually talks to?
- Are ports correct?

---

## Step 4: Test on One Namespace First

```bash
# Apply to a non-critical namespace
kubectl apply -f $OUTPUT_DIR/network-policies/ -n <test-namespace>

# Verify the app still works
kubectl port-forward svc/<service> 8080:80 -n <test-namespace>
curl http://localhost:8080/healthz
```

If something breaks, the service can't reach a dependency. Add the missing egress rule.

---

## Step 5: Apply to All Namespaces

```bash
# Generate for all namespaces
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v kube-); do
  bash tools/network-policy-generator.sh --namespace $ns --output $OUTPUT_DIR/network-policies/$ns/
done

# Apply
kubectl apply -R -f $OUTPUT_DIR/network-policies/
```

---

## Step 6: Verify

```bash
# Count policies per namespace
kubectl get networkpolicy --all-namespaces --no-headers | awk '{print $1}' | sort | uniq -c

# Test lateral movement is blocked
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -n <namespace> -- \
  curl -s --max-time 3 http://<service-in-another-namespace>.<other-ns>.svc.cluster.local
# Expected: timeout (blocked by NetworkPolicy)
```

---

## Flow Visualization (Optional)

If you have Cilium as your CNI:
```bash
# Install Hubble for flow visualization
cilium hubble enable
cilium hubble ui
# Opens a browser showing actual network flows — great for finding missing rules
```

---

## Next Step

Go to [05-secrets-management.md](05-secrets-management.md) to set up External Secrets.
