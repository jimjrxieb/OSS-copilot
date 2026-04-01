#!/usr/bin/env bash
# benchmark-score.sh — Run CIS Kubernetes Benchmark and show pass/fail summary.
# Part of GP-Copilot 02-CLUSTER-HARDEN package.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

header() { printf "\n${CYAN}${BOLD}=== %s ===${NC}\n" "$1"; }

# Check kube-bench is installed
if ! command -v kube-bench &>/dev/null; then
    printf "${RED}kube-bench is not installed.${NC}\n\n"
    printf "Install options:\n"
    printf "  # Binary (amd64):\n"
    printf "  curl -sL https://github.com/aquasecurity/kube-bench/releases/latest/download/kube-bench_linux_amd64.tar.gz | tar xz -C /usr/local/bin\n\n"
    printf "  # Container:\n"
    printf "  kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml\n\n"
    printf "  # Homebrew:\n"
    printf "  brew install kube-bench\n"
    exit 1
fi

header "Running CIS Kubernetes Benchmark (kube-bench)"

# Run kube-bench and capture JSON output
json_output=$(kube-bench run --json 2>/dev/null) || {
    printf "${YELLOW}kube-bench requires root or must run on a cluster node.${NC}\n"
    printf "Try: sudo %s\n" "$0"
    exit 1
}

# Section name mapping
declare -A section_names=(
    ["1"]="Master Node"
    ["2"]="Etcd"
    ["3"]="Control Plane"
    ["4"]="Worker Node"
    ["5"]="Policies"
)

total_pass=0
total_fail=0
total_warn=0
total_info=0

header "Section Breakdown"
printf "  %-5s %-20s %6s %6s %6s %6s\n" "Sec" "Name" "Pass" "Fail" "Warn" "Info"
printf "  %-5s %-20s %6s %6s %6s %6s\n" "---" "----" "----" "----" "----" "----"

while IFS='|' read -r section pass fail warn info; do
    section=$(echo "$section" | xargs)
    pass=$(echo "$pass" | xargs)
    fail=$(echo "$fail" | xargs)
    warn=$(echo "$warn" | xargs)
    info=$(echo "$info" | xargs)

    name="${section_names[$section]:-Unknown}"

    color="$GREEN"
    if [ "$fail" -gt 0 ]; then
        color="$RED"
    elif [ "$warn" -gt 0 ]; then
        color="$YELLOW"
    fi

    printf "  ${color}%-5s %-20s %6d %6d %6d %6d${NC}\n" "$section" "$name" "$pass" "$fail" "$warn" "$info"

    total_pass=$((total_pass + pass))
    total_fail=$((total_fail + fail))
    total_warn=$((total_warn + warn))
    total_info=$((total_info + info))
done < <(echo "$json_output" | jq -r '.Controls[] |
    (.id | split(".")[0]) as $sec |
    [($sec),
     ([.tests[].results[] | select(.status=="PASS")] | length),
     ([.tests[].results[] | select(.status=="FAIL")] | length),
     ([.tests[].results[] | select(.status=="WARN")] | length),
     ([.tests[].results[] | select(.status=="INFO")] | length)]
    | join("|")' | sort -t'|' -k1,1 -u)

# Overall summary
header "Overall Score"
total_checks=$((total_pass + total_fail + total_warn + total_info))
if [ "$total_checks" -gt 0 ]; then
    pct=$((total_pass * 100 / total_checks))
else
    pct=0
fi

printf "  Pass: ${GREEN}%d${NC}  Fail: ${RED}%d${NC}  Warn: ${YELLOW}%d${NC}  Info: %d\n" \
    "$total_pass" "$total_fail" "$total_warn" "$total_info"

if [ "$pct" -ge 80 ]; then
    color="$GREEN"
elif [ "$pct" -ge 60 ]; then
    color="$YELLOW"
else
    color="$RED"
fi

printf "\n  ${color}${BOLD}Score: %d%% (%d/%d checks passed)${NC}\n" "$pct" "$total_pass" "$total_checks"
