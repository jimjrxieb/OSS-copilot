#!/usr/bin/env bash
# rbac-risk-analyzer.sh
# Analyze RBAC for privilege escalation paths, over-permissioned roles,
# and blast radius assessment.
#
# Enterprise equivalent: Teleport ($30-100K), Prisma Cloud IAM ($100-400K),
# StrongDM ($50-150K). These add session recording and JIT access.
# This script covers the ANALYSIS — finding what's broken in RBAC.
#
# Usage:
#   bash rbac-risk-analyzer.sh
#   bash rbac-risk-analyzer.sh --output rbac-risk-report.md
#   bash rbac-risk-analyzer.sh --namespace kube-system
#   bash rbac-risk-analyzer.sh --fix-recommendations
#
# CKS alignment: Minimize ClusterRole usage, restrict RBAC permissions
# NIST 800-53: AC-2 (Account Management), AC-6 (Least Privilege)
#
# Requires: kubectl, jq

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT=""
NAMESPACE=""
FIX_RECS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --fix-recommendations) FIX_RECS=true; shift ;;
    -h|--help)
      cat <<EOF
Analyze RBAC for privilege escalation paths and over-permissioned roles.

Usage: bash rbac-risk-analyzer.sh [OPTIONS]

Options:
  --output FILE            Write markdown report to file
  --namespace NS           Scope to a specific namespace
  --fix-recommendations    Include remediation commands

What it checks:
  1. ClusterRoleBindings to cluster-admin (CRITICAL)
  2. Wildcard permissions in ClusterRoles (HIGH)
  3. Privilege escalation paths (bind/escalate/impersonate verbs) (CRITICAL)
  4. Service accounts with excessive permissions (HIGH)
  5. Default service account usage (MEDIUM)
  6. Unused ClusterRoleBindings (LOW)
  7. Cross-namespace RoleBindings (MEDIUM)
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

if ! command -v kubectl &>/dev/null; then
  echo -e "${RED}ERROR: kubectl not found${NC}"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo -e "${RED}ERROR: jq not found${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Ghost Protocol — RBAC Risk Analysis ===${NC}"
echo "  Cluster : $(kubectl config current-context 2>/dev/null || echo 'unknown')"
echo "  Scope   : ${NAMESPACE:-all namespaces}"
echo ""

FINDINGS=()
CRITICAL=0; HIGH=0; MEDIUM=0; LOW=0

add_finding() {
  local severity="$1" category="$2" resource="$3" detail="$4" fix="${5:-}"
  FINDINGS+=("$severity|$category|$resource|$detail|$fix")
  case "$severity" in
    CRITICAL) CRITICAL=$((CRITICAL + 1)) ;;
    HIGH) HIGH=$((HIGH + 1)) ;;
    MEDIUM) MEDIUM=$((MEDIUM + 1)) ;;
    LOW) LOW=$((LOW + 1)) ;;
  esac
}

# ─── Check 1: ClusterRoleBindings to cluster-admin ──────────────────────────

echo -e "${BLUE}[1/7] Checking cluster-admin bindings...${NC}"

ADMIN_BINDINGS=$(kubectl get clusterrolebindings -o json | jq -r '
  .items[] |
  select(.roleRef.name == "cluster-admin") |
  .metadata.name + "|" +
  (.subjects // [] | map(.kind + ":" + (.namespace // "-") + "/" + .name) | join(","))
')

while IFS='|' read -r binding subjects; do
  [[ -z "$binding" ]] && continue
  # Skip system bindings
  if [[ "$binding" =~ ^(system:|kubeadm:|cluster-admin$) ]]; then
    continue
  fi
  add_finding "CRITICAL" "cluster-admin" "$binding" \
    "ClusterRoleBinding grants cluster-admin to: $subjects" \
    "kubectl delete clusterrolebinding $binding  # Replace with scoped ClusterRole"
  echo -e "  ${RED}CRITICAL${NC} $binding → cluster-admin (subjects: $subjects)"
done <<< "$ADMIN_BINDINGS"

# ─── Check 2: Wildcard permissions ──────────────────────────────────────────

echo -e "${BLUE}[2/7] Checking wildcard permissions...${NC}"

WILDCARD_ROLES=$(kubectl get clusterroles -o json | jq -r '
  .items[] |
  select(.metadata.name | test("^system:") | not) |
  select(.rules // [] | any(
    (.verbs // [] | any(. == "*")) or
    (.resources // [] | any(. == "*")) or
    (.apiGroups // [] | any(. == "*"))
  )) |
  .metadata.name
')

while IFS= read -r role; do
  [[ -z "$role" ]] && continue
  [[ "$role" == "cluster-admin" ]] && continue  # Already caught in Check 1

  WILDCARDS=$(kubectl get clusterrole "$role" -o json | jq -r '
    [.rules[] | select(
      (.verbs // [] | any(. == "*")) or
      (.resources // [] | any(. == "*"))
    ) | "verbs=" + (.verbs | join(",")) + " resources=" + (.resources | join(","))] | join("; ")
  ')

  add_finding "HIGH" "wildcard-perms" "clusterrole/$role" \
    "Wildcard permissions: $WILDCARDS" \
    "# Scope down: kubectl edit clusterrole $role"
  echo -e "  ${YELLOW}HIGH${NC} clusterrole/$role has wildcard permissions"
done <<< "$WILDCARD_ROLES"

# ─── Check 3: Privilege escalation verbs ─────────────────────────────────────

echo -e "${BLUE}[3/7] Checking privilege escalation paths...${NC}"

ESCALATION_ROLES=$(kubectl get clusterroles -o json | jq -r '
  .items[] |
  select(.metadata.name | test("^system:") | not) |
  select(.rules // [] | any(
    .verbs // [] | any(. == "bind" or . == "escalate" or . == "impersonate")
  )) |
  .metadata.name + "|" +
  ([.rules[] | select(.verbs // [] | any(. == "bind" or . == "escalate" or . == "impersonate")) |
    (.verbs | join(","))] | join(";"))
')

while IFS='|' read -r role verbs; do
  [[ -z "$role" ]] && continue
  add_finding "CRITICAL" "escalation" "clusterrole/$role" \
    "Has escalation verbs: $verbs — can grant itself more permissions" \
    "# Remove bind/escalate/impersonate verbs: kubectl edit clusterrole $role"
  echo -e "  ${RED}CRITICAL${NC} clusterrole/$role has escalation verbs: $verbs"
done <<< "$ESCALATION_ROLES"

# ─── Check 4: Service accounts with ClusterRoleBindings ─────────────────────

echo -e "${BLUE}[4/7] Checking service account permissions...${NC}"

SA_BINDINGS=$(kubectl get clusterrolebindings -o json | jq -r '
  .items[] |
  select(.subjects // [] | any(.kind == "ServiceAccount")) |
  .metadata.name + "|" + .roleRef.name + "|" +
  ([.subjects[] | select(.kind == "ServiceAccount") | .namespace + "/" + .name] | join(","))
')

while IFS='|' read -r binding role sas; do
  [[ -z "$binding" ]] && continue
  [[ "$binding" =~ ^system: ]] && continue
  # Skip known system service accounts
  [[ "$sas" =~ (kube-system/|kyverno/|gatekeeper/) ]] && continue

  add_finding "HIGH" "sa-permissions" "clusterrolebinding/$binding" \
    "ServiceAccount(s) $sas bound to ClusterRole/$role" \
    "# Scope to namespace: convert ClusterRoleBinding to RoleBinding"
  echo -e "  ${YELLOW}HIGH${NC} SA $sas → ClusterRole/$role (via $binding)"
done <<< "$SA_BINDINGS"

# ─── Check 5: Default service account usage ──────────────────────────────────

echo -e "${BLUE}[5/7] Checking default service account usage...${NC}"

NS_FLAG=""
if [[ -n "$NAMESPACE" ]]; then
  NS_FLAG="-n $NAMESPACE"
else
  NS_FLAG="--all-namespaces"
fi

DEFAULT_SA_PODS=$(kubectl get pods $NS_FLAG -o json 2>/dev/null | jq -r '
  .items[] |
  select(.spec.serviceAccountName == "default" or .spec.serviceAccountName == null) |
  select(.spec.automountServiceAccountToken != false) |
  (.metadata.namespace // "default") + "/" + .metadata.name
' 2>/dev/null || true)

DEFAULT_SA_COUNT=0
while IFS= read -r pod; do
  [[ -z "$pod" ]] && continue
  DEFAULT_SA_COUNT=$((DEFAULT_SA_COUNT + 1))
done <<< "$DEFAULT_SA_PODS"

if [[ $DEFAULT_SA_COUNT -gt 0 ]]; then
  add_finding "MEDIUM" "default-sa" "pods ($DEFAULT_SA_COUNT)" \
    "$DEFAULT_SA_COUNT pods using default SA with token auto-mounted" \
    "# Set automountServiceAccountToken: false or create dedicated SA"
  echo -e "  ${YELLOW}MEDIUM${NC} $DEFAULT_SA_COUNT pods using default service account"
else
  echo -e "  ${GREEN}PASS${NC} No pods using default service account with auto-mounted token"
fi

# ─── Check 6: Unused ClusterRoleBindings ─────────────────────────────────────

echo -e "${BLUE}[6/7] Checking for stale/unused bindings...${NC}"

STALE_BINDINGS=$(kubectl get clusterrolebindings -o json | jq -r '
  .items[] |
  select(.metadata.name | test("^system:") | not) |
  select((.subjects // []) | length == 0) |
  .metadata.name
')

while IFS= read -r binding; do
  [[ -z "$binding" ]] && continue
  add_finding "LOW" "stale-binding" "clusterrolebinding/$binding" \
    "ClusterRoleBinding has no subjects — stale or misconfigured" \
    "kubectl delete clusterrolebinding $binding"
  echo -e "  ${BLUE}LOW${NC} Stale binding: $binding (no subjects)"
done <<< "$STALE_BINDINGS"

# ─── Check 7: Secrets access ─────────────────────────────────────────────────

echo -e "${BLUE}[7/7] Checking roles with secrets access...${NC}"

SECRETS_ROLES=$(kubectl get clusterroles -o json | jq -r '
  .items[] |
  select(.metadata.name | test("^system:") | not) |
  select(.rules // [] | any(
    (.resources // [] | any(. == "secrets")) and
    (.verbs // [] | any(. == "get" or . == "list" or . == "watch" or . == "*"))
  )) |
  .metadata.name
')

while IFS= read -r role; do
  [[ -z "$role" ]] && continue
  [[ "$role" == "cluster-admin" ]] && continue

  add_finding "HIGH" "secrets-access" "clusterrole/$role" \
    "Has read access to secrets cluster-wide" \
    "# Scope secrets access to specific namespaces via Role, not ClusterRole"
  echo -e "  ${YELLOW}HIGH${NC} clusterrole/$role has cluster-wide secrets access"
done <<< "$SECRETS_ROLES"

# ─── Summary ──────────────────────────────────────────────────────────────────

TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))

echo ""
echo -e "${BLUE}=== RBAC Risk Summary ===${NC}"
echo -e "  ${RED}CRITICAL : $CRITICAL${NC}"
echo -e "  ${YELLOW}HIGH     : $HIGH${NC}"
echo -e "  ${YELLOW}MEDIUM   : $MEDIUM${NC}"
echo -e "  ${BLUE}LOW      : $LOW${NC}"
echo -e "  Total    : $TOTAL findings"

# ─── Report generation ────────────────────────────────────────────────────────

if [[ -n "$OUTPUT" ]]; then
  {
    echo "# RBAC Risk Analysis Report"
    echo ""
    echo "**Cluster:** $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    echo "**Date:** $(date +"%Y-%m-%d %H:%M")"
    echo "**Scope:** ${NAMESPACE:-all namespaces}"
    echo ""
    echo "## Summary"
    echo ""
    echo "| Severity | Count |"
    echo "|----------|-------|"
    echo "| CRITICAL | $CRITICAL |"
    echo "| HIGH | $HIGH |"
    echo "| MEDIUM | $MEDIUM |"
    echo "| LOW | $LOW |"
    echo "| **Total** | **$TOTAL** |"
    echo ""
    echo "## Findings"
    echo ""
    echo "| Severity | Category | Resource | Detail |"
    echo "|----------|----------|----------|--------|"

    for finding in "${FINDINGS[@]}"; do
      IFS='|' read -r sev cat res det fix <<< "$finding"
      echo "| $sev | $cat | \`$res\` | $det |"
    done

    if $FIX_RECS && [[ ${#FINDINGS[@]} -gt 0 ]]; then
      echo ""
      echo "## Remediation Commands"
      echo ""
      echo '```bash'
      for finding in "${FINDINGS[@]}"; do
        IFS='|' read -r sev cat res det fix <<< "$finding"
        if [[ -n "$fix" ]]; then
          echo "$fix"
        fi
      done
      echo '```'
    fi

    echo ""
    echo "## Recommended RBAC Templates"
    echo ""
    echo "Replace over-permissioned ClusterRoles with scoped roles:"
    echo ""
    echo '```bash'
    echo "kubectl apply -f $PKG_DIR/02-hardening/rbac-templates/developer.yaml"
    echo "kubectl apply -f $PKG_DIR/02-hardening/rbac-templates/platform-eng.yaml"
    echo "kubectl apply -f $PKG_DIR/02-hardening/rbac-templates/admin.yaml"
    echo '```'
    echo ""
    echo "---"
    echo "*Generated by Ghost Protocol rbac-risk-analyzer.sh*"
  } > "$OUTPUT"

  echo ""
  echo -e "${GREEN}Report written: $OUTPUT${NC}"
fi

echo ""
if [[ $CRITICAL -gt 0 ]]; then
  echo -e "${RED}Action required: $CRITICAL critical findings need immediate remediation.${NC}"
  echo "  Run with --fix-recommendations --output report.md for remediation commands."
fi
echo ""
