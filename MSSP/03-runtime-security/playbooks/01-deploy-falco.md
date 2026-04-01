# 01 — Deploy Falco

> Deploy Falco for runtime syscall monitoring. It watches what containers actually do — not what the YAML says they should do.

Falco is the open source version of what Sysdig Secure and CrowdStrike Falcon do. It monitors kernel-level system calls and fires alerts when something suspicious happens: shell spawns in containers, crypto mining DNS lookups, privilege escalation attempts, unexpected network connections.

Deploy this BEFORE the application goes live. You want Falco watching when the first pod starts.

---

## What You Need

- Playbook 00 completed (prerequisites installed)
- `kubectl` and `helm` access
- Your paths set:
  ```bash
  export OUTPUT_DIR=../../Target-Projects/slot-1/mssp-outputs
  ```

---

## Step 1: Choose Your Platform Config

Pick the Helm values file that matches your cluster:

| Platform | Values File | Notes |
|----------|------------|-------|
| **EKS** | `templates/deployment-configs/aws-eks.yaml` | eBPF driver, IRSA support |
| **AKS** | `templates/deployment-configs/azure-aks.yaml` | eBPF driver |
| **GKE** | `templates/deployment-configs/gcp-gke.yaml` | eBPF driver |
| **On-prem / kubeadm** | `templates/deployment-configs/on-prem.yaml` | Kernel module driver |
| **Minimal (testing)** | `templates/deployment-configs/minimal.yaml` | Lightweight, fewer rules |
| **Full-featured** | `templates/deployment-configs/full-featured.yaml` | Everything enabled |

---

## Step 2: Deploy

```bash
bash tools/deploy.sh --values templates/deployment-configs/aws-eks.yaml
```

Or manually:
```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  -f templates/deployment-configs/aws-eks.yaml

# Deploy the exporter (Prometheus metrics)
helm install falco-exporter falcosecurity/falco-exporter \
  --namespace falco
```

---

## Step 3: Verify

```bash
bash tools/health-check.sh
```

Or manually:
```bash
# Falco pods running?
kubectl get pods -n falco

# Falco generating events?
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20

# Exporter serving metrics?
kubectl port-forward -n falco svc/falco-exporter 9376:9376 &
curl -s http://localhost:9376/metrics | grep falco_events
kill %1
```

---

## Step 4: Load Custom Rules

The default Falco rules are noisy. Load the tuned rules from this package:

```bash
# Copy rules into the Falco ConfigMap
kubectl create configmap falco-custom-rules \
  --from-file=falco-rules/ \
  --namespace falco \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Falco to pick up new rules
kubectl rollout restart daemonset/falco -n falco
```

**Rules included:**

| Rule File | What It Detects |
|-----------|----------------|
| `crypto-mining.yaml` | DNS lookups to mining pools, CPU-intensive processes |
| `data-exfiltration.yaml` | Large outbound transfers, unexpected external connections |
| `privilege-escalation.yaml` | setuid/setgid, capability changes, nsenter |
| `persistence.yaml` | Crontab writes, systemd unit creation, authorized_keys modification |
| `k8s-audit.yaml` | K8s API abuse — secret reads, exec into pods, RBAC changes |
| `allowlist.yaml` | Known-good exceptions to reduce noise |

---

## Step 5: Observe (Don't Act Yet)

Let Falco run for at least a few hours before tuning. Watch the alert volume:

```bash
# Count alerts per rule in the last hour
kubectl logs -n falco -l app.kubernetes.io/name=falco --since=1h | \
  grep "Warning\|Error\|Critical" | \
  awk -F'rule=' '{print $2}' | sort | uniq -c | sort -rn | head -20
```

If alert volume is >100/hour, you'll tune it in playbook 06.

---

## Next Step

Go to [02-deploy-monitoring.md](02-deploy-monitoring.md) to set up Prometheus alerts and Grafana dashboards for Falco.
