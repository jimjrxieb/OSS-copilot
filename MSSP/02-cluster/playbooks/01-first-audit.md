# Playbook 01: Your First Cluster Audit

> Run CIS benchmarks, Kubescape, and Polaris against your cluster.
> Find out how hardened (or not) your Kubernetes environment really is.
>
> **Time:** ~15 minutes
> **Prerequisites:** kubectl access, tools installed (script helps with that)

---

## Step 1: Install the Audit Tools

You need three tools. Each scans for different things.

```bash
# kube-bench — CIS Kubernetes Benchmark (node + control plane config)
brew install kube-bench
# Or: https://github.com/aquasecurity/kube-bench/releases

# Kubescape — NSA/CISA hardening, MITRE ATT&CK mapping
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | bash
# Or: brew install kubescape

# Polaris — deployment best practices, gives you a score
brew install polaris
# Or: https://github.com/FairwindsOps/polaris/releases
```

Don't have all three? That's fine — the scan scripts skip what's missing.

---

## Step 2: Run the Audit

```bash
# From the 02-cluster directory
./scan-cis.sh        # CIS benchmarks (kube-bench + Kubescape)
./scan-rbac.sh       # RBAC permissions audit
./scan-policies.sh   # Admission control + policy posture
```

Or run tools directly:

```bash
# kube-bench — CIS benchmark
kube-bench run --json > kube-bench-results.json
kube-bench run  # Human-readable output

# Kubescape — NSA hardening + CIS
kubescape scan framework nsa --format pretty
kubescape scan framework cis-v1.23-t1.0.1 --format json --output kubescape-results.json

# Polaris — best practices score
polaris audit --format pretty
polaris audit --format json > polaris-results.json
```

---

## Step 3: Understand Your Scores

### kube-bench (CIS Benchmark)

```
[PASS] 1.2.1 Ensure that the --anonymous-auth argument is set to false
[FAIL] 1.2.2 Ensure that the --token-auth-file parameter is not set
[WARN] 1.2.3 Ensure that the --DenyServiceExternalIPs is not set

== Summary ==
45 checks PASS
12 checks FAIL
8 checks WARN
```

| Result | What It Means | Action |
|--------|--------------|--------|
| **PASS** | Meets CIS benchmark | Nothing to do |
| **FAIL** | Violates CIS benchmark | Fix these (kube-bench tells you how) |
| **WARN** | Needs manual verification | Check these when you have time |

**On managed K8s (EKS/GKE/AKS):** Many control plane checks will WARN because
you can't access the control plane. That's expected — your cloud provider handles
those. Focus on worker node checks.

### Kubescape (Risk Score)

```
Overall compliance score: 67%

┌──────────────────────────────┬───────────┬──────────┐
│ Control                      │ Resources │ Status   │
├──────────────────────────────┼───────────┼──────────┤
│ Privileged container         │  3        │ Failed   │
│ Resource limits              │  27       │ Failed   │
│ NetworkPolicy                │  9 ns     │ Failed   │
│ Non-root containers          │  12       │ Failed   │
│ API server access            │  5        │ Failed   │
└──────────────────────────────┴───────────┴──────────┘
```

**Target score:** 80%+ for a hardened cluster. Below 60% means significant
work needed. Above 90% is excellent.

### Polaris (Best Practices Score)

```
Score: 62/100

Checks:
  ✅ Image tag is specified          (15/15 deployments)
  ❌ CPU limits are set              (3/15 deployments)
  ❌ Memory limits are set           (5/15 deployments)
  ❌ Runs as non-root                (6/15 deployments)
  ❌ Health probes configured        (7/15 deployments)
```

**Target score:** 80+ for production. Below 60 means most deployments are
missing basic security and reliability settings.

---

## Step 4: Save Your Baseline

```bash
OUTPUT_DIR=".oss-copilot/cluster-baseline-$(date +%Y%m%d)"
mkdir -p "$OUTPUT_DIR"

# Save all results
kube-bench run --json > "$OUTPUT_DIR/kube-bench.json" 2>/dev/null
kubescape scan framework nsa --format json --output "$OUTPUT_DIR/kubescape-nsa.json" 2>/dev/null
polaris audit --format json > "$OUTPUT_DIR/polaris.json" 2>/dev/null

# Quick summary
echo "=== Cluster Security Baseline ===" > "$OUTPUT_DIR/SUMMARY.md"
echo "Date: $(date)" >> "$OUTPUT_DIR/SUMMARY.md"
echo "" >> "$OUTPUT_DIR/SUMMARY.md"
echo "Polaris Score: $(python3 -c "import json; d=json.load(open('$OUTPUT_DIR/polaris.json')); print(d.get('ClusterInfo',{}).get('Score','N/A'))" 2>/dev/null)/100" >> "$OUTPUT_DIR/SUMMARY.md"

echo "Baseline saved to $OUTPUT_DIR"
```

---

## Step 5: Quick Wins You Can Fix Right Now

After your first audit, these are the most common findings. Each one is a
5-minute fix in your Kubernetes manifests:

### Add securityContext to every container:

```yaml
# Add this to each container spec
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Add resource limits:

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Add health probes:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
```

### Add PSA labels to namespaces:

```bash
# Warn mode first (doesn't block, just warns)
kubectl label namespace my-app \
    pod-security.kubernetes.io/warn=restricted \
    pod-security.kubernetes.io/audit=restricted
```

---

## Next Steps

- Understand what the audit findings mean → [02-read-your-audit.md](02-read-your-audit.md)
- Jump to admission control → [03-deploy-admission-control.md](03-deploy-admission-control.md)
