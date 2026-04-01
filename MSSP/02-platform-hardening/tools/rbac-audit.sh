#!/usr/bin/env bash
# rbac-audit.sh — Find dangerous RBAC configurations in a Kubernetes cluster.
# Part of GP-Copilot 02-CLUSTER-HARDEN package.
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

header() { printf "\n${CYAN}${BOLD}=== %s ===${NC}\n" "$1"; }
warn()   { printf "${YELLOW}  [!] %s${NC}\n" "$1"; }
danger() { printf "${RED}  [!!] %s${NC}\n" "$1"; }
ok()     { printf "${GREEN}  [ok] %s${NC}\n" "$1"; }

count_cluster_admin=0
count_wildcard_verbs=0
count_wildcard_resources=0
count_non_default_sa=0
count_automount=0

# --- 1. cluster-admin bindings ---
header "ClusterRoleBindings with cluster-admin"
while IFS= read -r line; do
    if [ -n "$line" ]; then
        danger "$line"
        count_cluster_admin=$((count_cluster_admin + 1))
    fi
done < <(kubectl get clusterrolebindings -o json 2>/dev/null | \
    jq -r '.items[] | select(.roleRef.name=="cluster-admin") |
        .metadata.name as $binding |
        (.subjects // [])[] |
        "\($binding) -> \(.kind)/\(.name)" + (if .namespace then " (ns: \(.namespace))" else "" end)')

if [ "$count_cluster_admin" -eq 0 ]; then
    ok "No cluster-admin bindings found"
fi

# --- 2. ClusterRoles with wildcard verbs ---
header "ClusterRoles with wildcard verbs"
while IFS= read -r line; do
    if [ -n "$line" ]; then
        warn "$line"
        count_wildcard_verbs=$((count_wildcard_verbs + 1))
    fi
done < <(kubectl get clusterroles -o json 2>/dev/null | \
    jq -r '.items[] | select(.rules != null) |
        . as $role |
        .rules[] | select(.verbs != null and (.verbs | index("*"))) |
        $role.metadata.name')

if [ "$count_wildcard_verbs" -eq 0 ]; then
    ok "No ClusterRoles with wildcard verbs"
fi

# --- 3. ClusterRoles with wildcard resources ---
header "ClusterRoles with wildcard resources"
while IFS= read -r line; do
    if [ -n "$line" ]; then
        warn "$line"
        count_wildcard_resources=$((count_wildcard_resources + 1))
    fi
done < <(kubectl get clusterroles -o json 2>/dev/null | \
    jq -r '.items[] | select(.rules != null) |
        . as $role |
        .rules[] | select(.resources != null and (.resources | index("*"))) |
        $role.metadata.name')

if [ "$count_wildcard_resources" -eq 0 ]; then
    ok "No ClusterRoles with wildcard resources"
fi

# --- 4. Pods using non-default service accounts ---
header "Pods with non-default service accounts"
while IFS= read -r line; do
    if [ -n "$line" ]; then
        printf "  %s\n" "$line"
        count_non_default_sa=$((count_non_default_sa + 1))
    fi
done < <(kubectl get pods --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] |
        select(.spec.serviceAccountName != null and .spec.serviceAccountName != "default") |
        "\(.metadata.namespace)/\(.metadata.name) -> sa:\(.spec.serviceAccountName)"')

if [ "$count_non_default_sa" -eq 0 ]; then
    ok "All pods use default service account"
fi

# --- 5. Service accounts with automountServiceAccountToken ---
header "ServiceAccounts with automountServiceAccountToken: true"
while IFS= read -r line; do
    if [ -n "$line" ]; then
        warn "$line"
        count_automount=$((count_automount + 1))
    fi
done < <(kubectl get serviceaccounts --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] |
        select(.automountServiceAccountToken == true) |
        "\(.metadata.namespace)/\(.metadata.name)"')

if [ "$count_automount" -eq 0 ]; then
    ok "No service accounts explicitly set automountServiceAccountToken: true"
fi

# --- Summary ---
header "RBAC Audit Summary"
printf "  cluster-admin bindings:     %s\n" "$count_cluster_admin"
printf "  wildcard verb roles:        %s\n" "$count_wildcard_verbs"
printf "  wildcard resource roles:    %s\n" "$count_wildcard_resources"
printf "  non-default service accts:  %s\n" "$count_non_default_sa"
printf "  automount token enabled:    %s\n" "$count_automount"

total=$((count_cluster_admin + count_wildcard_verbs + count_wildcard_resources))
if [ "$total" -gt 0 ]; then
    printf "\n${RED}${BOLD}  %d high-risk RBAC finding(s) require review.${NC}\n" "$total"
else
    printf "\n${GREEN}${BOLD}  No high-risk RBAC findings.${NC}\n"
fi
