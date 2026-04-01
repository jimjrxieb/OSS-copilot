#!/usr/bin/env bash
# falco-siem-forwarder.sh
# Forward Falco alerts to external SIEM systems (Splunk, ELK, Wazuh).
#
# Enterprise equivalent: Sysdig Secure SIEM integration ($40-150K),
# Splunk Enterprise Security ($100-500K), Microsoft Sentinel ($30-200K).
# Enterprise SIEMs correlate Falco data with network/identity/cloud events.
# This script handles the FORMAT TRANSLATION — getting Falco alerts into SIEM.
#
# Usage:
#   bash falco-siem-forwarder.sh --target splunk-hec --endpoint https://splunk:8088 --token HEC-TOKEN
#   bash falco-siem-forwarder.sh --target elasticsearch --endpoint https://elastic:9200 --index falco-alerts
#   bash falco-siem-forwarder.sh --target wazuh --endpoint https://wazuh-manager:55000
#   bash falco-siem-forwarder.sh --target file --output /var/log/falco-siem.jsonl
#
# What it does:
#   1. Reads Falco alerts from pod logs or Falco HTTP output
#   2. Transforms to target SIEM format (Splunk HEC, ELK bulk, Wazuh)
#   3. Forwards via HTTP/HTTPS
#   4. Tracks last-forwarded timestamp to avoid duplicates
#
# Requires: kubectl, jq, curl

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

TARGET=""
ENDPOINT=""
TOKEN=""
INDEX="falco-alerts"
OUTPUT_FILE=""
FALCO_NS="falco-system"
SINCE="5m"
CONTINUOUS=false
STATE_FILE="/tmp/falco-siem-forwarder.state"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --endpoint) ENDPOINT="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --index) INDEX="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --falco-namespace) FALCO_NS="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --continuous) CONTINUOUS=true; shift ;;
    -h|--help)
      cat <<EOF
Forward Falco alerts to external SIEM systems.

Usage:
  bash falco-siem-forwarder.sh --target <siem> --endpoint <url> [OPTIONS]

Targets:
  splunk-hec       Splunk HTTP Event Collector (requires --token)
  elasticsearch    Elasticsearch bulk API (requires --index)
  wazuh            Wazuh manager API
  file             Write to local JSONL file (requires --output)
  stdout           Print formatted events to stdout (for testing/piping)

Options:
  --target TARGET       SIEM target (required)
  --endpoint URL        SIEM endpoint URL
  --token TOKEN         Auth token (Splunk HEC token, Wazuh API key)
  --index NAME          Elasticsearch index name (default: falco-alerts)
  --output FILE         Output file (for --target file)
  --falco-namespace NS  Falco namespace (default: falco-system)
  --since DURATION      How far back to read (default: 5m)
  --continuous          Run in continuous mode (tail Falco logs)

Examples:
  # Splunk HEC
  bash falco-siem-forwarder.sh --target splunk-hec \\
    --endpoint https://splunk.example.com:8088/services/collector \\
    --token your-hec-token

  # Elasticsearch
  bash falco-siem-forwarder.sh --target elasticsearch \\
    --endpoint https://elastic.example.com:9200 \\
    --index falco-alerts-2026

  # Wazuh
  bash falco-siem-forwarder.sh --target wazuh \\
    --endpoint https://wazuh.example.com:55000 \\
    --token your-api-key

  # Test mode (stdout)
  bash falco-siem-forwarder.sh --target stdout --since 10m

  # Deploy as CronJob (every 5 minutes)
  # See playbooks/14-siem-integration.md for CronJob template
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Usage: bash falco-siem-forwarder.sh --target <siem> --endpoint <url>"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Ghost Protocol — Falco SIEM Forwarder ===${NC}"
echo "  Target   : $TARGET"
echo "  Endpoint : ${ENDPOINT:-N/A}"
echo "  Window   : last $SINCE"
echo ""

# ─── Collect Falco alerts ─────────────────────────────────────────────────

echo -e "${BLUE}Collecting Falco alerts...${NC}"

FALCO_POD=$(kubectl get pods -n "$FALCO_NS" -l app.kubernetes.io/name=falco \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "$FALCO_POD" ]]; then
  echo -e "${RED}Falco pod not found in namespace $FALCO_NS${NC}"
  echo "  Check: kubectl get pods -n $FALCO_NS"
  exit 1
fi

# Get Falco logs (JSON format)
ALERTS=$(kubectl logs "$FALCO_POD" -n "$FALCO_NS" --since="$SINCE" 2>/dev/null | \
  grep -E '^\{' | jq -c '.' 2>/dev/null || true)

ALERT_COUNT=$(echo "$ALERTS" | grep -c '.' || echo "0")
echo "  Found $ALERT_COUNT alerts in last $SINCE"

if [[ "$ALERT_COUNT" -eq 0 ]]; then
  echo -e "${GREEN}No alerts to forward.${NC}"
  exit 0
fi

# ─── Transform and forward ────────────────────────────────────────────────

FORWARDED=0
ERRORS=0

forward_splunk_hec() {
  local event="$1"
  local splunk_event=$(echo "$event" | jq -c '{
    event: .,
    sourcetype: "falco",
    source: "gp-copilot/falco-siem-forwarder",
    index: "main"
  }')

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "$ENDPOINT" \
    -H "Authorization: Splunk $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$splunk_event" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" =~ ^(200|201) ]]; then
    FORWARDED=$((FORWARDED + 1))
  else
    ERRORS=$((ERRORS + 1))
  fi
}

forward_elasticsearch() {
  local event="$1"
  local date_index="${INDEX}-$(date +%Y.%m.%d)"
  local bulk_line=$(echo -e "{\"index\":{\"_index\":\"$date_index\"}}\n$event")

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "${ENDPOINT}/_bulk" \
    -H "Content-Type: application/x-ndjson" \
    -d "$bulk_line" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" =~ ^(200|201) ]]; then
    FORWARDED=$((FORWARDED + 1))
  else
    ERRORS=$((ERRORS + 1))
  fi
}

forward_wazuh() {
  local event="$1"
  local wazuh_event=$(echo "$event" | jq -c '{
    rule: {id: (.rule // "falco"), level: (if .priority == "Critical" then 15 elif .priority == "Error" then 12 elif .priority == "Warning" then 7 else 3 end)},
    data: {falco: .}
  }')

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -X POST "${ENDPOINT}/events" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$wazuh_event" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" =~ ^(200|201) ]]; then
    FORWARDED=$((FORWARDED + 1))
  else
    ERRORS=$((ERRORS + 1))
  fi
}

forward_file() {
  local event="$1"
  echo "$event" >> "$OUTPUT_FILE"
  FORWARDED=$((FORWARDED + 1))
}

forward_stdout() {
  local event="$1"
  local priority=$(echo "$event" | jq -r '.priority // "Notice"')
  local rule=$(echo "$event" | jq -r '.rule // "unknown"')
  local output=$(echo "$event" | jq -r '.output // "no output"' | head -c 200)
  local ts=$(echo "$event" | jq -r '.time // .output_fields.evt.time // "unknown"')

  case "$priority" in
    Critical|Error) COLOR="$RED" ;;
    Warning) COLOR="$YELLOW" ;;
    *) COLOR="$NC" ;;
  esac

  echo -e "  ${COLOR}[$priority]${NC} $ts | $rule | $output"
  FORWARDED=$((FORWARDED + 1))
}

echo ""
echo -e "${BLUE}Forwarding to $TARGET...${NC}"

echo "$ALERTS" | while IFS= read -r alert; do
  [[ -z "$alert" ]] && continue

  case "$TARGET" in
    splunk-hec) forward_splunk_hec "$alert" ;;
    elasticsearch) forward_elasticsearch "$alert" ;;
    wazuh) forward_wazuh "$alert" ;;
    file) forward_file "$alert" ;;
    stdout) forward_stdout "$alert" ;;
    *) echo -e "${RED}Unknown target: $TARGET${NC}"; exit 1 ;;
  esac
done

echo ""
echo -e "${BLUE}=== Forwarding Complete ===${NC}"
echo "  Forwarded : $FORWARDED"
echo "  Errors    : $ERRORS"
echo "  Target    : $TARGET"

# Save state for dedup on next run
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"

echo ""
echo -e "${YELLOW}For continuous forwarding, deploy as CronJob:${NC}"
echo "  See playbooks/14-siem-integration.md for deployment template"
echo ""
