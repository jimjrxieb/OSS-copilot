#!/usr/bin/env bash
# incident-timeline.sh
# Reconstruct a forensic incident timeline from multiple Kubernetes data sources.
#
# Enterprise equivalent: Sysdig Secure Activity Audit ($40-150K), Prisma Cloud
# Forensics ($100-400K), CrowdStrike Incident Workbench ($50-200K).
# These provide real-time timeline UIs with process trees and network graphs.
# This script reconstructs the same timeline from kubectl, Falco, and pod data.
#
# Usage:
#   bash incident-timeline.sh --namespace default --since 1h
#   bash incident-timeline.sh --namespace production --pod suspicious-pod-xyz --output incident.md
#   bash incident-timeline.sh --namespace default --since 30m --include-falco
#
# CKS alignment: Runtime security — incident investigation and forensics
# NIST 800-53: IR-4 (Incident Handling), IR-5 (Incident Monitoring), AU-6 (Audit Review)
#
# What it collects:
#   1. K8s events (pod lifecycle, OOMKill, evictions, restarts)
#   2. Pod status changes (container state transitions)
#   3. Falco alerts (if available via Prometheus/Loki)
#   4. RBAC events (role bindings, SA token usage)
#   5. NetworkPolicy changes
#   6. Image pull events and config changes
#
# Requires: kubectl, jq
# Optional: curl (for Falco/Prometheus queries)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

NAMESPACE=""
POD=""
SINCE="1h"
OUTPUT=""
INCLUDE_FALCO=false
FALCO_ENDPOINT=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --pod) POD="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --include-falco) INCLUDE_FALCO=true; shift ;;
    --falco-endpoint) FALCO_ENDPOINT="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    -h|--help)
      cat <<EOF
Reconstruct forensic incident timeline from Kubernetes data sources.

Usage:
  bash incident-timeline.sh --namespace <ns> [OPTIONS]

Options:
  --namespace NS         Target namespace (required)
  --pod POD              Focus on specific pod
  --since DURATION       How far back to look (default: 1h). Formats: 30m, 1h, 24h, 7d
  --output FILE          Write markdown report
  --include-falco        Include Falco alerts (requires falco-exporter or Loki)
  --falco-endpoint URL   Falco metrics endpoint (default: auto-detect)
  --verbose              Show raw data alongside timeline

Data sources:
  1. kubectl get events       → Pod lifecycle, scheduling, OOMKill
  2. kubectl get pods         → Container state transitions, restart counts
  3. kubectl logs             → Application logs from target pod
  4. Falco alerts             → Syscall-level security events (if --include-falco)
  5. kubectl get rolebindings → RBAC changes in the timeframe
  6. kubectl get netpol       → NetworkPolicy modifications

Example:
  # Investigate last hour in production
  bash incident-timeline.sh --namespace production --since 1h --output incident.md

  # Focus on a specific suspicious pod
  bash incident-timeline.sh --namespace default --pod crypto-miner-xyz --include-falco

  # Deep investigation with Falco data
  bash incident-timeline.sh --namespace production --since 4h --include-falco --verbose
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

if [[ -z "$NAMESPACE" ]]; then
  echo "Usage: bash incident-timeline.sh --namespace <ns> [--pod POD] [--since 1h]"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Ghost Protocol — Incident Timeline Reconstruction ===${NC}"
echo "  Namespace : $NAMESPACE"
echo "  Pod       : ${POD:-all}"
echo "  Window    : last $SINCE"
echo "  Falco     : $(if $INCLUDE_FALCO; then echo 'included'; else echo 'excluded (use --include-falco)'; fi)"
echo ""

TIMELINE=()

add_event() {
  local timestamp="$1" source="$2" severity="$3" message="$4"
  TIMELINE+=("${timestamp}|${source}|${severity}|${message}")
}

# ─── 1. K8s Events ──────────────────────────────────────────────────────────

echo -e "${BLUE}[1/6] Collecting K8s events...${NC}"

POD_FILTER=""
if [[ -n "$POD" ]]; then
  POD_FILTER="--field-selector involvedObject.name=$POD"
fi

EVENTS=$(kubectl get events -n "$NAMESPACE" $POD_FILTER --sort-by='.lastTimestamp' -o json 2>/dev/null || echo '{"items":[]}')

EVENT_COUNT=$(echo "$EVENTS" | jq '.items | length')
echo "  Found $EVENT_COUNT events"

echo "$EVENTS" | jq -r '.items[] | [
  (.lastTimestamp // .eventTime // "unknown"),
  .type,
  .reason,
  (.involvedObject.kind // "?") + "/" + (.involvedObject.name // "?"),
  (.message // "no message" | gsub("\n"; " ") | .[:200])
] | @tsv' 2>/dev/null | while IFS=$'\t' read -r ts type reason obj msg; do
  severity="INFO"
  [[ "$type" == "Warning" ]] && severity="WARN"
  [[ "$reason" =~ (OOMKill|BackOff|Failed|Unhealthy|Evicted) ]] && severity="HIGH"
  add_event "$ts" "k8s-event" "$severity" "[$reason] $obj: $msg"
done

# ─── 2. Pod Status ──────────────────────────────────────────────────────────

echo -e "${BLUE}[2/6] Collecting pod status...${NC}"

if [[ -n "$POD" ]]; then
  PODS_JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || echo '{}')
else
  PODS_JSON=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
fi

# Extract container status transitions
echo "$PODS_JSON" | jq -r '
  (.items // [.]) | .[] |
  .metadata.name as $pod |
  (.status.containerStatuses // [])[] |
  [$pod, .name, .restartCount, (.state | keys[0]),
   (if .lastState.terminated then
     "last terminated: " + (.lastState.terminated.reason // "unknown") +
     " at " + (.lastState.terminated.finishedAt // "unknown")
   else "" end)
  ] | @tsv
' 2>/dev/null | while IFS=$'\t' read -r pod container restarts state last_state; do
  if [[ "$restarts" -gt 0 ]]; then
    add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "pod-status" "WARN" \
      "Pod $pod/$container: $restarts restarts, state=$state $last_state"
  fi
  if [[ "$state" == "waiting" ]]; then
    add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "pod-status" "HIGH" \
      "Pod $pod/$container: stuck in waiting state"
  fi
done

POD_COUNT=$(echo "$PODS_JSON" | jq '(.items // [.]) | length')
echo "  Analyzed $POD_COUNT pod(s)"

# ─── 3. Pod Logs (if specific pod targeted) ──────────────────────────────────

echo -e "${BLUE}[3/6] Collecting pod logs...${NC}"

if [[ -n "$POD" ]]; then
  LOG_LINES=$(kubectl logs "$POD" -n "$NAMESPACE" --since="$SINCE" --tail=100 2>/dev/null | wc -l || echo "0")
  echo "  Captured $LOG_LINES log lines from $POD"

  # Look for error patterns
  ERROR_COUNT=$(kubectl logs "$POD" -n "$NAMESPACE" --since="$SINCE" --tail=500 2>/dev/null | \
    grep -ciE '(error|exception|fatal|panic|segfault|denied|unauthorized)' || echo "0")

  if [[ "$ERROR_COUNT" -gt 0 ]]; then
    add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "pod-logs" "WARN" \
      "Pod $POD: $ERROR_COUNT error/exception lines in last $SINCE"
  fi
else
  echo "  Skipped (no --pod specified, use --pod to capture logs)"
fi

# ─── 4. Falco Alerts ─────────────────────────────────────────────────────────

echo -e "${BLUE}[4/6] Collecting Falco alerts...${NC}"

if $INCLUDE_FALCO; then
  # Try to find Falco alerts via Prometheus
  if [[ -z "$FALCO_ENDPOINT" ]]; then
    FALCO_SVC=$(kubectl get svc -n falco-system -l app.kubernetes.io/name=falco-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$FALCO_SVC" ]]; then
      FALCO_ENDPOINT="http://$FALCO_SVC.falco-system:9376/metrics"
    fi
  fi

  if [[ -n "$FALCO_ENDPOINT" ]]; then
    echo "  Querying Falco exporter: $FALCO_ENDPOINT"
    FALCO_METRICS=$(curl -s "$FALCO_ENDPOINT" 2>/dev/null || true)
    if [[ -n "$FALCO_METRICS" ]]; then
      ALERT_COUNT=$(echo "$FALCO_METRICS" | grep "falco_events{" | grep -c "$NAMESPACE" || echo "0")
      echo "  Found $ALERT_COUNT Falco events for namespace $NAMESPACE"
      add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "falco" "HIGH" \
        "$ALERT_COUNT Falco alerts in namespace $NAMESPACE (see Grafana for details)"
    fi
  else
    # Fall back to Falco pod logs
    FALCO_POD=$(kubectl get pods -n falco-system -l app.kubernetes.io/name=falco -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$FALCO_POD" ]]; then
      FALCO_ALERTS=$(kubectl logs "$FALCO_POD" -n falco-system --since="$SINCE" --tail=200 2>/dev/null | \
        grep -c "$NAMESPACE" || echo "0")
      echo "  Found $FALCO_ALERTS Falco log entries mentioning $NAMESPACE"
      if [[ "$FALCO_ALERTS" -gt 0 ]]; then
        # Extract alert summaries
        kubectl logs "$FALCO_POD" -n falco-system --since="$SINCE" --tail=200 2>/dev/null | \
          grep "$NAMESPACE" | head -10 | while IFS= read -r line; do
          PRIORITY=$(echo "$line" | grep -oP 'Priority":\s*"\K[^"]+' || echo "Notice")
          RULE=$(echo "$line" | grep -oP 'Rule":\s*"\K[^"]+' || echo "unknown")
          add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "falco" "HIGH" \
            "Falco [$PRIORITY]: $RULE"
        done
      fi
    else
      echo "  Falco not found in cluster (skipping)"
    fi
  fi
else
  echo "  Skipped (use --include-falco to collect)"
fi

# ─── 5. RBAC Changes ─────────────────────────────────────────────────────────

echo -e "${BLUE}[5/6] Checking RBAC changes...${NC}"

# Check for recently created RoleBindings
RB_COUNT=$(kubectl get rolebindings -n "$NAMESPACE" -o json 2>/dev/null | \
  jq '[.items[] | select(.metadata.creationTimestamp > (now - 3600 | strftime("%Y-%m-%dT%H:%M:%SZ")))] | length' 2>/dev/null || echo "0")

if [[ "$RB_COUNT" -gt 0 ]]; then
  add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "rbac" "WARN" \
    "$RB_COUNT RoleBinding(s) created in $NAMESPACE in the last hour"
  echo "  $RB_COUNT recent RoleBinding changes"
else
  echo "  No recent RBAC changes"
fi

# ─── 6. NetworkPolicy Changes ────────────────────────────────────────────────

echo -e "${BLUE}[6/6] Checking NetworkPolicy changes...${NC}"

NP_COUNT=$(kubectl get networkpolicies -n "$NAMESPACE" -o json 2>/dev/null | \
  jq '[.items[] | select(.metadata.creationTimestamp > (now - 3600 | strftime("%Y-%m-%dT%H:%M:%SZ")))] | length' 2>/dev/null || echo "0")

if [[ "$NP_COUNT" -gt 0 ]]; then
  add_event "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "netpol" "INFO" \
    "$NP_COUNT NetworkPolicy(ies) created/modified in $NAMESPACE recently"
  echo "  $NP_COUNT recent NetworkPolicy changes"
else
  echo "  No recent NetworkPolicy changes"
fi

# ─── Generate Timeline ───────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}=== Incident Timeline ===${NC}"
echo ""

# Sort and display
printf '%s\n' "${TIMELINE[@]}" | sort | while IFS='|' read -r ts source sev msg; do
  case "$sev" in
    HIGH) COLOR="$RED" ;;
    WARN) COLOR="$YELLOW" ;;
    *) COLOR="$GREEN" ;;
  esac
  echo -e "  ${COLOR}[$sev]${NC} $ts [$source] $msg"
done

echo ""
echo -e "Total events: ${#TIMELINE[@]}"

# ─── Report Generation ───────────────────────────────────────────────────────

if [[ -n "$OUTPUT" ]]; then
  {
    echo "# Incident Timeline Report"
    echo ""
    echo "**Namespace:** $NAMESPACE"
    echo "**Pod:** ${POD:-all}"
    echo "**Window:** last $SINCE"
    echo "**Generated:** $(date +"%Y-%m-%d %H:%M:%S UTC")"
    echo "**Cluster:** $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    echo ""
    echo "## Timeline"
    echo ""
    echo "| Time | Source | Severity | Event |"
    echo "|------|--------|----------|-------|"

    printf '%s\n' "${TIMELINE[@]}" | sort | while IFS='|' read -r ts source sev msg; do
      echo "| $ts | $source | $sev | $msg |"
    done

    echo ""
    echo "## Summary"
    echo ""
    echo "- **Total events:** ${#TIMELINE[@]}"
    echo "- **K8s events:** $EVENT_COUNT"
    echo "- **Pods analyzed:** $POD_COUNT"
    if $INCLUDE_FALCO; then
      echo "- **Falco alerts:** included"
    fi

    echo ""
    echo "## Recommended Actions"
    echo ""
    echo "1. Review HIGH severity events for root cause"
    echo "2. Check if drifted resources are ArgoCD-managed (fix in git, not kubectl)"
    echo "3. If pod compromise suspected: \`bash 02-response/isolate-pod.sh --pod <name> --namespace $NAMESPACE\`"
    echo "4. Capture forensics before killing: \`bash 02-response/capture-forensics.sh --pod <name> --namespace $NAMESPACE\`"
    echo "5. Generate full weekly report: \`python3 tools/generate-report.py --format markdown\`"

    echo ""
    echo "---"
    echo "*Generated by Ghost Protocol incident-timeline.sh*"
  } > "$OUTPUT"

  echo -e "${GREEN}Report: $OUTPUT${NC}"
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review HIGH events above"
echo "  2. Isolate if compromised:  bash 02-response/isolate-pod.sh --pod <name> -n $NAMESPACE"
echo "  3. Capture forensics:       bash 02-response/capture-forensics.sh --pod <name> -n $NAMESPACE"
echo "  4. Check Falco dashboards:  kubectl port-forward svc/grafana 3000:3000 -n monitoring"
echo ""
