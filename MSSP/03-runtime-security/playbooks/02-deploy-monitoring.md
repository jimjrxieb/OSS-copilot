# 02 — Deploy Monitoring

> Set up Prometheus alerts and Grafana dashboards so Falco findings are visible and actionable.

Falco detects. Prometheus alerts. Grafana visualizes. Without this step, Falco events go to container logs and nobody sees them.

In production, Sysdig Secure and Datadog have built-in dashboards. This is the open source equivalent.

---

## What You Need

- Playbook 01 completed (Falco deployed)
- Prometheus + Grafana already running in the cluster (part of 02-platform-hardening or pre-existing)

---

## Step 1: Deploy Prometheus Alert Rules

```bash
kubectl apply -f monitoring/falco-alerts.yaml -n monitoring
kubectl apply -f monitoring/log-alerts.yaml -n monitoring
```

**Falco alerts included:**

| Alert | Fires When |
|-------|-----------|
| FalcoHighPriorityAlert | Critical/Emergency severity Falco event |
| FalcoContainerShellSpawn | Shell spawned inside a container |
| FalcoPrivilegeEscalation | Privilege escalation attempt detected |
| FalcoSensitiveFileAccess | /etc/shadow, /etc/passwd, or SSH key access |
| FalcoCryptoMiningDetected | Known mining pool DNS lookup |

---

## Step 2: Import Grafana Dashboards

```bash
# Via ConfigMap (if Grafana watches for ConfigMaps)
kubectl create configmap grafana-falco-dashboard \
  --from-file=monitoring/runtime-security.json \
  --namespace monitoring
kubectl label configmap grafana-falco-dashboard grafana_dashboard=1 -n monitoring

kubectl create configmap grafana-falco-alerts \
  --from-file=monitoring/falco-alerts.json \
  --namespace monitoring
kubectl label configmap grafana-falco-alerts grafana_dashboard=1 -n monitoring

kubectl create configmap grafana-log-dashboard \
  --from-file=monitoring/log-dashboard.json \
  --namespace monitoring
kubectl label configmap grafana-log-dashboard grafana_dashboard=1 -n monitoring
```

Or import via Grafana API:
```bash
GRAFANA_URL=http://localhost:3000
GRAFANA_API_KEY=<your-key>

for dashboard in monitoring/*.json; do
  curl -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H "Authorization: Bearer $GRAFANA_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"dashboard\": $(cat $dashboard), \"overwrite\": true}"
done
```

---

## Step 3: Verify

```bash
# Check alert rules are loaded
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.name | startswith("Falco")) | .name'
kill %1

# Check dashboards exist in Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000 &
# Open http://localhost:3000 and look for "Runtime Security" and "Falco Alerts" dashboards
kill %1
```

---

## Next Step

Go to [03-deploy-logging.md](03-deploy-logging.md) to centralize logs.
