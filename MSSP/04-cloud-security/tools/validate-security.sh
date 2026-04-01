#!/usr/bin/env bash
# validate-security.sh — Run all IaC security scanners against Terraform/CloudFormation
# Usage: bash tools/validate-security.sh --dir ./terraform [--format json]

set -euo pipefail

TARGET_DIR=""
FORMAT="text"
FAILED=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --dir <iac-directory> [OPTIONS]

Options:
  --dir DIR        Directory containing IaC files (required)
  --format FMT     Output format: text, json (default: text)
  -h, --help       Show this help

Scanners used (if installed):
  - Checkov       IaC misconfiguration detection
  - TFsec         Terraform-specific security scanner
  - cfn-lint      CloudFormation linter
  - cfn_nag       CloudFormation security analysis
  - tfsec         Terraform static analysis
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) TARGET_DIR="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1"; usage ;;
  esac
done

[[ -z "$TARGET_DIR" ]] && echo "ERROR: --dir required" && exit 1
[[ ! -d "$TARGET_DIR" ]] && echo "ERROR: Directory not found: $TARGET_DIR" && exit 1

echo "=== GP-Consulting: IaC Security Validation ==="
echo "Target: $TARGET_DIR"
echo ""

# Detect IaC type
HAS_TF=$(find "$TARGET_DIR" -name "*.tf" -type f | head -1)
HAS_CFN=$(find "$TARGET_DIR" -name "*.yaml" -o -name "*.yml" -type f | head -1)

# Checkov (supports both TF and CFN)
if command -v checkov &>/dev/null; then
  echo "--- Checkov ---"
  FRAMEWORKS=""
  [[ -n "$HAS_TF" ]] && FRAMEWORKS="terraform"
  [[ -n "$HAS_CFN" ]] && FRAMEWORKS="${FRAMEWORKS:+$FRAMEWORKS,}cloudformation"

  if [[ -n "$FRAMEWORKS" ]]; then
    checkov -d "$TARGET_DIR" --framework "$FRAMEWORKS" --compact || FAILED=1
  fi
  echo ""
else
  echo "--- Checkov: NOT INSTALLED (pip install checkov) ---"
  echo ""
fi

# TFsec (Terraform only)
if [[ -n "$HAS_TF" ]]; then
  if command -v tfsec &>/dev/null; then
    echo "--- TFsec ---"
    tfsec "$TARGET_DIR" --format "$FORMAT" || FAILED=1
    echo ""
  else
    echo "--- TFsec: NOT INSTALLED (brew install tfsec) ---"
    echo ""
  fi
fi

# cfn-lint (CloudFormation only)
if [[ -n "$HAS_CFN" ]]; then
  if command -v cfn-lint &>/dev/null; then
    echo "--- cfn-lint ---"
    find "$TARGET_DIR" -name "*.yaml" -o -name "*.yml" | while read -r f; do
      echo "  Checking: $f"
      cfn-lint "$f" || FAILED=1
    done
    echo ""
  else
    echo "--- cfn-lint: NOT INSTALLED (pip install cfn-lint) ---"
    echo ""
  fi

  if command -v cfn_nag_scan &>/dev/null; then
    echo "--- cfn_nag ---"
    find "$TARGET_DIR" -name "*.yaml" -o -name "*.yml" | while read -r f; do
      echo "  Scanning: $f"
      cfn_nag_scan --input-path "$f" || FAILED=1
    done
    echo ""
  else
    echo "--- cfn_nag: NOT INSTALLED (gem install cfn-nag) ---"
    echo ""
  fi
fi

echo "=== Validation complete ==="
if [[ $FAILED -ne 0 ]]; then
  echo "STATUS: FINDINGS DETECTED — review output above"
  exit 1
else
  echo "STATUS: PASSED"
  exit 0
fi
