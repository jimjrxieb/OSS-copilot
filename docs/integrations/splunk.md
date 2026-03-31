# Splunk Integration

> Any scanner output can go to Splunk via HTTP Event Collector (HEC).
> JSON in, indexed, searchable. Dashboards and alerts on top.

---

## What Splunk Expects

Splunk's HTTP Event Collector (HEC) accepts any JSON payload over HTTPS.
No special format required — send raw scanner JSON and Splunk indexes it.

```
Scanner → JSON output → curl POST to HEC endpoint → Splunk indexes it
```

---

## How to Format Your Findings

Splunk eats any JSON. Wrap scanner output in HEC format:

```json
{
    "event": { ... scanner JSON ... },
    "sourcetype": "oss-copilot:gitleaks",
    "source": "oss-copilot",
    "index": "security"
}
```

---

## The Command

### Setup: Get Your HEC Token

```
Splunk → Settings → Data Inputs → HTTP Event Collector → New Token
  Name: oss-copilot
  Index: security (or main)
  Source type: _json

Save the token — you'll use it in every curl call.
```

### Send Findings

```bash
SPLUNK_HEC="https://your-splunk:8088/services/collector/event"
SPLUNK_TOKEN="your-hec-token"
OUTPUT=/path/to/example-output

# --- 01-code findings ---

# Gitleaks → Splunk
curl -k -X POST "$SPLUNK_HEC" \
    -H "Authorization: Splunk $SPLUNK_TOKEN" \
    -d "{\"event\": $(cat $OUTPUT/01-code/gitleaks-results.json), \"sourcetype\": \"oss-copilot:gitleaks\", \"source\": \"oss-copilot\"}"

# Semgrep → Splunk
curl -k -X POST "$SPLUNK_HEC" \
    -H "Authorization: Splunk $SPLUNK_TOKEN" \
    -d "{\"event\": $(cat $OUTPUT/01-code/semgrep-results.json), \"sourcetype\": \"oss-copilot:semgrep\", \"source\": \"oss-copilot\"}"

# Trivy (dependencies) → Splunk
curl -k -X POST "$SPLUNK_HEC" \
    -H "Authorization: Splunk $SPLUNK_TOKEN" \
    -d "{\"event\": $(cat $OUTPUT/01-code/trivy-deps-results.json), \"sourcetype\": \"oss-copilot:trivy\", \"source\": \"oss-copilot\"}"

# Grype (dependencies) → Splunk
curl -k -X POST "$SPLUNK_HEC" \
    -H "Authorization: Splunk $SPLUNK_TOKEN" \
    -d "{\"event\": $(cat $OUTPUT/01-code/grype-results.json), \"sourcetype\": \"oss-copilot:grype\", \"source\": \"oss-copilot\"}"

# --- 02-cluster findings ---

# Checkov (K8s manifests) → Splunk
curl -k -X POST "$SPLUNK_HEC" \
    -H "Authorization: Splunk $SPLUNK_TOKEN" \
    -d "{\"event\": $(cat $OUTPUT/02-cluster/checkov-results.json), \"sourcetype\": \"oss-copilot:checkov\", \"source\": \"oss-copilot\"}"

# Polaris (K8s best practices) → Splunk
curl -k -X POST "$SPLUNK_HEC" \
    -H "Authorization: Splunk $SPLUNK_TOKEN" \
    -d "{\"event\": $(cat $OUTPUT/02-cluster/polaris-static.json), \"sourcetype\": \"oss-copilot:polaris\", \"source\": \"oss-copilot\"}"
```

### Batch Script (send all findings across all layers)

```bash
#!/usr/bin/env bash
# send-to-splunk.sh — Forward all scan results to Splunk HEC
# Usage: ./send-to-splunk.sh /path/to/example-output

SPLUNK_HEC="${SPLUNK_HEC_URL}"
SPLUNK_TOKEN="${SPLUNK_HEC_TOKEN}"
SCAN_DIR="${1:-MSSP/example-output}"

# Walk every layer's JSON files
for json_file in "$SCAN_DIR"/*//*.json "$SCAN_DIR"/*.json; do
    [ -f "$json_file" ] || continue
    filename=$(basename "$json_file" .json)
    echo "[*] Sending $filename to Splunk..."
    curl -k -s -X POST "$SPLUNK_HEC" \
        -H "Authorization: Splunk $SPLUNK_TOKEN" \
        -d "{\"event\": $(cat "$json_file"), \"sourcetype\": \"oss-copilot:$filename\", \"source\": \"oss-copilot\", \"time\": $(date +%s)}" \
        -o /dev/null -w "  HTTP %{http_code}\n"
done
```

---

## What It Looks Like in Splunk

```
Search: sourcetype="oss-copilot:*" | stats count by sourcetype

sourcetype                    count    layer
─────────────────────────── ────── ────────
oss-copilot:gitleaks           7    01-code
oss-copilot:semgrep           56    01-code
oss-copilot:trivy              4    01-code
oss-copilot:grype             70    01-code
oss-copilot:checkov           16    02-cluster
oss-copilot:polaris            0    02-cluster
```

### Useful SPL Queries

```spl
# All CRITICAL findings across all scanners
sourcetype="oss-copilot:*" (severity="CRITICAL" OR Severity="CRITICAL")
| stats count by sourcetype

# Secrets found over time
sourcetype="oss-copilot:gitleaks"
| timechart count by RuleID

# Dependency CVEs by package
sourcetype="oss-copilot:trivy"
| spath Results{}.Vulnerabilities{}.PkgName
| stats count by Results{}.Vulnerabilities{}.PkgName

# Trend: findings per scan over time
sourcetype="oss-copilot:*"
| timechart span=1d count by sourcetype
```

---

## When to Use This vs. Fix First

| Scenario | Forward to Splunk | Fix First |
|----------|------------------|-----------|
| Client runs Splunk SIEM | Yes — correlate with other security events | Both |
| SOC team monitors Splunk | Yes — findings appear in their workflow | Both |
| Building compliance dashboards | Yes — auditors love trend charts | Both |
| Pre-engagement assessment | No — overkill | Yes |

**The correlation play:** When your code findings (Semgrep) and runtime findings
(Falco) both land in Splunk, the SOC can correlate: "this SQL injection vulnerability
was found by Semgrep, AND Falco detected suspicious database queries from that
container." That cross-domain detection is what Splunk is built for.
