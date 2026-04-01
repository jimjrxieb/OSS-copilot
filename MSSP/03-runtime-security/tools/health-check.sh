#!/usr/bin/env bash
# health-check.sh
# Verify runtime security components are healthy.
# Checks Falco + falco-exporter by default. jsa-infrasec is checked only if deployed.
#
# Usage:
#   bash health-check.sh
#   bash health-check.sh --namespace jsa-infrasec

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

NAMESPACE_JSA="jsa-infrasec"
NAMESPACE_FALCO="falco"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)   NAMESPACE_JSA="$2"; shift 2 ;;
    *) shift ;;
  esac
done

PASS=0; WARN=0; FAIL=0

check() {
  local label="$1" result="$2" detail="${3:-}"
  case "$result" in
    PASS) echo -e "  ${GREEN}✓${NC}  $label${detail:+ — $detail}"; PASS=$((PASS+1)) ;;
    WARN) echo -e "  ${YELLOW}⚠${NC}  $label${detail:+ — $detail}"; WARN=$((WARN+1)) ;;
    FAIL) echo -e "  ${RED}✗${NC}  $label${detail:+ — $detail}"; FAIL=$((FAIL+1)) ;;
    INFO) echo -e "  ${BLUE}ℹ${NC}  $label${detail:+ — $detail}" ;;
  esac
}

echo ""
echo -e "${BLUE}=== Runtime Security Health Check ===${NC}"
echo ""

# ── Cluster connectivity ───────────────────────────────────────────────────
echo -e "${BLUE}Cluster${NC}"
if kubectl cluster-info &>/dev/null; then
  CTX=$(kubectl config current-context)
  check "kubectl" PASS "$CTX"
else
  check "kubectl" FAIL "cannot reach cluster"
fi
echo ""

# ── Falco ─────────────────────────────────────────────────────────────────
echo -e "${BLUE}Falco (ns: $NAMESPACE_FALCO)${NC}"

if kubectl get namespace "$NAMESPACE_FALCO" &>/dev/null; then
  check "namespace" PASS

  FALCO_TOTAL=$(kubectl get pods -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco --no-headers 2>/dev/null | wc -l | tr -d ' ')
  FALCO_RUNNING=$(kubectl get pods -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco --no-headers 2>/dev/null | grep -c "Running" || echo "0")

  if [[ "$FALCO_TOTAL" -eq 0 ]]; then
    check "daemonset" FAIL "no Falco pods — run: helm install falco falcosecurity/falco -n falco --create-namespace"
  elif [[ "$FALCO_RUNNING" -eq "$FALCO_TOTAL" ]]; then
    check "daemonset" PASS "$FALCO_RUNNING/$FALCO_TOTAL pods Running"
  else
    check "daemonset" WARN "$FALCO_RUNNING/$FALCO_TOTAL pods Running"
  fi

  # Check Falco rules loaded
  FALCO_RULES=$(kubectl get configmap -n "$NAMESPACE_FALCO" --no-headers 2>/dev/null | grep -c "falco" || echo "0")
  if [[ "$FALCO_RULES" -gt 0 ]]; then
    check "rules configmap" PASS "$FALCO_RULES Falco configmap(s) found"
  else
    check "rules configmap" WARN "no Falco configmaps found"
  fi
else
  check "namespace" FAIL "$NAMESPACE_FALCO not found — Falco not installed (run: bash tools/deploy.sh)"
fi
echo ""

# ── falco-exporter ────────────────────────────────────────────────────────
echo -e "${BLUE}falco-exporter (ns: $NAMESPACE_FALCO)${NC}"

if kubectl get namespace "$NAMESPACE_FALCO" &>/dev/null; then
  EXPORTER_TOTAL=$(kubectl get pods -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco-exporter --no-headers 2>/dev/null | wc -l | tr -d ' ')
  EXPORTER_RUNNING=$(kubectl get pods -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco-exporter --no-headers 2>/dev/null | grep -c "Running" || echo "0")

  if [[ "$EXPORTER_TOTAL" -eq 0 ]]; then
    check "deployment" WARN "falco-exporter not deployed — Prometheus metrics (falco_alerts_total) unavailable"
    check "deployment" INFO "Install: helm install falco-exporter falcosecurity/falco-exporter -n falco"
  elif [[ "$EXPORTER_RUNNING" -eq "$EXPORTER_TOTAL" ]]; then
    check "deployment" PASS "$EXPORTER_RUNNING/$EXPORTER_TOTAL pods Running"

    # Check if the metrics port is exposed
    EXPORTER_SVC=$(kubectl get service -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco-exporter --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$EXPORTER_SVC" -gt 0 ]]; then
      check "metrics service" PASS "service exists (exposes falco_alerts_total)"
    else
      check "metrics service" WARN "no service found — Prometheus may not be able to scrape"
    fi
  else
    check "deployment" WARN "$EXPORTER_RUNNING/$EXPORTER_TOTAL pods Running"
  fi
else
  check "falco-exporter" WARN "falco namespace not found — deploy Falco first"
fi
echo ""

# ── jsa-infrasec (auto-detected, not required) ───────────────────────────
echo -e "${BLUE}jsa-infrasec (ns: $NAMESPACE_JSA)${NC}"

if kubectl get namespace "$NAMESPACE_JSA" &>/dev/null; then
  check "namespace" PASS

  # Pod running
  JSA_STATUS=$(kubectl get pods -n "$NAMESPACE_JSA" -l app=jsa-infrasec \
    --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "")
  if [[ "$JSA_STATUS" == "Running" ]]; then
    JSA_POD=$(kubectl get pods -n "$NAMESPACE_JSA" -l app=jsa-infrasec \
      --no-headers 2>/dev/null | awk '{print $1}' | head -1)
    check "pod" PASS "$JSA_POD — $JSA_STATUS"
  elif [[ -z "$JSA_STATUS" ]]; then
    check "pod" FAIL "no pods found in $NAMESPACE_JSA"
  else
    JSA_POD=$(kubectl get pods -n "$NAMESPACE_JSA" -l app=jsa-infrasec \
      --no-headers 2>/dev/null | awk '{print $1}' | head -1)
    check "pod" WARN "$JSA_POD — $JSA_STATUS"
  fi

  # API endpoint
  if kubectl get service -n "$NAMESPACE_JSA" jsa-infrasec &>/dev/null; then
    check "service" PASS "jsa-infrasec service exists"

    # Port-forward check (quick attempt)
    if kubectl exec -n "$NAMESPACE_JSA" \
        -l app=jsa-infrasec \
        -- curl -sf http://localhost:8000/health &>/dev/null 2>&1; then
      check "health endpoint" PASS "/health → 200"
    else
      check "health endpoint" WARN "could not reach /health (may need port-forward)"
    fi
  else
    check "service" WARN "no service found"
  fi

  # Recent log lines — any errors?
  LOG_ERRORS=$(kubectl logs -n "$NAMESPACE_JSA" \
    -l app=jsa-infrasec \
    --tail=50 2>/dev/null | grep -ciE "ERROR|CRITICAL|panic|traceback" 2>/dev/null | tr -d '[:space:]' || echo "0")
  LOG_ERRORS="${LOG_ERRORS:-0}"
  if [[ "$LOG_ERRORS" -eq 0 ]]; then
    check "recent logs" PASS "no errors in last 50 lines"
  else
    check "recent logs" WARN "$LOG_ERRORS error(s) in last 50 lines — run: kubectl logs -n $NAMESPACE_JSA deploy/jsa-infrasec --tail=100"
  fi

else
  check "jsa-infrasec" INFO "not deployed — this is optional (package 05-JSA-AUTONOMOUS)"
  check "jsa-infrasec" INFO "deploy with: bash tools/deploy.sh --with-jsa"
fi
echo ""

# ── Summary ────────────────────────────────────────────────────────────────
echo "============================================================"
echo -e "  ${GREEN}PASS${NC}: $PASS   ${YELLOW}WARN${NC}: $WARN   ${RED}FAIL${NC}: $FAIL"
echo "============================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}Action required — fix FAIL items above${NC}"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "${YELLOW}Review WARN items above${NC}"
fi
echo ""
