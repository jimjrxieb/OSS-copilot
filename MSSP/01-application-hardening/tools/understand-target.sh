#!/usr/bin/env bash
# understand-target.sh
# Pre-scan discovery: inventory the target, build scanner exclude list,
# flag false positive sources BEFORE any scanner runs.
#
# This is the "Understand" phase. Run this BEFORE run-all-scanners.sh.
# A senior engineer walks the codebase before scanning. This script does
# that walk automatically — so JADE doesn't waste time on .terraform/ CVEs.
#
# Usage:
#   bash understand-target.sh --target-dir /path/to/client-repo
#   bash understand-target.sh --target-dir /path/to/client-repo --output /path/to/output/
#
# Outputs:
#   TARGET-PROFILE.md     — Human-readable target inventory
#   .scanner-excludes     — Exclude list for run-all-scanners.sh
#   .scanner-config.env   — Scanner flags/config for this specific target
#
# Methodology: Understand → Secure → Optimize → Outcome
# This tool implements UNDERSTAND. run-all-scanners.sh implements SECURE.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

TARGET_DIR="."
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target-dir) TARGET_DIR="$2"; shift 2 ;;
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Pre-scan target discovery. Run BEFORE scanning.

Usage: bash understand-target.sh --target-dir <path> [--output <dir>]

What it does:
  1. Inventories languages, frameworks, file counts
  2. Identifies build artifacts and vendor directories
  3. Detects GP-Copilot artifacts (findings JSON, .bak files)
  4. Picks relevant scanners for this tech stack
  5. Builds exclude list to prevent false positives
  6. Flags potential noise sources
  7. Outputs TARGET-PROFILE.md for human review

Run this first, review the profile, then run scanners:
  bash understand-target.sh -t ~/client-repo -o ~/reports/
  cat ~/reports/TARGET-PROFILE.md
  bash run-all-scanners.sh -t ~/client-repo -o ~/reports/ --exclude-file ~/reports/.scanner-excludes
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown: $1${NC}"; exit 1 ;;
  esac
done

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$TARGET_DIR"
fi
mkdir -p "$OUTPUT_DIR"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  JADE — UNDERSTAND: Pre-Scan Target Discovery               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo "  Target: $TARGET_DIR"
echo ""

# ─── 1. Total file inventory ─────────────────────────────────────────────────

echo -e "${BLUE}[1/8] File inventory...${NC}"

TOTAL_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' | wc -l)

PY_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "*.py" | wc -l)
GO_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "*.go" | wc -l)
JS_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) | wc -l)
JAVA_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.java" -o -name "*.kt" \) | wc -l)
RUBY_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "*.rb" | wc -l)
YAML_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.yaml" -o -name "*.yml" \) | wc -l)
TF_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "*.tf" | wc -l)
DOCKER_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "Dockerfile*" -not -name "*.bak" | wc -l)
REGO_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "*.rego" | wc -l)
SHELL_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "*.sh" | wc -l)
CF_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.template" -o -name "*.cfn.yaml" -o -name "*.cfn.json" \) | wc -l)

echo "  Total: $TOTAL_FILES files"
echo "  Python: $PY_FILES | Go: $GO_FILES | JS/TS: $JS_FILES | Java: $JAVA_FILES"
echo "  YAML: $YAML_FILES | Terraform: $TF_FILES | Dockerfiles: $DOCKER_FILES"
echo "  Rego: $REGO_FILES | Shell: $SHELL_FILES"

# ─── 2. Detect build artifacts and vendor directories ─────────────────────────

echo ""
echo -e "${BLUE}[2/8] Detecting build artifacts and vendor directories...${NC}"

EXCLUDES=()
EXCLUDE_REASONS=()

# Standard build artifacts
for dir in .terraform node_modules vendor __pycache__ .venv venv .tox .mypy_cache \
           .pytest_cache dist build .eggs *.egg-info target .gradle .m2 \
           .next .nuxt .output _archive scanner_outputs; do
  FOUND=$(find "$TARGET_DIR" -maxdepth 4 -type d -name "$dir" -not -path '*/.git/*' 2>/dev/null | head -1)
  if [[ -n "$FOUND" ]]; then
    REL_PATH="${FOUND#$TARGET_DIR/}"
    EXCLUDES+=("$REL_PATH")

    # Count files in artifact dir
    ARTIFACT_FILES=$(find "$FOUND" -type f | wc -l)
    echo -e "  ${YELLOW}ARTIFACT${NC} $REL_PATH/ ($ARTIFACT_FILES files)"

    case "$dir" in
      .terraform)
        EXCLUDE_REASONS+=("$REL_PATH: Terraform provider binaries — compiled Go, NOT your code. Grype will find 50-100+ CVEs in Go stdlib embedded in provider binaries. ALL are false positives for your codebase.")
        ;;
      node_modules)
        EXCLUDE_REASONS+=("$REL_PATH: NPM dependencies — scan via package-lock.json instead of filesystem. Grype/Trivy detect CVEs from lockfile, not by scanning 50K node_modules files.")
        ;;
      vendor)
        EXCLUDE_REASONS+=("$REL_PATH: Vendored Go/PHP dependencies — scan via go.mod/composer.lock instead.")
        ;;
      __pycache__|.venv|venv)
        EXCLUDE_REASONS+=("$REL_PATH: Python cache/virtualenv — not source code.")
        ;;
      *)
        EXCLUDE_REASONS+=("$REL_PATH: Build artifact — not source code.")
        ;;
    esac
  fi
done

if [[ ${#EXCLUDES[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}No build artifacts found${NC}"
fi

# ─── 3. Detect GP-Copilot artifacts ──────────────────────────────────────────

echo ""
echo -e "${BLUE}[3/8] Detecting GP-Copilot / engagement artifacts...${NC}"

# GP-Copilot directory
if [[ -d "$TARGET_DIR/GP-Copilot" ]]; then
  GP_FILES=$(find "$TARGET_DIR/GP-Copilot" -type f | wc -l)
  echo -e "  ${YELLOW}GP-COPILOT${NC} GP-Copilot/ ($GP_FILES files — playbooks, findings, summaries)"
  EXCLUDES+=("GP-Copilot")
  EXCLUDE_REASONS+=("GP-Copilot/: Engagement artifacts from prior GP-Copilot runs. Contains findings JSON with example secrets/keys that Gitleaks will flag as false positives.")

  # Check for findings JSON that contain example secrets
  FINDINGS_JSON=$(find "$TARGET_DIR/GP-Copilot" -name "*.json" -path "*/findings/*" | wc -l)
  if [[ $FINDINGS_JSON -gt 0 ]]; then
    echo -e "  ${YELLOW}  └─ $FINDINGS_JSON findings JSON files (will trigger Gitleaks FPs)${NC}"
  fi
fi

# Backup files
BAK_COUNT=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.bak" -o -name "*.jade_backup" -o -name "*.jade_phase2_backup" \) | wc -l)
if [[ $BAK_COUNT -gt 0 ]]; then
  echo -e "  ${YELLOW}BACKUPS${NC} $BAK_COUNT .bak/.jade_backup files (will trigger Checkov Dockerfile FPs)"
  EXCLUDES+=("*.bak" "*.jade_backup" "*.jade_phase2_backup")
  EXCLUDE_REASONS+=("*.bak: Backup files from prior JADE remediation. Checkov scans Dockerfile.bak as if it were a real Dockerfile.")
fi

# ─── 4. Detect CloudFormation templates (Checkov framework conflict) ─────────

echo ""
echo -e "${BLUE}[4/8] Detecting IaC frameworks...${NC}"

HAS_TERRAFORM=false
HAS_CLOUDFORMATION=false
HAS_KUBERNETES=false
HAS_KUSTOMIZE=false

if [[ $TF_FILES -gt 0 ]]; then
  HAS_TERRAFORM=true
  echo "  ✓ Terraform ($TF_FILES .tf files)"
fi

# CloudFormation detection
CF_FOUND=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) -exec grep -l "AWSTemplateFormatVersion\|AWS::CloudFormation\|Type: AWS::" {} + 2>/dev/null | wc -l)
if [[ $CF_FOUND -gt 0 ]]; then
  HAS_CLOUDFORMATION=true
  echo "  ✓ CloudFormation ($CF_FOUND templates)"
fi

# Kubernetes detection
K8S_FOUND=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' \( -name "*.yaml" -o -name "*.yml" \) -exec grep -l "^apiVersion:" {} + 2>/dev/null | wc -l)
if [[ $K8S_FOUND -gt 0 ]]; then
  HAS_KUBERNETES=true
  echo "  ✓ Kubernetes manifests ($K8S_FOUND files)"
fi

KUSTOMIZE_FOUND=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -name "kustomization.yaml" | wc -l)
if [[ $KUSTOMIZE_FOUND -gt 0 ]]; then
  HAS_KUSTOMIZE=true
  echo "  ✓ Kustomize ($KUSTOMIZE_FOUND kustomization.yaml files)"
fi

if [[ $REGO_FILES -gt 0 ]]; then
  echo "  ✓ OPA/Rego policies ($REGO_FILES .rego files)"
fi

# ─── 5. Detect existing security configs ──────────────────────────────────────

echo ""
echo -e "${BLUE}[5/8] Detecting existing security configs...${NC}"

for config in .gitignore .dockerignore .bandit .bandit.yaml .hadolint.yaml .gitleaks.toml \
              .semgrep.yaml .trivyignore .checkov.yaml .pre-commit-config.yaml; do
  if [[ -f "$TARGET_DIR/$config" ]]; then
    echo -e "  ${GREEN}✓${NC} $config exists"
  fi
done

# Check .gitignore for key exclusions
if [[ -f "$TARGET_DIR/.gitignore" ]]; then
  echo ""
  echo "  .gitignore covers:"
  for pattern in ".terraform" "node_modules" "vendor" "__pycache__" ".env" "*.bak"; do
    if grep -q "$pattern" "$TARGET_DIR/.gitignore" 2>/dev/null; then
      echo -e "    ${GREEN}✓${NC} $pattern"
    else
      echo -e "    ${YELLOW}✗${NC} $pattern — NOT gitignored (may cause scanner noise)"
    fi
  done
fi

# ─── 6. Determine relevant scanners ──────────────────────────────────────────

echo ""
echo -e "${BLUE}[6/8] Determining relevant scanners...${NC}"

SCANNERS=("gitleaks" "trivy-fs")  # Always run
SKIP_SCANNERS=()

if [[ $PY_FILES -gt 0 ]]; then SCANNERS+=("bandit"); echo "  + bandit (Python detected)"; fi
[[ $PY_FILES -eq 0 ]] && SKIP_SCANNERS+=("bandit") && echo "  - bandit (no Python)"

SCANNERS+=("semgrep")
echo "  + semgrep (always — multi-language)"

if [[ $DOCKER_FILES -gt 0 ]]; then SCANNERS+=("hadolint"); echo "  + hadolint (Dockerfiles detected)"; fi
[[ $DOCKER_FILES -eq 0 ]] && SKIP_SCANNERS+=("hadolint") && echo "  - hadolint (no Dockerfiles)"

if $HAS_TERRAFORM || $HAS_CLOUDFORMATION || $HAS_KUBERNETES; then
  SCANNERS+=("checkov")
  echo "  + checkov (IaC detected)"
fi

if $HAS_KUBERNETES; then
  SCANNERS+=("polaris" "conftest")
  echo "  + polaris, conftest (K8s manifests detected)"
fi

SCANNERS+=("grype")
echo "  + grype (CVE cross-check)"

echo ""
echo "  Scanners: ${#SCANNERS[@]} active, ${#SKIP_SCANNERS[@]} skipped"

# ─── 7. Estimate scan complexity ─────────────────────────────────────────────

echo ""
echo -e "${BLUE}[7/8] Estimating scan complexity...${NC}"

# Files that scanners will actually process (excluding artifacts)
SCANNABLE_FILES=$(find "$TARGET_DIR" -type f -not -path '*/.git/*' -not -path '*/.terraform/*' \
  -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/__pycache__/*' \
  -not -path '*/GP-Copilot/*' -not -name '*.bak' -not -name '*.pyc' | wc -l)

echo "  Total files: $TOTAL_FILES"
echo "  Scannable (after excludes): $SCANNABLE_FILES"
echo "  Excluded: $((TOTAL_FILES - SCANNABLE_FILES)) files (build artifacts, caches, backups)"

if [[ $TOTAL_FILES -gt 1000 ]]; then
  echo -e "  ${YELLOW}Large codebase — consider using --include-dir to scope scan${NC}"
fi

# ─── 8. Flag potential false positive sources ─────────────────────────────────

echo ""
echo -e "${BLUE}[8/8] Flagging potential false positive sources...${NC}"

FP_WARNINGS=()

# .terraform binaries
if [[ -d "$TARGET_DIR/infrastructure/terraform/.terraform" ]] || [[ -d "$TARGET_DIR/.terraform" ]]; then
  FP_WARNINGS+=("GRYPE: .terraform/providers/ contains compiled Go binaries (Terraform providers). Grype will report 50-100+ Go stdlib CVEs. These are NOT your code — they are HashiCorp's compiled provider binaries. EXCLUDE from Grype scan.")
  echo -e "  ${RED}⚠ .terraform/providers/${NC} — Grype will find 50-100+ false positive Go CVEs"
fi

# GP-Copilot findings JSON
if [[ -d "$TARGET_DIR/GP-Copilot" ]]; then
  FP_WARNINGS+=("GITLEAKS: GP-Copilot/jsa-*/findings/*.json contains scan outputs with example secrets/keys. These are findings FROM scans, not real secrets. EXCLUDE GP-Copilot/ from Gitleaks.")
  echo -e "  ${RED}⚠ GP-Copilot/findings/${NC} — Gitleaks will flag example secrets in scan output files"
fi

# .bak files
if [[ $BAK_COUNT -gt 0 ]]; then
  FP_WARNINGS+=("CHECKOV: *.bak files (Dockerfile.bak) will be scanned as Dockerfiles. These are pre-fix backups. EXCLUDE *.bak from Checkov.")
  echo -e "  ${RED}⚠ *.bak files${NC} — Checkov will flag backup Dockerfiles"
fi

# Kustomize duplicate scanning
if $HAS_KUSTOMIZE && $HAS_KUBERNETES; then
  FP_WARNINGS+=("CHECKOV: Kustomize overlays duplicate base manifest findings. The same deployment.yaml gets scanned as both 'kubernetes' and 'kustomize' framework — expect 2x finding count on shared manifests.")
  echo -e "  ${YELLOW}⚠ Kustomize + K8s${NC} — Checkov will double-count findings in overlays"
fi

# CloudFormation + Terraform overlap
if $HAS_CLOUDFORMATION && $HAS_TERRAFORM; then
  FP_WARNINGS+=("CHECKOV: Both CloudFormation and Terraform detected. Some controls may appear in both frameworks — expect overlap in findings count.")
  echo -e "  ${YELLOW}⚠ CF + Terraform${NC} — Checkov may flag same control in both frameworks"
fi

if [[ ${#FP_WARNINGS[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}No major false positive sources detected${NC}"
fi

# ─── Write outputs ────────────────────────────────────────────────────────────

# Write .scanner-excludes
EXCLUDE_FILE="$OUTPUT_DIR/.scanner-excludes"
{
  echo "# Auto-generated by understand-target.sh"
  echo "# Pass to run-all-scanners.sh: --exclude-file $EXCLUDE_FILE"
  echo "#"
  for excl in "${EXCLUDES[@]}"; do
    echo "$excl"
  done
} > "$EXCLUDE_FILE"

# Write .scanner-config.env
CONFIG_FILE="$OUTPUT_DIR/.scanner-config.env"
{
  echo "# Auto-generated by understand-target.sh"
  echo "# Source this before running scanners"
  echo "TARGET_DIR=\"$TARGET_DIR\""
  echo "SCANNABLE_FILES=$SCANNABLE_FILES"
  echo "SKIP_SCANNERS=\"${SKIP_SCANNERS[*]}\""
  echo "HAS_TERRAFORM=$HAS_TERRAFORM"
  echo "HAS_CLOUDFORMATION=$HAS_CLOUDFORMATION"
  echo "HAS_KUBERNETES=$HAS_KUBERNETES"
  echo "HAS_KUSTOMIZE=$HAS_KUSTOMIZE"
  echo "GRYPE_EXCLUDE=\".terraform,node_modules,vendor,GP-Copilot\""
} > "$CONFIG_FILE"

# Write TARGET-PROFILE.md
PROFILE="$OUTPUT_DIR/TARGET-PROFILE.md"
{
  echo "# Target Profile — $(basename "$TARGET_DIR")"
  echo ""
  echo "**Generated:** $(date +"%Y-%m-%d %H:%M")"
  echo "**Target:** $TARGET_DIR"
  echo "**Phase:** Understand (pre-scan discovery)"
  echo ""
  echo "## Inventory"
  echo ""
  echo "| Metric | Count |"
  echo "|--------|-------|"
  echo "| Total files | $TOTAL_FILES |"
  echo "| Scannable files | $SCANNABLE_FILES |"
  echo "| Excluded (artifacts) | $((TOTAL_FILES - SCANNABLE_FILES)) |"
  echo ""
  echo "| Language | Files |"
  echo "|----------|-------|"
  [[ $PY_FILES -gt 0 ]] && echo "| Python | $PY_FILES |"
  [[ $GO_FILES -gt 0 ]] && echo "| Go | $GO_FILES |"
  [[ $JS_FILES -gt 0 ]] && echo "| JavaScript/TypeScript | $JS_FILES |"
  [[ $JAVA_FILES -gt 0 ]] && echo "| Java/Kotlin | $JAVA_FILES |"
  [[ $RUBY_FILES -gt 0 ]] && echo "| Ruby | $RUBY_FILES |"
  [[ $YAML_FILES -gt 0 ]] && echo "| YAML | $YAML_FILES |"
  [[ $TF_FILES -gt 0 ]] && echo "| Terraform | $TF_FILES |"
  [[ $DOCKER_FILES -gt 0 ]] && echo "| Dockerfiles | $DOCKER_FILES |"
  [[ $REGO_FILES -gt 0 ]] && echo "| OPA Rego | $REGO_FILES |"
  [[ $SHELL_FILES -gt 0 ]] && echo "| Shell | $SHELL_FILES |"
  echo ""
  echo "## IaC Frameworks Detected"
  echo ""
  $HAS_TERRAFORM && echo "- Terraform ($TF_FILES files)"
  $HAS_CLOUDFORMATION && echo "- CloudFormation ($CF_FOUND templates)"
  $HAS_KUBERNETES && echo "- Kubernetes ($K8S_FOUND manifests)"
  $HAS_KUSTOMIZE && echo "- Kustomize ($KUSTOMIZE_FOUND overlays)"
  [[ $REGO_FILES -gt 0 ]] && echo "- OPA/Rego ($REGO_FILES policies)"
  echo ""
  echo "## Scanners Selected"
  echo ""
  echo "| Scanner | Status | Reason |"
  echo "|---------|--------|--------|"
  for s in "${SCANNERS[@]}"; do
    echo "| $s | Active | Language/framework match |"
  done
  for s in "${SKIP_SCANNERS[@]}"; do
    echo "| $s | Skip | No matching files |"
  done
  echo ""
  echo "## Excluded Directories"
  echo ""
  if [[ ${#EXCLUDE_REASONS[@]} -gt 0 ]]; then
    for reason in "${EXCLUDE_REASONS[@]}"; do
      echo "- **${reason%%:*}**: ${reason#*: }"
    done
  else
    echo "No exclusions needed."
  fi
  echo ""
  echo "## False Positive Warnings"
  echo ""
  if [[ ${#FP_WARNINGS[@]} -gt 0 ]]; then
    for warning in "${FP_WARNINGS[@]}"; do
      SCANNER="${warning%%:*}"
      DETAIL="${warning#*: }"
      echo "### $SCANNER"
      echo "$DETAIL"
      echo ""
    done
  else
    echo "No major false positive sources detected."
  fi
  echo ""
  echo "## Next Steps"
  echo ""
  echo "1. Review this profile — does the inventory match expectations?"
  echo "2. Run scanners with excludes:"
  echo '   ```bash'
  echo "   bash run-all-scanners.sh -t $TARGET_DIR \\"
  for excl in "${EXCLUDES[@]}"; do
    echo "     --skip-dir $excl \\"
  done
  for s in "${SKIP_SCANNERS[@]}"; do
    echo "     --skip-scanner $s \\"
  done
  echo '   ```'
  echo "3. Review REMEDIATION-PLAN.md after scan completes"
  echo ""
  echo "---"
  echo "*Generated by JADE understand-target.sh — Understand before Secure*"
} > "$PROFILE"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Outputs:${NC}"
echo "    TARGET-PROFILE.md    → $PROFILE"
echo "    .scanner-excludes    → $EXCLUDE_FILE"
echo "    .scanner-config.env  → $CONFIG_FILE"
echo ""
echo -e "${YELLOW}  Next: Review TARGET-PROFILE.md, then run scanners:${NC}"
echo "    cat $PROFILE"
echo "    bash run-all-scanners.sh -t $TARGET_DIR -o $OUTPUT_DIR"
echo ""
