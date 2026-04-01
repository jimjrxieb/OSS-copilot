#!/usr/bin/env bash
# auto-fix.sh
# Read triage output and execute D-rank fixer scripts automatically.
# C-rank fixes are proposed but not executed without --approve-c flag.
# B/S-rank are logged and skipped.
#
# This is the "last mile" — triage.py tells you what to fix, auto-fix.sh does it.
#
# Usage:
#   bash auto-fix.sh --scan-dir outputs/baseline-20260328 --target /path/to/repo
#   bash auto-fix.sh --scan-dir outputs/baseline-20260328 --target /path/to/repo --dry-run
#   bash auto-fix.sh --scan-dir outputs/baseline-20260328 --target /path/to/repo --approve-c
#
# Workflow:
#   1. Reads scanner JSON from scan-dir (same dir run-all-scanners.sh outputs to)
#   2. For each finding, looks up the fixer script in 02-fixers/
#   3. D-rank: executes fixer automatically (with snapshot)
#   4. C-rank: shows proposed fix, skips unless --approve-c
#   5. B/S-rank: logs to ESCALATED.md, never touches
#   6. Outputs FIX-REPORT.md with everything that was done
#
# A human reads the same output. An AI reads the same output.
# Same playbook, same scripts, same decision tree.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
FIXERS_DIR="$PKG_DIR/02-fixers"

SCAN_DIR=""
TARGET_DIR=""
DRY_RUN=false
APPROVE_C=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-dir) SCAN_DIR="$2"; shift 2 ;;
    --target) TARGET_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --approve-c) APPROVE_C=true; shift ;;
    -h|--help)
      cat <<EOF
Execute fixer scripts based on scan results.

Usage:
  bash auto-fix.sh --scan-dir <scan-output-dir> --target <repo-dir> [OPTIONS]

Options:
  --scan-dir DIR    Directory with scanner JSON (from run-all-scanners.sh)
  --target DIR      Target repository to fix
  --dry-run         Show what would be fixed without changing files
  --approve-c       Also execute C-rank fixes (default: propose only)

What it does:
  1. Reads each scanner's JSON output
  2. Maps findings to fixer scripts using the same routing table as triage.py
  3. E/D rank: runs the fixer script automatically
  4. C rank: shows the proposed command (runs if --approve-c)
  5. B/S rank: logs to ESCALATED.md for human review
  6. Snapshots every file before changing it (.bak backup)
  7. Outputs FIX-REPORT.md

Playbook reference: 01-APP-SEC/playbooks/01a-fix-baseline.md
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown: $1${NC}"; exit 1 ;;
  esac
done

if [[ -z "$SCAN_DIR" || -z "$TARGET_DIR" ]]; then
  echo "Usage: bash auto-fix.sh --scan-dir <dir> --target <repo>"
  exit 1
fi

SCAN_DIR="$(cd "$SCAN_DIR" && pwd)"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  JADE — Auto-Fix: Execute Remediation                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo "  Scan results : $SCAN_DIR"
echo "  Target repo  : $TARGET_DIR"
echo "  Mode         : $(if $DRY_RUN; then echo 'DRY RUN'; else echo 'LIVE'; fi)"
echo "  C-rank       : $(if $APPROVE_C; then echo 'APPROVED'; else echo 'PROPOSE ONLY'; fi)"
echo ""

FIXED=0; PROPOSED=0; ESCALATED=0; SKIPPED=0

FIX_LOG="$SCAN_DIR/FIX-REPORT.md"
ESCALATE_LOG="$SCAN_DIR/ESCALATED.md"

{
  echo "# Fix Report — $(basename "$TARGET_DIR")"
  echo ""
  echo "**Date:** $(date +"%Y-%m-%d %H:%M")"
  echo "**Target:** $TARGET_DIR"
  echo "**Mode:** $(if $DRY_RUN; then echo 'Dry Run'; else echo 'Live'; fi)"
  echo ""
  echo "## Fixes Applied"
  echo ""
  echo "| # | File | Finding | Fixer | Rank | Status |"
  echo "|---|------|---------|-------|------|--------|"
} > "$FIX_LOG"

{
  echo "# Escalated Findings — $(basename "$TARGET_DIR")"
  echo ""
  echo "**These require human review. JADE cannot fix them autonomously.**"
  echo ""
  echo "| # | File | Finding | Rank | Why |"
  echo "|---|------|---------|------|-----|"
} > "$ESCALATE_LOG"

run_fixer() {
  local file="$1" fixer_cmd="$2" finding="$3" rank="$4"
  local full_path="$TARGET_DIR/$file"
  local num=$((FIXED + PROPOSED + 1))

  if [[ ! -f "$full_path" ]]; then
    echo -e "  ${YELLOW}SKIP${NC} $file — file not found"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  case "$rank" in
    E|D)
      if $DRY_RUN; then
        echo -e "  ${BLUE}[DRY]${NC} [$rank] $file — would run: $fixer_cmd"
        PROPOSED=$((PROPOSED + 1))
        echo "| $num | \`$file\` | $finding | \`$fixer_cmd\` | $rank | DRY RUN |" >> "$FIX_LOG"
      else
        # Snapshot before fix
        cp "$full_path" "${full_path}.bak" 2>/dev/null || true
        echo -e "  ${GREEN}[FIX]${NC} [$rank] $file — running: $fixer_cmd"
        eval "$fixer_cmd" 2>/dev/null || echo -e "  ${YELLOW}  └─ Fixer returned non-zero (may still have applied changes)${NC}"
        FIXED=$((FIXED + 1))
        echo "| $num | \`$file\` | $finding | \`$fixer_cmd\` | $rank | FIXED |" >> "$FIX_LOG"
      fi
      ;;
    C)
      if $APPROVE_C; then
        if $DRY_RUN; then
          echo -e "  ${BLUE}[DRY]${NC} [$rank] $file — would run: $fixer_cmd"
          PROPOSED=$((PROPOSED + 1))
        else
          cp "$full_path" "${full_path}.bak" 2>/dev/null || true
          echo -e "  ${YELLOW}[C-FIX]${NC} [$rank] $file — running (approved): $fixer_cmd"
          eval "$fixer_cmd" 2>/dev/null || true
          FIXED=$((FIXED + 1))
        fi
        echo "| $num | \`$file\` | $finding | \`$fixer_cmd\` | $rank | $(if $DRY_RUN; then echo 'DRY RUN'; else echo 'FIXED (C-approved)'; fi) |" >> "$FIX_LOG"
      else
        echo -e "  ${YELLOW}[PROPOSE]${NC} [$rank] $file — $fixer_cmd"
        PROPOSED=$((PROPOSED + 1))
        echo "| $num | \`$file\` | $finding | \`$fixer_cmd\` | $rank | PROPOSED (needs --approve-c) |" >> "$FIX_LOG"
      fi
      ;;
    B|S)
      echo -e "  ${RED}[ESCALATE]${NC} [$rank] $file — $finding"
      ESCALATED=$((ESCALATED + 1))
      echo "| $num | \`$file\` | $finding | $rank | Requires human review |" >> "$ESCALATE_LOG"
      ;;
  esac
}

# ─── Process Bandit findings ─────────────────────────────────────────────────

if [[ -f "$SCAN_DIR/bandit.json" ]]; then
  echo -e "${BLUE}=== Bandit findings ===${NC}"
  BANDIT_COUNT=$(jq '.results | length' "$SCAN_DIR/bandit.json" 2>/dev/null || echo 0)

  if [[ $BANDIT_COUNT -gt 0 ]]; then
    jq -r '.results[] | "\(.filename | ltrimstr("'"$TARGET_DIR"'/"))|\(.test_id)|\(.line_number)|\(.issue_severity)"' "$SCAN_DIR/bandit.json" 2>/dev/null | while IFS='|' read -r file rule line sev; do
      case "$rule" in
        B303|B324)   run_fixer "$file" "python3 $FIXERS_DIR/python/fix-md5.py $TARGET_DIR/$file" "B303/B324 weak hash" "D" ;;
        B311|B312)   run_fixer "$file" "bash $FIXERS_DIR/python/fix-weak-random.sh $TARGET_DIR/$file" "B311 insecure random" "D" ;;
        B602|B603)   run_fixer "$file" "bash $FIXERS_DIR/python/fix-shell-injection.sh $TARGET_DIR/$file" "B602 shell injection" "D" ;;
        B105|B106|B107) run_fixer "$file" "bash $FIXERS_DIR/secrets/fix-env-reference.sh $TARGET_DIR/$file $line PASSWORD" "B105-107 hardcoded password" "E" ;;
        B506)        run_fixer "$file" "bash $FIXERS_DIR/python/fix-yaml-load.sh $TARGET_DIR/$file" "B506 unsafe yaml.load" "E" ;;
        B301)        run_fixer "$file" "bash $FIXERS_DIR/python/fix-pickle.sh $TARGET_DIR/$file" "B301 pickle" "C" ;;
        B102)        run_fixer "$file" "bash $FIXERS_DIR/python/fix-exec.sh $TARGET_DIR/$file" "B102 exec" "C" ;;
        B608)        run_fixer "$file" "" "B608 SQL injection — parameterize queries" "B" ;;
        B110)        run_fixer "$file" "" "B110 bare except:pass — add specific exception" "C" ;;
        B108)        echo -e "  ${GREEN}[ACCEPT]${NC} $file:$line B108 temp file — accepted risk (container uses emptyDir)" && SKIPPED=$((SKIPPED + 1)) ;;
        *)           echo -e "  ${YELLOW}[SKIP]${NC} $file $rule — no fixer mapped" && SKIPPED=$((SKIPPED + 1)) ;;
      esac
    done
  else
    echo "  No Bandit findings"
  fi
fi

# ─── Process Gitleaks findings ────────────────────────────────────────────────

if [[ -f "$SCAN_DIR/gitleaks.json" ]]; then
  echo -e "${BLUE}=== Gitleaks findings ===${NC}"
  GITLEAKS_COUNT=$(jq 'length' "$SCAN_DIR/gitleaks.json" 2>/dev/null || echo 0)

  if [[ $GITLEAKS_COUNT -gt 0 ]]; then
    jq -r '.[] | "\(.File)|\(.RuleID)|\(.StartLine)"' "$SCAN_DIR/gitleaks.json" 2>/dev/null | sort -u | while IFS='|' read -r file rule line; do
      # Skip GP-Copilot findings (false positives in scan output files)
      if [[ "$file" == GP-Copilot/* || "$file" == vulnerabilities/* || "$file" == external/* ]]; then
        echo -e "  ${GREEN}[FP]${NC} $file — scan artifact, not a real secret"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi
      run_fixer "$file" "bash $FIXERS_DIR/secrets/fix-env-reference.sh $TARGET_DIR/$file $line SECRET" "$rule secret detected" "E"
    done
  else
    echo "  No secrets found"
  fi
fi

# ─── Process Hadolint findings ────────────────────────────────────────────────

for hadolint_json in "$SCAN_DIR"/hadolint-*.json; do
  [[ -f "$hadolint_json" ]] || continue
  echo -e "${BLUE}=== Hadolint: $(basename "$hadolint_json") ===${NC}"
  COUNT=$(jq 'length' "$hadolint_json" 2>/dev/null || echo 0)

  if [[ $COUNT -gt 0 ]]; then
    jq -r '.[] | "\(.file)|\(.code)|\(.line)"' "$hadolint_json" 2>/dev/null | while IFS='|' read -r file code line; do
      case "$code" in
        DL3002) run_fixer "$file" "bash $FIXERS_DIR/dockerfile/add-nonroot-user.sh $TARGET_DIR/$file" "DL3002 no USER" "D" ;;
        DL3025|DL4006) run_fixer "$file" "bash $FIXERS_DIR/dockerfile/fix-cmd-format.sh $TARGET_DIR/$file" "DL4006 CMD format" "D" ;;
        DL4000) run_fixer "$file" "bash $FIXERS_DIR/dockerfile/fix-maintainer.sh $TARGET_DIR/$file" "DL4000 MAINTAINER" "E" ;;
        DL3003) run_fixer "$file" "bash $FIXERS_DIR/dockerfile/fix-workdir.sh $TARGET_DIR/$file" "DL3003 WORKDIR" "D" ;;
        *) echo -e "  ${YELLOW}[SKIP]${NC} $code — no fixer mapped" && SKIPPED=$((SKIPPED + 1)) ;;
      esac
    done
  else
    echo "  No findings"
  fi
done

# ─── Process Checkov K8s findings ─────────────────────────────────────────────

if [[ -f "$SCAN_DIR/results_json.json" ]]; then
  echo -e "${BLUE}=== Checkov findings ===${NC}"

  # Extract K8s manifest findings only (not terraform — those need different fixers)
  jq -r '.[] | select(.check_type == "kubernetes" or .check_type == "dockerfile") | .results.failed_checks[]? | "\(.file_path | ltrimstr("/"))|\(.check_id)|\(.file_line_range[0])"' "$SCAN_DIR/results_json.json" 2>/dev/null | sort -u | while IFS='|' read -r file check line; do
    # Skip .bak files
    [[ "$file" == *.bak ]] && continue

    case "$check" in
      CKV_K8S_6|CKV_K8S_20|CKV_K8S_22|CKV_K8S_28|CKV_K8S_37)
        run_fixer "$file" "bash $FIXERS_DIR/k8s-manifests/add-security-context.sh $TARGET_DIR/$file" "$check securityContext" "D" ;;
      CKV_K8S_11|CKV_K8S_12|CKV_K8S_13)
        run_fixer "$file" "bash $FIXERS_DIR/k8s-manifests/add-resource-limits.sh $TARGET_DIR/$file" "$check resource limits" "D" ;;
      CKV_K8S_8|CKV_K8S_9)
        run_fixer "$file" "bash $FIXERS_DIR/k8s-manifests/add-probes.sh $TARGET_DIR/$file" "$check probes" "C" ;;
      CKV_K8S_43)
        run_fixer "$file" "bash $FIXERS_DIR/k8s-manifests/fix-image-pull-policy.sh $TARGET_DIR/$file" "$check pullPolicy" "D" ;;
      CKV_K8S_15)
        run_fixer "$file" "bash $FIXERS_DIR/k8s-manifests/fix-image-pull-policy.sh $TARGET_DIR/$file" "$check imagePullPolicy" "D" ;;
      CKV_K8S_35)
        run_fixer "$file" "" "$check secrets as env vars — migrate to ExternalSecret" "C" ;;
      CKV_DOCKER_2)
        run_fixer "$file" "bash $FIXERS_DIR/dockerfile/add-healthcheck.sh $TARGET_DIR/$file" "$check HEALTHCHECK" "D" ;;
      CKV_DOCKER_3)
        run_fixer "$file" "bash $FIXERS_DIR/dockerfile/add-nonroot-user.sh $TARGET_DIR/$file" "$check USER" "D" ;;
      *)
        SKIPPED=$((SKIPPED + 1)) ;;
    esac
  done

  # Count terraform findings separately
  TF_FAILS=$(jq '[.[] | select(.check_type == "terraform") | .results.failed_checks | length] | add // 0' "$SCAN_DIR/results_json.json" 2>/dev/null)
  if [[ $TF_FAILS -gt 0 ]]; then
    echo -e "  ${YELLOW}$TF_FAILS Terraform findings — fix with playbook 14 (fix-terraform-findings)${NC}"
    echo "| — | terraform/ | $TF_FAILS CKV_AWS_* findings | See 04-CLOUD-SECURITY | D-C | See playbook 14 |" >> "$FIX_LOG"
  fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

{
  echo ""
  echo "## Summary"
  echo ""
  echo "| Status | Count |"
  echo "|--------|-------|"
  echo "| Fixed | $FIXED |"
  echo "| Proposed (C-rank) | $PROPOSED |"
  echo "| Escalated (B/S-rank) | $ESCALATED |"
  echo "| Skipped (no fixer / FP) | $SKIPPED |"
  echo ""
  echo "## Next Steps"
  echo ""
  echo "1. Review fixes: \`git diff\` in the target repo"
  echo "2. Review proposed: run with \`--approve-c\` to apply C-rank fixes"
  echo "3. Review escalated: \`cat $ESCALATE_LOG\`"
  echo "4. Re-scan: \`bash run-all-scanners.sh -t $TARGET_DIR -l post-fix\`"
  echo ""
  echo "---"
  echo "*Generated by JADE auto-fix.sh*"
} >> "$FIX_LOG"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Fixed      : $FIXED${NC}"
echo -e "  ${YELLOW}Proposed   : $PROPOSED${NC} (C-rank, needs --approve-c)"
echo -e "  ${RED}Escalated  : $ESCALATED${NC} (B/S-rank, needs human)"
echo -e "  Skipped    : $SKIPPED (no fixer mapped or false positive)"
echo ""
echo -e "  Reports:"
echo "    $FIX_LOG"
echo "    $ESCALATE_LOG"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review: cat $FIX_LOG"
echo "  2. Verify: bash $SCRIPT_DIR/run-all-scanners.sh -t $TARGET_DIR -l post-fix"
echo ""
