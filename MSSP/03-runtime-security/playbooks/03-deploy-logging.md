# 03 — Deploy Logging

> Deploy Fluent Bit + Loki so container logs and Falco events are searchable in one place.

Without centralized logging, you're running `kubectl logs` across 50 pods hoping to find the one that matters. Fluent Bit collects, Loki stores, Grafana searches.

In production, Splunk, Datadog, or Elastic take over. This is your staging log pipeline.

---

## What You Need

- Playbooks 01-02 completed (Falco + monitoring deployed)
- Prometheus + Grafana running

---

## Step 1: Deploy Fluent Bit + Loki

```bash
bash tools/deploy-logging.sh
```

Or manually:
```bash
# Loki (log storage)
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace logging \
  --create-namespace \
  -f templates/observability/loki-values.yaml

# Fluent Bit (log collector)
helm install fluent-bit grafana/fluent-bit \
  --namespace logging \
  -f templates/observability/fluent-bit-values.yaml
```

---

## Step 2: Add Loki as Grafana Datasource

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000 &
# Grafana > Configuration > Data Sources > Add > Loki
# URL: http://loki.logging.svc.cluster.local:3100
kill %1
```

---

## Step 3: Query Logs

In Grafana > Explore > Loki:

```logql
# All Falco alerts
{namespace="falco"} |= "Warning"

# Falco alerts for a specific namespace
{namespace="falco"} |= "Warning" |= "app-namespace"

# Application logs with errors
{namespace="app"} |= "error" | json | level="ERROR"

# Kubernetes events
{job="kube-events"}
```

---

## Step 4: Verify

```bash
# Fluent Bit pods running on every node?
kubectl get pods -n logging -l app.kubernetes.io/name=fluent-bit

# Loki accepting logs?
kubectl port-forward -n logging svc/loki 3100:3100 &
curl -s http://localhost:3100/ready
kill %1

# Logs flowing in Grafana?
# Grafana > Explore > Loki > {namespace="falco"} > should show results
```

---

## Log Retention

Default retention in `loki-values.yaml` is 7 days. Adjust for your needs:
- Dev: 3 days
- Staging: 7 days
- Compliance: 30-90 days (but use the production SIEM for that)

---

## Next Step

Go to [04-verify-container-hardening.md](04-verify-container-hardening.md) to validate containers before the application deploys.
