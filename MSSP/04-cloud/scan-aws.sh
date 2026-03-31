#!/usr/bin/env bash
set -euo pipefail

# scan-aws.sh — AWS security posture scan with Prowler
# Usage: ./scan-aws.sh [profile]
# Requires: AWS credentials configured

PROFILE="${1:-default}"
OUTPUT_DIR=".oss-copilot/cloud"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: AWS Security Posture Scan ==="
echo "Profile: $PROFILE"
echo "Output: $OUTPUT_DIR"
echo ""

# --- Verify AWS access ---
echo "[*] Verifying AWS credentials..."
if ! aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
    echo "[!] AWS credentials not configured or expired."
    echo "    Run: aws configure --profile $PROFILE"
    echo "    Or:  aws sso login --profile $PROFILE"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query "Account" --output text 2>/dev/null)
echo "    Account: $ACCOUNT_ID"
echo ""

# --- Prowler ---
if command -v prowler &>/dev/null; then
    echo "[*] Running Prowler (this takes 10-30 minutes for a full scan)..."
    echo "    Scanning critical services: IAM, S3, EC2, RDS, Lambda, CloudTrail"

    prowler aws \
        --profile "$PROFILE" \
        --output-formats json-ocsf \
        --output-directory "$OUTPUT_DIR" \
        --severity critical high \
        2>/dev/null || true

    echo "    Results: $OUTPUT_DIR/"
    echo ""

    # Quick summary
    if ls "$OUTPUT_DIR"/*.json 1>/dev/null 2>&1; then
        python3 -c "
import json, glob
files = glob.glob('$OUTPUT_DIR/*.json')
pass_count = 0
fail_count = 0
for f in files:
    try:
        with open(f) as fh:
            for line in fh:
                data = json.loads(line)
                status = data.get('status_code', data.get('status', ''))
                if status in ('PASS', 'pass'): pass_count += 1
                elif status in ('FAIL', 'fail'): fail_count += 1
    except: pass
print(f'    PASS: {pass_count}  FAIL: {fail_count}')
" 2>/dev/null || true
    fi
else
    echo "[!] Prowler not found. Install: pip install prowler"
    echo ""
    echo "    Running basic AWS checks with CLI instead..."
    echo ""

    # Fallback: basic checks with AWS CLI
    echo "[*] Checking S3 public access..."
    aws s3api list-buckets --profile "$PROFILE" --query "Buckets[].Name" --output text 2>/dev/null | tr '\t' '\n' | while read -r bucket; do
        PUBLIC=$(aws s3api get-public-access-block --bucket "$bucket" --profile "$PROFILE" 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
config = data.get('PublicAccessBlockConfiguration', {})
if not all(config.values()):
    print('PUBLIC-ACCESS-POSSIBLE')
" 2>/dev/null)
        if [ -n "$PUBLIC" ]; then
            echo "    [WARN] $bucket: public access block not fully enabled"
        fi
    done

    echo ""
    echo "[*] Checking CloudTrail..."
    TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --query "trailList[?IsMultiRegionTrail==\`true\`].Name" --output text 2>/dev/null)
    if [ -z "$TRAILS" ]; then
        echo "    [WARN] No multi-region CloudTrail found"
    else
        echo "    Multi-region trails: $TRAILS"
    fi

    echo ""
    echo "[*] Checking GuardDuty..."
    GD_DETECTORS=$(aws guardduty list-detectors --profile "$PROFILE" --query "DetectorIds" --output text 2>/dev/null)
    if [ -z "$GD_DETECTORS" ]; then
        echo "    [WARN] GuardDuty not enabled"
    else
        echo "    GuardDuty detectors: $GD_DETECTORS"
    fi
fi

echo ""
echo "=== AWS scan complete ==="
echo ""
echo "Next steps:"
echo "  1. Fix CRITICAL findings first (public S3, overprivileged IAM, disabled logging)"
echo "  2. Run ./scan-iac.sh to check Terraform for misconfigurations before they deploy"
echo ""
echo "Note: Prowler catches individual misconfigurations. Wiz connects them into"
echo "attack paths. If Prowler finds 50 issues, Wiz tells you which 3 are actually"
echo "exploitable together."
