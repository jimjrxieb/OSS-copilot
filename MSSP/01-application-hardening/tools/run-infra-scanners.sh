#!/usr/bin/env bash
# run-infra-scanners.sh
# Infrastructure & K8s configuration scanners — the "Cluster" C.
#
# Scanners: checkov, kubescape, polaris, conftest, kube-bench
#
# Usage:
#   bash run-infra-scanners.sh --target-dir /path/to/client-repo
#   bash run-infra-scanners.sh -t ~/GP-PROJECTS/01-instance/slot-2/Anthra-CLOUD

set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_DIR/_scanner-common.sh"

SCANNER_LIST="checkov  kubescape  polaris  conftest  kube-bench"

parse_scanner_args "run-infra-scanners.sh" "$SCANNER_LIST" "$@"
setup_target
setup_output
print_banner "Infrastructure & K8s Config Scan"

# ─── 1. Checkov — IaC (K8s, Terraform, Dockerfile) ──────────────────────────

echo -e "${YELLOW}[1/5] IaC${NC}"
run_scanner "checkov" \
    "checkov -d '$SCAN_DIR' \
        --config-file '$CONFIGS_DIR/.checkov.yaml' \
        --output json \
        --output-file-path '$OUTPUT_DIR' \
        --quiet 2>/dev/null || true" \
    "checkov"

# ─── 2. Kubescape — NSA/CISA K8s hardening ──────────────────────────────────

echo -e "${YELLOW}[2/5] K8s hardening${NC}"
run_scanner "kubescape" \
    "kubescape scan '$SCAN_DIR' \
        --format json \
        --output '$OUTPUT_DIR/kubescape.json' 2>/dev/null || true" \
    "kubescape"

# ─── 3. Polaris — K8s best practices ────────────────────────────────────────

echo -e "${YELLOW}[3/5] K8s best practices${NC}"
if ! should_skip "polaris" && command -v polaris &>/dev/null; then
    _POLARIS_PATH=""
    for _dir in k8s kubernetes infrastructure manifests deploy; do
        [[ -d "$SCAN_DIR/$_dir" ]] && _POLARIS_PATH="$SCAN_DIR/$_dir"
    done
    if [[ -n "$_POLARIS_PATH" ]]; then
        echo -e "${BLUE}  ▶  polaris...${NC}"
        if polaris audit --audit-path "$_POLARIS_PATH" --format json > "$OUTPUT_DIR/polaris.json" 2>/dev/null; then
            echo -e "${GREEN}  ✓  polaris — done${NC}"
            PASS=$((PASS + 1))
        else
            echo -e "${GREEN}  ✓  polaris — done (findings present)${NC}"
            PASS=$((PASS + 1))
        fi
    else
        echo -e "${YELLOW}  ⏭  polaris — no K8s manifest directories found${NC}"
        SKIP=$((SKIP + 1))
    fi
elif should_skip "polaris"; then
    echo -e "${YELLOW}  ⏭  polaris — skipped${NC}"
    SKIP=$((SKIP + 1))
else
    echo -e "${YELLOW}  ⚠  polaris — not installed${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── 4. Conftest — OPA policy check on K8s manifests ────────────────────────

echo -e "${YELLOW}[4/5] OPA policies${NC}"
if ! should_skip "conftest" && command -v conftest &>/dev/null; then
    _CONFTEST_TARGETS=""
    for _dir in k8s kubernetes infrastructure manifests deploy; do
        [[ -d "$SCAN_DIR/$_dir" ]] && _CONFTEST_TARGETS="$SCAN_DIR/$_dir"
    done
    if [[ -n "$_CONFTEST_TARGETS" ]]; then
        echo -e "${BLUE}  ▶  conftest...${NC}"
        if conftest test "$_CONFTEST_TARGETS" \
            --policy "$CONFIGS_DIR/conftest-policy.rego" \
            --output json > "$OUTPUT_DIR/conftest.json" 2>/dev/null; then
            echo -e "${GREEN}  ✓  conftest — done${NC}"
            PASS=$((PASS + 1))
        else
            echo -e "${GREEN}  ✓  conftest — done (findings present)${NC}"
            PASS=$((PASS + 1))
        fi
    else
        echo -e "${YELLOW}  ⏭  conftest — no K8s manifest directories found${NC}"
        SKIP=$((SKIP + 1))
    fi
elif should_skip "conftest"; then
    echo -e "${YELLOW}  ⏭  conftest — skipped${NC}"
    SKIP=$((SKIP + 1))
else
    echo -e "${YELLOW}  ⚠  conftest — not installed${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── 5. Kube-bench — CIS benchmark ──────────────────────────────────────────

echo -e "${YELLOW}[5/5] CIS benchmark${NC}"
if should_skip "kube-bench"; then
    echo -e "${YELLOW}  ⏭  kube-bench — skipped${NC}"
    SKIP=$((SKIP + 1))
elif command -v kube-bench &>/dev/null; then
    run_scanner "kube-bench" \
        "kube-bench --json > '$OUTPUT_DIR/kube-bench.json' 2>/dev/null || true" \
        "kube-bench"
else
    echo -e "${YELLOW}  ⏭  kube-bench — not installed (requires cluster access, skip for repo-only scans)${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary
