#!/usr/bin/env bash
# run-all-scanners.sh
# Run all pre-deployment security scanners against a target directory.
# Wrapper that calls run-src-scanners.sh (Code C) + run-infra-scanners.sh (Cluster C).
#
# Usage:
#   bash run-all-scanners.sh --target-dir /path/to/client-repo --output-dir ./outputs/baseline-$(date +%Y%m%d)
#
# All scanner configs are read from GP-CONSULTING/01-APP-SEC/01-scanners/configs/
# You do NOT need to copy configs into the client repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

usage() {
    cat <<EOF
Run all pre-deployment security scanners.

Usage: bash run-all-scanners.sh [OPTIONS]

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

Output routing (automatic):
  If target is under GP-PROJECTS/<instance>/<slot>/<project>/
  output auto-routes to GP-S3/5-consulting-reports/<instance>/<slot>/<label>-YYYYMMDD/

Source scanners (run-src-scanners.sh):
  gitleaks  bandit  semgrep  trivy-fs  grype  hadolint

Infrastructure scanners (run-infra-scanners.sh):
  checkov  kubescape  polaris  conftest  kube-bench

DAST scanners (nuclei, zap) are in 03-RUNTIME-SECURITY.

Examples:
  bash run-all-scanners.sh -t ~/GP-PROJECTS/01-instance/slot-2/Anthra-CLOUD
  bash run-all-scanners.sh -t ~/client-repo --skip-scanner kube-bench
  bash run-all-scanners.sh -t ~/client-repo -l post-fix
EOF
    exit 0
}

# Pass --help through
for arg in "$@"; do
    [[ "$arg" == "-h" || "$arg" == "--help" ]] && usage
done

# ─── Run both scanner groups ─────────────────────────────────────────────────

echo -e "${BLUE}=== Ghost Protocol — Full Pre-Deployment Scan ===${NC}"
echo ""

echo -e "${BLUE}── Source Code & Dependencies ──${NC}"
bash "$SCRIPT_DIR/run-src-scanners.sh" "$@"

echo -e "${BLUE}── Infrastructure & K8s Config ──${NC}"
bash "$SCRIPT_DIR/run-infra-scanners.sh" "$@"

# ─── Resolve output dir for summary/triage (same logic as _scanner-common.sh) ─

TARGET_DIR="."
OUTPUT_DIR=""
SCAN_LABEL="baseline"
GP_S3_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)/GP-S3/5-consulting-reports"

# Re-parse just the args we need for output path
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target-dir)  TARGET_DIR="$2"; shift 2 ;;
        -o|--output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
        -l|--label)       SCAN_LABEL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
if [[ -z "$OUTPUT_DIR" ]]; then
    if [[ "$TARGET_DIR" =~ GP-PROJECTS/([0-9]+-instance)/(slot-[0-9]+)/ ]]; then
        INSTANCE="${BASH_REMATCH[1]}"
        SLOT="${BASH_REMATCH[2]}"
        OUTPUT_DIR="$GP_S3_DIR/${INSTANCE}/${SLOT}/${SCAN_LABEL}-$(date +%Y%m%d)"
    else
        CLIENT_SLUG="$(basename "$TARGET_DIR")"
        OUTPUT_DIR="$GP_S3_DIR/${CLIENT_SLUG}/${SCAN_LABEL}-$(date +%Y%m%d)"
    fi
fi

# ─── SUMMARY.md ──────────────────────────────────────────────────────────────

cat > "$OUTPUT_DIR/SUMMARY.md" <<SUMMARY
# Scan Summary — $(basename "$TARGET_DIR")
Date: $(date +"%Y-%m-%d %H:%M")
Target: $TARGET_DIR

## Source Code Scanners
| Scanner | Output File | Status |
|---------|-------------|--------|
| Gitleaks (secrets)       | gitleaks.json       | $([ -f "$OUTPUT_DIR/gitleaks.json" ] && echo "✓" || echo "—") |
| Bandit (Python SAST)     | bandit.json         | $([ -f "$OUTPUT_DIR/bandit.json" ] && echo "✓" || echo "—") |
| Semgrep (SAST)           | semgrep.json        | $([ -f "$OUTPUT_DIR/semgrep.json" ] && echo "✓" || echo "—") |
| Trivy (CVEs)             | trivy-fs.json       | $([ -f "$OUTPUT_DIR/trivy-fs.json" ] && echo "✓" || echo "—") |
| Grype (CVEs)             | grype.json          | $([ -f "$OUTPUT_DIR/grype.json" ] && echo "✓" || echo "—") |
| Hadolint (Dockerfile)    | hadolint-*.json     | $(ls "$OUTPUT_DIR"/hadolint-*.json 2>/dev/null | head -1 | grep -q . && echo "✓" || echo "—") |

## Infrastructure Scanners
| Scanner | Output File | Status |
|---------|-------------|--------|
| Checkov (IaC)            | results_json.json   | $([ -f "$OUTPUT_DIR/results_json.json" ] && echo "✓" || echo "—") |
| Kubescape (K8s NSA)      | kubescape.json      | $([ -f "$OUTPUT_DIR/kubescape.json" ] && echo "✓" || echo "—") |
| Polaris (K8s)            | polaris.json        | $([ -f "$OUTPUT_DIR/polaris.json" ] && echo "✓" || echo "—") |
| Conftest (OPA)           | conftest.json       | $([ -f "$OUTPUT_DIR/conftest.json" ] && echo "✓" || echo "—") |
| Kube-bench (CIS)         | kube-bench.json     | $([ -f "$OUTPUT_DIR/kube-bench.json" ] && echo "✓" || echo "—") |

## Quick Finding Counts

Run from this directory to get counts:

\`\`\`bash
# Secrets
jq 'length' gitleaks.json 2>/dev/null || echo "0"

# Python HIGH/CRITICAL
jq '[.results[]|select(.issue_severity=="HIGH" or .issue_severity=="CRITICAL")]|length' bandit.json 2>/dev/null || echo "0"

# Dependency CRITICAL CVEs
jq '[.Results[]?.Vulnerabilities[]?|select(.Severity=="CRITICAL")]|length' trivy-fs.json 2>/dev/null || echo "0"

# Checkov failed checks
jq '.results.failed_checks|length' results_json.json 2>/dev/null || echo "0"
\`\`\`

## Next Steps

1. Review findings above
2. Look up error codes in: $PKG_DIR/02-fixers/README.md
3. Run the corresponding fix script for each finding
4. Re-scan: bash run-all-scanners.sh -t $TARGET_DIR -o ../post-fix-$(date +%Y%m%d)
SUMMARY

echo -e "${GREEN}SUMMARY.md written to $OUTPUT_DIR/SUMMARY.md${NC}"

# ─── Auto-triage ─────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}=== Auto-Triage: Generating REMEDIATION-PLAN.md ===${NC}"
if command -v python3 &>/dev/null && [[ -f "$SCRIPT_DIR/triage.py" ]]; then
    python3 "$SCRIPT_DIR/triage.py" --scan-dir "$OUTPUT_DIR" --project "$(basename "$TARGET_DIR")" 2>/dev/null || true
    if [[ -f "$OUTPUT_DIR/REMEDIATION-PLAN.md" ]]; then
        echo -e "${GREEN}REMEDIATION-PLAN.md generated${NC}"
    fi
else
    echo -e "${YELLOW}triage.py not found or Python unavailable — generate manually:${NC}"
    echo "  python3 $SCRIPT_DIR/triage.py --scan-dir $OUTPUT_DIR"
fi

echo ""
echo -e "${YELLOW}Next steps (follow Playbook 01a):${NC}"
echo "  1. Review: cat $OUTPUT_DIR/TARGET-PROFILE.md    (what we scanned)"
echo "  2. Review: cat $OUTPUT_DIR/REMEDIATION-PLAN.md  (what to fix)"
echo "  3. Fix:    bash $SCRIPT_DIR/auto-fix.sh --plan $OUTPUT_DIR/REMEDIATION-PLAN.md --target $TARGET_DIR"
echo "  4. Verify: bash $SCRIPT_DIR/run-all-scanners.sh -t $TARGET_DIR -l post-fix"
echo ""
