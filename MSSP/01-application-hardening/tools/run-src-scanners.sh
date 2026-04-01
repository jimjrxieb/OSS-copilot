#!/usr/bin/env bash
# run-src-scanners.sh
# Source code & dependency scanners — the "Code" C.
#
# Scanners: gitleaks, bandit, semgrep, trivy-fs, grype, hadolint
#
# Usage:
#   bash run-src-scanners.sh --target-dir /path/to/client-repo
#   bash run-src-scanners.sh -t ~/GP-PROJECTS/01-instance/slot-2/Anthra-CLOUD

set -euo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_DIR/_scanner-common.sh"

SCANNER_LIST="gitleaks  bandit  semgrep  trivy-fs  grype  hadolint"

parse_scanner_args "run-src-scanners.sh" "$SCANNER_LIST" "$@"
setup_target
setup_output
print_banner "Source Code & Dependency Scan"

# ─── 1. Gitleaks — secrets detection ──────────────────────────────────────────

echo -e "${YELLOW}[1/6] Secrets${NC}"
if ! should_skip "gitleaks" && command -v gitleaks &>/dev/null; then
    _GITLEAKS_FLAGS=""
    if [[ ! -d "$TARGET_DIR/.git" ]]; then
        _GITLEAKS_FLAGS="--no-git"
        echo -e "${YELLOW}  ℹ  No .git found — scanning all files (no .gitignore filtering)${NC}"
    fi
    echo -e "${BLUE}  ▶  gitleaks...${NC}"
    gitleaks detect \
        --source "$SCAN_DIR" \
        --config "$CONFIGS_DIR/.gitleaks.toml" \
        --report-path "$OUTPUT_DIR/gitleaks.json" \
        --report-format json \
        $_GITLEAKS_FLAGS 2>/dev/null || true
    [[ ! -f "$OUTPUT_DIR/gitleaks.json" ]] && echo '[]' > "$OUTPUT_DIR/gitleaks.json"
    echo -e "${GREEN}  ✓  gitleaks — done${NC}"
    PASS=$((PASS + 1))
elif should_skip "gitleaks"; then
    echo -e "${YELLOW}  ⏭  gitleaks — skipped${NC}"
    SKIP=$((SKIP + 1))
else
    echo -e "${YELLOW}  ⚠  gitleaks — not installed${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── 2. Bandit — Python SAST ─────────────────────────────────────────────────

echo -e "${YELLOW}[2/6] Python SAST${NC}"
if ! should_skip "bandit" && command -v bandit &>/dev/null; then
    echo -e "${BLUE}  ▶  bandit...${NC}"
    _BANDIT_TARGETS=""
    for _pydir in GP-INFRA GP-BEDROCK-AGENTS GP-GUI GP-MODEL-OPS GP-CONSULTING; do
        [[ -d "$TARGET_DIR/$_pydir" ]] && _BANDIT_TARGETS="$_BANDIT_TARGETS $TARGET_DIR/$_pydir"
    done
    [[ -z "$_BANDIT_TARGETS" ]] && _BANDIT_TARGETS="$SCAN_DIR"
    bandit -r $_BANDIT_TARGETS \
        -f json \
        -o "$OUTPUT_DIR/bandit.json" \
        --skip B101 \
        -ll 2>/dev/null || true
    [[ ! -s "$OUTPUT_DIR/bandit.json" ]] && echo '{"results":[],"errors":[],"metrics":{}}' > "$OUTPUT_DIR/bandit.json"
    echo -e "${GREEN}  ✓  bandit — done${NC}"
    PASS=$((PASS + 1))
elif should_skip "bandit"; then
    echo -e "${YELLOW}  ⏭  bandit — skipped${NC}"
    SKIP=$((SKIP + 1))
else
    echo -e "${YELLOW}  ⚠  bandit — not installed${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── 3. Semgrep — multi-language SAST ────────────────────────────────────────

echo -e "${YELLOW}[3/6] Multi-language SAST${NC}"
run_scanner "semgrep" \
    "semgrep \
        --config 'p/security-audit' \
        --config 'p/owasp-top-ten' \
        --config 'p/secrets' \
        --config 'p/python' \
        --config 'p/javascript' \
        --config 'p/golang' \
        --config 'p/kubernetes' \
        --config 'p/dockerfile' \
        --config 'p/terraform' \
        --config 'p/github-actions' \
        --exclude 'tests' --exclude 'test' --exclude 'node_modules' \
        --exclude 'vendor' --exclude 'venv' --exclude '.git' \
        --exclude '*.min.js' --exclude '*.bundle.js' \
        --json \
        --output '$OUTPUT_DIR/semgrep.json' \
        --metrics off \
        --timeout 30 \
        '$SCAN_DIR' 2>/dev/null || true" \
    "semgrep"

# ─── 4. Trivy filesystem — CVEs in dependencies ─────────────────────────────

echo -e "${YELLOW}[4/6] Dependency CVEs${NC}"
if ! should_skip "trivy-fs" && command -v trivy &>/dev/null; then
    echo -e "${BLUE}  ▶  trivy-fs...${NC}"
    trivy fs "$SCAN_DIR" \
        --format json \
        --output "$OUTPUT_DIR/trivy-fs.json" \
        --severity HIGH,CRITICAL \
        --scanners vuln,secret \
        --skip-dirs node_modules,vendor,venv,.venv,.git,__pycache__,scanner_outputs,_archive,.terraform,GP-Copilot \
        --timeout 10m0s 2>/dev/null || true
    [[ ! -s "$OUTPUT_DIR/trivy-fs.json" ]] && echo '{"Results":[]}' > "$OUTPUT_DIR/trivy-fs.json"
    echo -e "${GREEN}  ✓  trivy-fs — done${NC}"
    PASS=$((PASS + 1))
elif should_skip "trivy-fs"; then
    echo -e "${YELLOW}  ⏭  trivy-fs — skipped${NC}"
    SKIP=$((SKIP + 1))
else
    echo -e "${YELLOW}  ⚠  trivy — not installed${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── 5. Grype — CVE cross-check ─────────────────────────────────────────────

echo -e "${YELLOW}[5/6] CVE cross-check${NC}"
run_scanner "grype" \
    "grype dir:'$SCAN_DIR' --exclude './.terraform/**' --exclude './GP-Copilot/**' --exclude './node_modules/**' --exclude './vendor/**' -o json > '$OUTPUT_DIR/grype.json' 2>/dev/null || true" \
    "grype"

# ─── 6. Hadolint — Dockerfile lint ──────────────────────────────────────────

echo -e "${YELLOW}[6/6] Dockerfile lint${NC}"
if ! should_skip "hadolint" && command -v hadolint &>/dev/null; then
    DOCKERFILES=$(find -L "$SCAN_DIR" -name "Dockerfile" -o -name "Dockerfile.*" 2>/dev/null | grep -v ".git" | sort)
    if [[ -n "$DOCKERFILES" ]]; then
        echo "$DOCKERFILES" | while read -r df; do
            out_name="hadolint-$(basename "$(dirname "$df")").json"
            hadolint "$df" \
                --config "$CONFIGS_DIR/.hadolint.yaml" \
                -f json > "$OUTPUT_DIR/$out_name" 2>/dev/null || true
        done
        echo -e "${GREEN}  ✓  hadolint — done ($(echo "$DOCKERFILES" | wc -l | tr -d ' ') Dockerfiles)${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${YELLOW}  ⏭  hadolint — no Dockerfiles found${NC}"
        SKIP=$((SKIP + 1))
    fi
elif should_skip "hadolint"; then
    echo -e "${YELLOW}  ⏭  hadolint — skipped${NC}"
    SKIP=$((SKIP + 1))
else
    echo -e "${YELLOW}  ⚠  hadolint — not installed${NC}"
    SKIP=$((SKIP + 1))
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary
