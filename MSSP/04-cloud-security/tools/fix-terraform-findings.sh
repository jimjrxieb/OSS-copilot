#!/usr/bin/env bash
# fix-terraform-findings.sh
# Scan Terraform modules with Checkov and generate fix patches for D-rank findings.
#
# Usage:
#   bash fix-terraform-findings.sh <terraform-dir> [--apply] [--dry-run]
#
# Modes:
#   --dry-run   Show what would be fixed (default)
#   --apply     Apply D-rank fixes directly to modules
#
# What it does:
#   1. Runs checkov on the target directory
#   2. Categorizes findings by fix type and rank
#   3. Generates HCL patches in /tmp/jsa-cascade/terraform-fixes/
#   4. Optionally applies D-rank fixes to the modules
#
# What it does NOT do:
#   - Apply C-rank fixes (EKS endpoint, cross-region replication)
#   - Modify resources it doesn't understand
#   - Touch .tfstate files

set -euo pipefail

TF_DIR="${1:?Usage: bash fix-terraform-findings.sh <terraform-dir> [--apply|--dry-run]}"
MODE="${2:---dry-run}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
CASCADE_DIR="/tmp/jsa-cascade/terraform-fixes"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [[ ! -d "$TF_DIR" ]]; then
  echo -e "${RED}ERROR: Directory not found: $TF_DIR${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Ghost Protocol — Terraform IaC Fixer ===${NC}"
echo "  Target : $TF_DIR"
echo "  Mode   : $MODE"
echo "  Output : $CASCADE_DIR"
echo ""

# --- Step 1: Validate terraform ---
echo -e "${CYAN}[1/4] Validating Terraform...${NC}"
if ! command -v terraform &>/dev/null; then
  echo -e "${RED}ERROR: terraform not found${NC}"
  exit 1
fi

cd "$TF_DIR"
if ! terraform validate -no-color &>/dev/null 2>&1; then
  echo -e "${YELLOW}WARNING: terraform validate failed — fixes may not apply cleanly${NC}"
fi

# --- Step 2: Run Checkov ---
echo -e "${CYAN}[2/4] Running Checkov scan...${NC}"
if ! command -v checkov &>/dev/null; then
  echo -e "${RED}ERROR: checkov not found. Install: pip install checkov${NC}"
  exit 1
fi

SCAN_JSON=$(mktemp)
checkov -d . --framework terraform --output json 2>/dev/null > "$SCAN_JSON" || true

# Count findings
TOTAL_PASSED=$(python3 -c "
import json, sys
data = json.load(open('$SCAN_JSON'))
results = data if isinstance(data, list) else [data]
passed = sum(len(r.get('results',{}).get('passed_checks',[])) for r in results)
print(passed)
" 2>/dev/null || echo "?")

TOTAL_FAILED=$(python3 -c "
import json, sys
data = json.load(open('$SCAN_JSON'))
results = data if isinstance(data, list) else [data]
failed = sum(len(r.get('results',{}).get('failed_checks',[])) for r in results)
print(failed)
" 2>/dev/null || echo "?")

echo "  Passed: $TOTAL_PASSED | Failed: $TOTAL_FAILED"

if [[ "$TOTAL_FAILED" == "0" ]]; then
  echo -e "${GREEN}No findings. Nothing to fix.${NC}"
  rm -f "$SCAN_JSON"
  exit 0
fi

# --- Step 3: Categorize findings ---
echo ""
echo -e "${CYAN}[3/4] Categorizing findings...${NC}"
mkdir -p "$CASCADE_DIR"

# Extract failed check IDs and files
python3 - "$SCAN_JSON" "$CASCADE_DIR" "$TIMESTAMP" << 'PYEOF'
import json, sys, os
from collections import defaultdict

scan_file = sys.argv[1]
cascade_dir = sys.argv[2]
timestamp = sys.argv[3]

data = json.load(open(scan_file))
results = data if isinstance(data, list) else [data]

# Collect all failed checks
failed = []
for r in results:
    for check in r.get("results", {}).get("failed_checks", []):
        evaluated = check.get("check_result", {})
        if isinstance(evaluated, dict):
            keys = evaluated.get("evaluated_keys", [])
        else:
            keys = []
        failed.append({
            "id": check.get("check_id", ""),
            "name": keys[0] if keys else "",
            "desc": check.get("check_id", "") + ": " + check.get("bc_check_id", check.get("check_id", "")),
            "file": check.get("file_path", ""),
            "resource": check.get("resource", ""),
            "check_name": check.get("check_id", "") + " — " + check.get("check_name", ""),
            "guideline": check.get("guideline", ""),
        })

# Categorize by fix type
categories = {
    "cloudwatch_kms": {
        "rank": "D",
        "ids": {"CKV_AWS_158"},
        "desc": "CloudWatch Log Group KMS Encryption",
        "template": "cloudwatch-kms.tf",
    },
    "s3_hardening": {
        "rank": "D",
        "ids": {"CKV_AWS_18", "CKV_AWS_300", "CKV2_AWS_61", "CKV2_AWS_62"},
        "desc": "S3 Access Logging + Lifecycle",
        "template": "s3-access-logging.tf",
    },
    "s3_replication": {
        "rank": "C",
        "ids": {"CKV_AWS_144"},
        "desc": "S3 Cross-Region Replication",
        "template": None,
    },
    "rds_hardening": {
        "rank": "D",
        "ids": {"CKV_AWS_118", "CKV_AWS_161", "CKV_AWS_226", "CKV_AWS_293", "CKV2_AWS_30"},
        "desc": "RDS Monitoring + IAM Auth + Query Logging",
        "template": "rds-hardening.tf",
    },
    "eks_endpoint": {
        "rank": "C",
        "ids": {"CKV_AWS_38", "CKV_AWS_39"},
        "desc": "EKS Public Endpoint Restriction",
        "template": None,
    },
    "sg_egress": {
        "rank": "C",
        "ids": {"CKV_AWS_382", "CKV_AWS_23"},
        "desc": "Security Group Egress Restriction",
        "template": None,
    },
    "lambda_hardening": {
        "rank": "D",
        "ids": {"CKV_AWS_115", "CKV_AWS_116", "CKV_AWS_117", "CKV_AWS_173", "CKV_AWS_272"},
        "desc": "Lambda VPC + DLQ + Concurrency + Encryption",
        "template": "lambda-hardening.tf",
    },
    "iam_scope": {
        "rank": "C",
        "ids": {"CKV_AWS_355", "CKV_AWS_290"},
        "desc": "IAM Policy Resource Scoping",
        "template": "iam-scope-flowlogs.tf",
    },
    "cloudtrail_sns": {
        "rank": "D",
        "ids": {"CKV_AWS_252"},
        "desc": "CloudTrail SNS Topic",
        "template": None,
    },
    "secrets_rotation": {
        "rank": "D",
        "ids": {"CKV2_AWS_57", "CKV_AWS_304"},
        "desc": "Secrets Manager Rotation",
        "template": None,
    },
    "vpc_default_sg": {
        "rank": "D",
        "ids": {"CKV2_AWS_12"},
        "desc": "VPC Default Security Group Lockdown",
        "template": "vpc-default-sg.tf",
    },
    "guardduty_org": {
        "rank": "C",
        "ids": {"CKV2_AWS_3"},
        "desc": "GuardDuty Organization-Level (skip if standalone)",
        "template": None,
    },
}

# Build report
report_lines = []
report_lines.append(f"# Terraform IaC Findings — Fix Report")
report_lines.append(f"# Generated: {timestamp}")
report_lines.append(f"# Total: {len(failed)} findings")
report_lines.append("")

d_rank_count = 0
c_rank_count = 0
uncategorized = []

for cat_key, cat in sorted(categories.items(), key=lambda x: (x[1]["rank"], x[0])):
    matches = [f for f in failed if f["id"] in cat["ids"]]
    if not matches:
        continue

    rank = cat["rank"]
    if rank == "D":
        d_rank_count += len(matches)
    else:
        c_rank_count += len(matches)

    report_lines.append(f"## [{rank}-rank] {cat['desc']} ({len(matches)} findings)")
    if cat["template"]:
        report_lines.append(f"Template: 01-iac-templates/terraform-hardening/{cat['template']}")
    report_lines.append("")
    for m in matches:
        report_lines.append(f"  - {m['id']} | {m['file']} | {m['resource']}")
    report_lines.append("")

# Check for uncategorized
all_cat_ids = set()
for cat in categories.values():
    all_cat_ids.update(cat["ids"])

for f in failed:
    if f["id"] not in all_cat_ids:
        uncategorized.append(f)

if uncategorized:
    report_lines.append(f"## [?-rank] Uncategorized ({len(uncategorized)} findings)")
    report_lines.append("")
    for u in uncategorized:
        report_lines.append(f"  - {u['id']} | {u['file']} | {u['resource']}")
    report_lines.append("")

report_lines.append(f"---")
report_lines.append(f"D-rank (auto-fixable): {d_rank_count}")
report_lines.append(f"C-rank (requires judgment): {c_rank_count}")
report_lines.append(f"Uncategorized: {len(uncategorized)}")

report_path = os.path.join(cascade_dir, f"fix-report-{timestamp}.md")
with open(report_path, "w") as f:
    f.write("\n".join(report_lines))

print(f"  Report: {report_path}")
print(f"  D-rank (auto-fixable): {d_rank_count}")
print(f"  C-rank (requires judgment): {c_rank_count}")
if uncategorized:
    print(f"  Uncategorized: {len(uncategorized)}")
PYEOF

rm -f "$SCAN_JSON"

# --- Step 4: Apply or report ---
echo ""
echo -e "${CYAN}[4/4] Fix actions...${NC}"

if [[ "$MODE" == "--dry-run" ]]; then
  echo ""
  echo -e "${YELLOW}DRY RUN — no changes made.${NC}"
  echo "  Review: $CASCADE_DIR/fix-report-$TIMESTAMP.md"
  echo ""
  echo "  To apply D-rank fixes:"
  echo "    bash fix-terraform-findings.sh $TF_DIR --apply"
  echo ""
  echo "  To apply individual categories manually, use the templates in:"
  echo "    GP-CONSULTING/07-CLOUD-SECURITY/01-iac-templates/terraform-hardening/"
  echo ""
  exit 0
fi

if [[ "$MODE" == "--apply" ]]; then
  echo -e "${YELLOW}Applying D-rank fixes...${NC}"
  echo ""

  FIXES_APPLIED=0

  # --- Fix: RDS hardening ---
  RDS_MAIN="modules/rds/main.tf"
  if [[ -f "$RDS_MAIN" ]]; then
    cp "$RDS_MAIN" "${RDS_MAIN}.bak"

    # Add IAM auth if missing
    if ! grep -q "iam_database_authentication_enabled" "$RDS_MAIN"; then
      sed -i '/deletion_protection/a\  iam_database_authentication_enabled = true' "$RDS_MAIN"
      echo -e "  ${GREEN}+${NC} RDS: iam_database_authentication_enabled"
      ((FIXES_APPLIED++))
    fi

    # Add auto minor version upgrade if missing
    if ! grep -q "auto_minor_version_upgrade" "$RDS_MAIN"; then
      sed -i '/deletion_protection/a\  auto_minor_version_upgrade = true' "$RDS_MAIN"
      echo -e "  ${GREEN}+${NC} RDS: auto_minor_version_upgrade"
      ((FIXES_APPLIED++))
    fi

    # Add enhanced monitoring if missing
    if ! grep -q "monitoring_interval" "$RDS_MAIN"; then
      echo -e "  ${YELLOW}~${NC} RDS: monitoring_interval — needs IAM role (see template rds-hardening.tf)"
    fi
  fi

  # --- Fix: VPC default SG ---
  VPC_MAIN="modules/vpc/main.tf"
  if [[ -f "$VPC_MAIN" ]]; then
    if ! grep -q "aws_default_security_group" "$VPC_MAIN"; then
      cp "$VPC_MAIN" "${VPC_MAIN}.bak"
      cat >> "$VPC_MAIN" << 'VPCEOF'

# --- Default Security Group Lockdown (CKV2_AWS_12) ---

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-default-sg-restricted" }
}
VPCEOF
      echo -e "  ${GREEN}+${NC} VPC: default security group lockdown"
      ((FIXES_APPLIED++))
    fi
  fi

  # --- Fix: S3 lifecycle abort-incomplete-multipart ---
  for S3_FILE in modules/s3/main.tf modules/security/main.tf; do
    if [[ -f "$S3_FILE" ]] && ! grep -q "abort_incomplete_multipart_upload" "$S3_FILE"; then
      echo -e "  ${YELLOW}~${NC} S3: $S3_FILE needs abort_incomplete_multipart_upload rules (see template)"
    fi
  done

  # --- Fix: CloudWatch KMS ---
  for CW_FILE in modules/cloudwatch/main.tf modules/vpc/main.tf modules/security/main.tf; do
    if [[ -f "$CW_FILE" ]] && grep -q "aws_cloudwatch_log_group" "$CW_FILE"; then
      if ! grep -q "kms_key_id" "$CW_FILE" || grep -q 'aws_cloudwatch_log_group.*{' "$CW_FILE"; then
        NEEDS_KMS=$(grep -c "aws_cloudwatch_log_group" "$CW_FILE" 2>/dev/null || echo 0)
        HAS_KMS=$(grep -c "kms_key_id" "$CW_FILE" 2>/dev/null || echo 0)
        if [[ "$HAS_KMS" -lt "$NEEDS_KMS" ]]; then
          echo -e "  ${YELLOW}~${NC} CloudWatch: $CW_FILE has log groups without kms_key_id (see template)"
        fi
      fi
    fi
  done

  echo ""
  echo -e "${GREEN}Applied $FIXES_APPLIED direct fixes.${NC}"
  echo -e "${YELLOW}Review items marked with ~ require manual template application.${NC}"
  echo ""
  echo "Backups created with .bak extension. Restore with:"
  echo "  for bak in modules/*/*.bak; do cp \"\$bak\" \"\${bak%.bak}\"; done"
  echo ""
  echo "Next steps:"
  echo "  1. Apply remaining fixes from templates in 01-iac-templates/terraform-hardening/"
  echo "  2. terraform validate"
  echo "  3. checkov -d . --framework terraform"
  echo "  4. terraform plan -var-file=environments/staging/terraform.tfvars"
fi

echo -e "${BLUE}=== Done ===${NC}"
