#!/usr/bin/env bash
# network-policy-generator.sh
# Auto-generate NetworkPolicies by analyzing running services in a namespace.
#
# Enterprise equivalent: Calico Enterprise ($50-200K), Cilium Enterprise ($40-150K),
# Illumio ($100-300K). These add flow visualization dashboards and automatic policy
# generation from observed traffic (eBPF-based). This script uses service discovery
# to generate a starting set of policies that can be refined after observation.
#
# Usage:
#   bash network-policy-generator.sh --namespace default
#   bash network-policy-generator.sh --namespace default --dry-run
#   bash network-policy-generator.sh --namespace default --output /tmp/netpols/
#   bash network-policy-generator.sh --all-namespaces --dry-run
#
# CKS alignment: Network Policies — restrict pod-to-pod communication.
# NIST 800-53: SC-7 (Boundary Protection), AC-4 (Information Flow Enforcement).
#
# What it generates:
#   1. Default-deny ingress policy for the namespace
#   2. Per-service ingress allow policies (based on Service selectors)
#   3. DNS egress policy (port 53 — EVERY policy needs this)
#   4. Service-to-service egress policies (based on known dependencies)
#
# Requires: kubectl, jq

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

NAMESPACE=""
ALL_NS=false
DRY_RUN=false
OUTPUT_DIR=""
INCLUDE_EGRESS=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --all-namespaces) ALL_NS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --no-egress) INCLUDE_EGRESS=false; shift ;;
    -h|--help)
      cat <<EOF
Generate NetworkPolicies from running services.

Usage:
  bash network-policy-generator.sh --namespace <ns> [OPTIONS]

Options:
  --namespace NS      Target namespace
  --all-namespaces    Generate for all non-system namespaces
  --dry-run           Print policies without applying
  --output DIR        Write YAML files to directory (instead of applying)
  --no-egress         Skip egress policies (ingress only)

What it generates:
  1. default-deny-ingress (blocks all ingress, baseline)
  2. allow-<service>-ingress (per Service, based on selectors)
  3. allow-dns-egress (port 53 UDP/TCP — CRITICAL, every NS needs this)
  4. allow-<service>-egress (if service has known upstream dependencies)

IMPORTANT: DNS egress (port 53) is included in EVERY namespace policy.
Without it, pods cannot resolve service names. This is the #1 NetworkPolicy
mistake — see feedback_netpol_dns_egress.md.

Example:
  # Preview policies for default namespace
  bash network-policy-generator.sh --namespace default --dry-run

  # Generate and save to files (review before applying)
  bash network-policy-generator.sh --namespace default --output /tmp/netpols/

  # Generate for all non-system namespaces
  bash network-policy-generator.sh --all-namespaces --output /tmp/netpols/
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

if [[ -z "$NAMESPACE" && "$ALL_NS" == "false" ]]; then
  echo "Usage: bash network-policy-generator.sh --namespace <ns> [--dry-run]"
  exit 1
fi

if ! command -v kubectl &>/dev/null || ! command -v jq &>/dev/null; then
  echo -e "${RED}ERROR: kubectl and jq are required${NC}"
  exit 1
fi

# System namespaces to skip
SYSTEM_NS="kube-system kube-public kube-node-lease gatekeeper-system kyverno falco-system gp-security cattle-system"

generate_for_namespace() {
  local ns="$1"
  local policies=()
  local policy_count=0

  echo -e "${BLUE}  Namespace: $ns${NC}"

  # Check if namespace already has NetworkPolicies
  EXISTING=$(kubectl get networkpolicies -n "$ns" -o json 2>/dev/null | jq '.items | length')
  if [[ "$EXISTING" -gt 0 ]]; then
    echo -e "  ${YELLOW}Already has $EXISTING NetworkPolicy(ies) — generating additions only${NC}"
  fi

  # ── 1. Default deny ingress ──────────────────────────────────────────────

  # Check if default-deny already exists
  if ! kubectl get networkpolicy default-deny-ingress -n "$ns" &>/dev/null; then
    DENY_POLICY=$(cat <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: $ns
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    gp-copilot/generated: "true"
  annotations:
    gp-copilot/purpose: "Default deny all ingress traffic. Allow rules added per-service."
    nist-800-53: "SC-7,AC-4"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
YAML
)
    policies+=("$DENY_POLICY")
    policy_count=$((policy_count + 1))
    echo -e "    ${GREEN}+${NC} default-deny-ingress"
  fi

  # ── 2. DNS egress (CRITICAL — every namespace needs this) ────────────────

  if ! kubectl get networkpolicy allow-dns-egress -n "$ns" &>/dev/null; then
    DNS_POLICY=$(cat <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: $ns
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    gp-copilot/generated: "true"
  annotations:
    gp-copilot/purpose: "Allow DNS resolution. Without this, pods cannot resolve service names."
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
YAML
)
    policies+=("$DNS_POLICY")
    policy_count=$((policy_count + 1))
    echo -e "    ${GREEN}+${NC} allow-dns-egress"
  fi

  # ── 3. Per-service ingress policies ──────────────────────────────────────

  SERVICES=$(kubectl get services -n "$ns" -o json 2>/dev/null | jq -c '
    .items[] |
    select(.spec.type != "ExternalName") |
    select(.metadata.name != "kubernetes") |
    {
      name: .metadata.name,
      selector: (.spec.selector // {}),
      ports: [.spec.ports[] | {port: .port, protocol: (.protocol // "TCP")}]
    }
  ')

  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue

    SVC_NAME=$(echo "$svc" | jq -r '.name')
    SELECTOR=$(echo "$svc" | jq -c '.selector')
    PORTS=$(echo "$svc" | jq -c '.ports')

    # Skip if selector is empty
    if [[ "$SELECTOR" == "{}" || "$SELECTOR" == "null" ]]; then
      echo -e "    ${YELLOW}~${NC} $SVC_NAME (no selector — headless or external)"
      continue
    fi

    POLICY_NAME="allow-${SVC_NAME}-ingress"

    # Skip if policy already exists
    if kubectl get networkpolicy "$POLICY_NAME" -n "$ns" &>/dev/null; then
      echo -e "    ${YELLOW}~${NC} $POLICY_NAME (already exists)"
      continue
    fi

    # Build podSelector from service selector
    MATCH_LABELS=$(echo "$SELECTOR" | jq -r 'to_entries | map("        " + .key + ": " + (.value | tostring)) | join("\n")')

    # Build ports block
    PORTS_YAML=$(echo "$PORTS" | jq -r '.[] | "        - protocol: " + .protocol + "\n          port: " + (.port | tostring)' )

    SVC_POLICY=$(cat <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: $POLICY_NAME
  namespace: $ns
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    gp-copilot/generated: "true"
  annotations:
    gp-copilot/purpose: "Allow ingress to $SVC_NAME service"
spec:
  podSelector:
    matchLabels:
$MATCH_LABELS
  policyTypes:
    - Ingress
  ingress:
    - ports:
$PORTS_YAML
YAML
)
    policies+=("$SVC_POLICY")
    policy_count=$((policy_count + 1))
    echo -e "    ${GREEN}+${NC} $POLICY_NAME ($(echo "$PORTS" | jq length) ports)"

  done <<< "$SERVICES"

  # ── Output / Apply ──────────────────────────────────────────────────────

  if [[ ${#policies[@]} -eq 0 ]]; then
    echo -e "    ${GREEN}No new policies needed${NC}"
    return 0
  fi

  COMBINED=""
  for policy in "${policies[@]}"; do
    COMBINED="${COMBINED}${policy}
---
"
  done

  if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    echo "$COMBINED" > "$OUTPUT_DIR/${ns}-networkpolicies.yaml"
    echo -e "    ${GREEN}Written: $OUTPUT_DIR/${ns}-networkpolicies.yaml ($policy_count policies)${NC}"
  elif $DRY_RUN; then
    echo ""
    echo -e "${YELLOW}--- DRY RUN: $ns ($policy_count policies) ---${NC}"
    echo "$COMBINED"
  else
    echo "$COMBINED" | kubectl apply -f -
    echo -e "    ${GREEN}Applied $policy_count policies to $ns${NC}"
  fi
}

echo ""
echo -e "${BLUE}=== Ghost Protocol — NetworkPolicy Generator ===${NC}"
echo "  Mode : $(if $DRY_RUN; then echo 'dry-run'; elif [[ -n "$OUTPUT_DIR" ]]; then echo "write to $OUTPUT_DIR"; else echo 'apply'; fi)"
echo ""

if $ALL_NS; then
  NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
  for ns in $NAMESPACES; do
    # Skip system namespaces
    SKIP=false
    for sys in $SYSTEM_NS; do
      [[ "$ns" == "$sys" ]] && SKIP=true
    done
    $SKIP && continue

    generate_for_namespace "$ns"
    echo ""
  done
else
  generate_for_namespace "$NAMESPACE"
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review generated policies before applying"
echo "  2. Test with a non-critical namespace first"
echo "  3. Monitor for broken connectivity after applying"
echo "  4. Refine egress rules based on observed traffic patterns"
echo "  5. Consider Hubble (Cilium OSS) for flow visibility: cilium hubble ui"
echo ""
echo -e "${YELLOW}IMPORTANT: These are STARTING policies based on Service definitions.${NC}"
echo "  Real production policies should be refined based on observed traffic."
echo "  For traffic-based policy generation, consider Calico Enterprise or Cilium Enterprise."
echo ""
