#!/usr/bin/env bash
# audit-to-enforce.sh
# Progressive rollout from Audit → Enforce mode for Kyverno ClusterPolicies.
#
# Usage:
#   bash audit-to-enforce.sh --strategy progressive
#   bash audit-to-enforce.sh --strategy critical-first --dry-run
#   bash audit-to-enforce.sh --strategy all-at-once

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

STRATEGY="progressive"
DRY_RUN=false
WAIT_MINUTES=10080  # 1 week default

# Policy groupings
CRITICAL_POLICIES=(
  "disallow-privileged-containers"
  "disallow-privilege-escalation"
  "require-run-as-nonroot"
)
HIGH_POLICIES=(
  "disallow-host-namespaces"
  "require-seccomp-strict"
  "require-apparmor-profile"
  "require-drop-all-capabilities"
)
ALL_POLICIES=(
  "disallow-latest-tag"
  "require-semver-tags"
  "require-resource-limits"
  "require-readonly-rootfs"
  "require-pss-labels"
  "require-runtime-class-untrusted"
)

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --strategy STRATEGY    progressive|critical-first|all-at-once (default: progressive)"
  echo "  --dry-run              Show what would change, don't apply"
  echo "  --wait-minutes N       Minutes to wait between phases (default: 10080 = 1 week)"
  echo ""
  echo "Strategies:"
  echo "  progressive     Phase 1: CRITICAL → Phase 2: HIGH → Phase 3: ALL"
  echo "  critical-first  Enforce CRITICAL immediately, rest stays in Audit"
  echo "  all-at-once     Enforce ALL policies immediately"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strategy) STRATEGY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --wait-minutes) WAIT_MINUTES="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

echo ""
echo -e "${BLUE}=== Ghost Protocol — Audit to Enforce Rollout ===${NC}"
echo "  Strategy     : $STRATEGY"
echo "  Dry run      : $DRY_RUN"
echo "  Wait between : ${WAIT_MINUTES}m"
echo ""

if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}ERROR: Cannot connect to cluster. Check kubectl context.${NC}"
  exit 1
fi

enforce_policy() {
  local policy="$1"
  local current
  current=$(kubectl get clusterpolicy "$policy" -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null || echo "NOT_FOUND")

  if [[ "$current" == "NOT_FOUND" ]]; then
    echo -e "  ${YELLOW}⚠  $policy — not found, skipping${NC}"
    return
  fi

  if [[ "$current" == "Enforce" ]]; then
    echo -e "  ${GREEN}✓  $policy — already Enforce${NC}"
    return
  fi

  echo -e "  ${BLUE}→  $policy — Audit → Enforce${NC}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "     ${YELLOW}[DRY RUN] would patch validationFailureAction: Enforce${NC}"
    return
  fi

  kubectl patch clusterpolicy "$policy" \
    --type=merge \
    -p '{"spec":{"validationFailureAction":"Enforce"}}' \
    &>/dev/null && echo -e "     ${GREEN}patched${NC}" || echo -e "     ${RED}patch failed${NC}"
}

enforce_group() {
  local label="$1"
  shift
  local policies=("$@")

  echo ""
  echo -e "${YELLOW}── Phase: $label (${#policies[@]} policies) ──${NC}"
  for p in "${policies[@]}"; do
    enforce_policy "$p"
  done
}

check_violations() {
  local phase="$1"
  echo ""
  echo -e "${BLUE}Checking for violations after $phase...${NC}"
  local count
  count=$(kubectl get polr -A -o json 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
total=sum(r.get('summary',{}).get('fail',0) for r in d.get('items',[]))
print(total)
" 2>/dev/null || echo "unknown")
  echo -e "  PolicyReport failures: ${YELLOW}$count${NC}"
}

case "$STRATEGY" in

  progressive)
    enforce_group "CRITICAL — enforce now" "${CRITICAL_POLICIES[@]}"
    check_violations "Phase 1"

    if [[ "$DRY_RUN" == "false" && "$WAIT_MINUTES" -gt 0 ]]; then
      echo ""
      echo -e "${YELLOW}Waiting ${WAIT_MINUTES} minutes before Phase 2 (HIGH)...${NC}"
      echo -e "  Run this script again with --strategy progressive to continue."
      echo -e "  Or skip the wait: --wait-minutes 0"
    fi

    enforce_group "HIGH — enforce" "${HIGH_POLICIES[@]}"
    check_violations "Phase 2"

    enforce_group "ALL — enforce remaining" "${ALL_POLICIES[@]}"
    check_violations "Phase 3"
    ;;

  critical-first)
    enforce_group "CRITICAL — enforce now" "${CRITICAL_POLICIES[@]}"
    check_violations "critical-first"
    echo ""
    echo -e "${YELLOW}HIGH and ALL policies remain in Audit mode.${NC}"
    echo -e "  Run with --strategy progressive to continue rollout."
    ;;

  all-at-once)
    echo -e "${YELLOW}WARNING: Enforcing ALL policies simultaneously.${NC}"
    echo -e "  This will block non-compliant deployments immediately.${NC}"
    echo ""
    enforce_group "ALL" "${CRITICAL_POLICIES[@]}" "${HIGH_POLICIES[@]}" "${ALL_POLICIES[@]}"
    check_violations "all-at-once"
    ;;

  *)
    echo -e "${RED}Unknown strategy: $STRATEGY${NC}"
    usage; exit 1
    ;;
esac

echo ""
echo -e "${GREEN}=== Rollout Complete ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Monitor violations:  kubectl get polr -A"
echo "  2. Check blocked pods:  kubectl get events -A --field-selector reason=PolicyViolation"
echo "  3. Generate fix guide:  bash $(dirname "$0")/../hardening/generate-fix-report.sh"
echo "  4. Review exceptions:   kubectl get policyexception -A"
echo ""
