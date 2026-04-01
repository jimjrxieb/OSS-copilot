# 07 — SIEM Integration

> Forward Falco alerts and cluster events to your SIEM so everything is in one place.

Falco stores events in container logs. That works for debugging but not for incident response. This playbook forwards alerts to your production SIEM — Splunk, Elasticsearch, or Wazuh.

In production, the SIEM team owns the pipeline. This gets the data flowing so they can build their dashboards and correlation rules.

---

## What You Need

- Playbook 06 completed (Falco tuned)
- SIEM endpoint URL and credentials

---

## Step 1: Test the Forwarder

```bash
# Test with stdout (verify it works before sending to SIEM)
bash tools/falco-siem-forwarder.sh --target stdout
```

---

## Step 2: Configure Your Target

### Splunk HEC

```bash
bash tools/falco-siem-forwarder.sh \
  --target splunk-hec \
  --url https://splunk.example.com:8088/services/collector \
  --token <HEC-token> \
  --index idx_security
```

### Elasticsearch

```bash
bash tools/falco-siem-forwarder.sh \
  --target elasticsearch \
  --url https://elastic.example.com:9200 \
  --index falco-alerts
```

### Wazuh

```bash
bash tools/falco-siem-forwarder.sh \
  --target wazuh \
  --url https://wazuh.example.com:1514
```

---

## Step 3: Deploy as CronJob

For continuous forwarding, deploy as a Kubernetes CronJob:

```bash
bash tools/falco-siem-forwarder.sh \
  --target splunk-hec \
  --url <url> \
  --token <token> \
  --deploy-cronjob \
  --interval 5m
```

---

## Step 4: Verify in SIEM

- Search for Falco events in your SIEM
- Confirm alert severity levels are mapped correctly
- Confirm timestamps are in UTC
- Confirm namespace/pod/container metadata is present

---

## What Gets Forwarded

| Field | Description |
|-------|------------|
| `timestamp` | When the event occurred (UTC) |
| `priority` | Falco severity (Emergency, Alert, Critical, Error, Warning) |
| `rule` | Which Falco rule fired |
| `output` | Human-readable alert message |
| `source` | Container/pod/namespace that triggered it |
| `tags` | MITRE ATT&CK technique IDs |

---

## Next Step

Go to [08-incident-response.md](08-incident-response.md) to set up containment and forensics procedures.
