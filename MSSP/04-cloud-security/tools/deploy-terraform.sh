#!/usr/bin/env bash
# deploy-terraform.sh — Deploy Terraform with validation, security scans, and execution plans
# Usage: bash tools/deploy-terraform.sh --dir ./terraform [--auto-approve] [--destroy]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR=""
AUTO_APPROVE=false
DESTROY=false
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") --dir <terraform-dir> [OPTIONS]

Options:
  --dir DIR          Terraform directory (required)
  --auto-approve     Skip interactive approval
  --destroy          Run terraform destroy instead of apply
  --dry-run          Run init + plan only, no apply
  --var-file FILE    Path to tfvars file
  -h, --help         Show this help

Examples:
  $(basename "$0") --dir ./terraform
  $(basename "$0") --dir ./terraform --var-file environments/production/terraform.tfvars
  $(basename "$0") --dir ./terraform --destroy
EOF
  exit 0
}

VAR_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) TF_DIR="$2"; shift 2 ;;
    --auto-approve) AUTO_APPROVE=true; shift ;;
    --destroy) DESTROY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --var-file) VAR_FILE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[[ -z "$TF_DIR" ]] && echo "ERROR: --dir is required" && exit 1
[[ ! -d "$TF_DIR" ]] && echo "ERROR: Directory not found: $TF_DIR" && exit 1

echo "=== GP-Consulting: Terraform Deployment ==="
echo "Directory: $TF_DIR"
echo ""

# Step 1: Security scan (if checkov available)
if command -v checkov &>/dev/null; then
  echo "[1/4] Running Checkov IaC security scan..."
  checkov -d "$TF_DIR" --framework terraform --compact --quiet || true
  echo ""
else
  echo "[1/4] Checkov not installed — skipping IaC scan"
  echo "  Install: pip install checkov"
  echo ""
fi

# Step 2: Terraform init
echo "[2/4] Running terraform init..."
cd "$TF_DIR"
terraform init -input=false
echo ""

# Step 3: Terraform plan
echo "[3/4] Running terraform plan..."
PLAN_ARGS=(-input=false -out=tfplan)
[[ -n "$VAR_FILE" ]] && PLAN_ARGS+=(-var-file="$VAR_FILE")
[[ "$DESTROY" == "true" ]] && PLAN_ARGS+=(-destroy)

terraform plan "${PLAN_ARGS[@]}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "=== Dry run complete. Plan saved to tfplan ==="
  exit 0
fi

# Step 4: Terraform apply
echo "[4/4] Applying terraform plan..."
APPLY_ARGS=(tfplan)
[[ "$AUTO_APPROVE" == "true" ]] && APPLY_ARGS=(-auto-approve)

if [[ "$AUTO_APPROVE" == "true" ]]; then
  terraform apply -auto-approve ${VAR_FILE:+-var-file="$VAR_FILE"}
else
  terraform apply tfplan
fi

echo ""
echo "=== Deployment complete ==="
terraform output
