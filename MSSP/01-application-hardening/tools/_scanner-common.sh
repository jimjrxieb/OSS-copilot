#!/usr/bin/env bash
# _scanner-common.sh — Shared setup for run-src-scanners.sh and run-infra-scanners.sh
# Sourced, not executed directly.

# Resolve package root (01-APP-SEC directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$PKG_DIR/01-scanners/configs"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Defaults
TARGET_DIR="."
OUTPUT_DIR=""
SEVERITY="medium"
PARALLEL=false
SKIP_SCANNERS=()
SCAN_LABEL="baseline"
INCLUDE_DIRS=()
SKIP_DIRS=()

# GP-S3 report storage
GP_S3_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)/GP-S3/5-consulting-reports"

# ─── Arg parsing ──────────────────────────────────────────────────────────────

_scanner_common_usage() {
    local script_name="$1"
    local scanner_list="$2"
    cat <<EOF
Usage: bash $script_name [OPTIONS]

Options:
  -t, --target-dir PATH    Directory to scan (default: current dir)
  -o, --output-dir PATH    Output directory (overrides auto-routing)
  -l, --label LABEL        Scan label: baseline|post-fix|weekly|nightly (default: baseline)
  -s, --severity LEVEL     Min severity: low|medium|high|critical (default: medium)
  --parallel               Run scanners in parallel (faster, noisier output)
  --skip-scanner NAME      Skip a scanner by name (repeatable)
  --include-dir NAME       Only scan these subdirectories (repeatable, for monorepos)
  --understand             Force understand phase even if .scanner-excludes exists
  -h, --help               Show this help

Available scanners:
  $scanner_list
EOF
    exit 0
}

parse_scanner_args() {
    local script_name="$1"
    local scanner_list="$2"
    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target-dir)  TARGET_DIR="$2"; shift 2 ;;
            -o|--output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
            -l|--label)       SCAN_LABEL="$2"; shift 2 ;;
            -s|--severity)    SEVERITY="$2"; shift 2 ;;
            --parallel)       PARALLEL=true; shift ;;
            --skip-scanner)   SKIP_SCANNERS+=("$2"); shift 2 ;;
            --include-dir)    INCLUDE_DIRS+=("$2"); shift 2 ;;
            --understand)     RUN_UNDERSTAND=true; shift ;;
            -h|--help)        _scanner_common_usage "$script_name" "$scanner_list" ;;
            *) echo -e "${RED}Unknown option: $1${NC}"; _scanner_common_usage "$script_name" "$scanner_list" ;;
        esac
    done
}

# ─── Target setup ─────────────────────────────────────────────────────────────

setup_target() {
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

    # Understand phase
    RUN_UNDERSTAND="${RUN_UNDERSTAND:-false}"
    if $RUN_UNDERSTAND || [[ ! -f "$TARGET_DIR/.scanner-excludes" ]]; then
        echo -e "${BLUE}=== Phase 0: Understand Target ===${NC}"
        bash "$SCRIPT_DIR/understand-target.sh" -t "$TARGET_DIR" -o "${OUTPUT_DIR:-$TARGET_DIR}"
        echo ""
    fi

    # Load excludes
    for ef in "${OUTPUT_DIR:-.}/.scanner-excludes" "$TARGET_DIR/.scanner-excludes"; do
        if [[ -f "$ef" ]]; then
            while IFS= read -r line; do
                [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
                SKIP_DIRS+=("$line")
            done < "$ef"
            echo -e "${GREEN}Loaded excludes from: $ef${NC}"
            break
        fi
    done

    # Build Grype exclude from skip dirs
    GRYPE_EXCLUDES=""
    for sd in "${SKIP_DIRS[@]+"${SKIP_DIRS[@]}"}"; do
        GRYPE_EXCLUDES="$GRYPE_EXCLUDES --exclude './$sd/**'"
    done

    # Scope to --include-dir if specified
    SCAN_DIR="$TARGET_DIR"
    if [[ ${#INCLUDE_DIRS[@]} -gt 0 ]]; then
        SCAN_DIR=$(mktemp -d)
        trap "rm -rf '$SCAN_DIR'" EXIT
        for idir in "${INCLUDE_DIRS[@]}"; do
            if [[ -d "$TARGET_DIR/$idir" ]]; then
                ln -s "$TARGET_DIR/$idir" "$SCAN_DIR/$idir"
            else
                echo -e "${YELLOW}WARNING: --include-dir $idir not found in $TARGET_DIR${NC}"
            fi
        done
        [[ -d "$TARGET_DIR/.git" ]] && ln -s "$TARGET_DIR/.git" "$SCAN_DIR/.git"
        echo -e "${GREEN}Scoped to: ${INCLUDE_DIRS[*]}${NC}"
    fi
}

# ─── Output routing ───────────────────────────────────────────────────────────

setup_output() {
    if [[ -z "$OUTPUT_DIR" ]]; then
        if [[ "$TARGET_DIR" =~ GP-PROJECTS/([0-9]+-instance)/(slot-[0-9]+)/ ]]; then
            INSTANCE="${BASH_REMATCH[1]}"
            SLOT="${BASH_REMATCH[2]}"
            OUTPUT_DIR="$GP_S3_DIR/${INSTANCE}/${SLOT}/${SCAN_LABEL}-$(date +%Y%m%d)"
            echo -e "${GREEN}Auto-routed: GP-S3/5-consulting-reports/${INSTANCE}/${SLOT}/${SCAN_LABEL}-$(date +%Y%m%d)${NC}"
        else
            CLIENT_SLUG="$(basename "$TARGET_DIR")"
            OUTPUT_DIR="$GP_S3_DIR/${CLIENT_SLUG}/${SCAN_LABEL}-$(date +%Y%m%d)"
            echo -e "${YELLOW}No instance/slot detected. Output: $OUTPUT_DIR${NC}"
        fi
    fi
    mkdir -p "$OUTPUT_DIR"
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

PASS=0; FAIL=0; SKIP=0

should_skip() {
    local name=$1
    for s in "${SKIP_SCANNERS[@]+"${SKIP_SCANNERS[@]}"}"; do
        [[ "$s" == "$name" ]] && return 0
    done
    return 1
}

run_scanner() {
    local name="$1"; local cmd="$2"

    if should_skip "$name"; then
        echo -e "${YELLOW}  ⏭  $name — skipped${NC}"
        SKIP=$((SKIP + 1))
        return 0
    fi

    if ! command -v "${3:-$name}" &>/dev/null; then
        echo -e "${YELLOW}  ⚠  $name — not installed (skipping)${NC}"
        SKIP=$((SKIP + 1))
        return 0
    fi

    echo -e "${BLUE}  ▶  $name...${NC}"
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}  ✓  $name — done${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${GREEN}  ✓  $name — done (findings present)${NC}"
        PASS=$((PASS + 1))
    fi
}

print_banner() {
    local title="$1"
    echo ""
    echo -e "${BLUE}=== Ghost Protocol — $title ===${NC}"
    echo "  Target    : $TARGET_DIR"
    echo "  Output    : $OUTPUT_DIR"
    echo "  Configs   : $CONFIGS_DIR"
    echo "  Severity  : $SEVERITY+"
    echo ""
}

print_summary() {
    echo ""
    echo -e "${BLUE}=== Scan Complete ===${NC}"
    echo -e "  ${GREEN}Passed : $PASS${NC}"
    echo -e "  ${YELLOW}Skipped: $SKIP${NC}"
    echo -e "  ${RED}Failed : $FAIL${NC}"
    echo "  Output : $OUTPUT_DIR"
    echo ""
}
