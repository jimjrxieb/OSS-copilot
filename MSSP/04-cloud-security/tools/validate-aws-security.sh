#!/usr/bin/env bash
# validate-aws-security.sh — Comprehensive AWS + EKS security posture audit.
# Runs all validation checks from Playbook 10 (Security Validation) as a single script.
# Produces a PASS/FAIL scorecard across network, IAM, encryption, EKS, and monitoring.
#
# Usage:
#   bash validate-aws-security.sh --cluster my-eks --region us-east-1
#   bash validate-aws-security.sh --cluster my-eks --region us-east-1 --output /tmp/audit.md
#   bash validate-aws-security.sh --skip-iam --skip-monitoring  (partial audit)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

EKS_CLUSTER=""
AWS_REGION="us-east-1"
OUTPUT_FILE=""
SKIP_NETWORK=false
SKIP_IAM=false
SKIP_ENCRYPTION=false
SKIP_EKS=false
SKIP_MONITORING=false

TOTAL=0
PASSED=0
WARNED=0
FAILED=0

usage() {
  cat <<EOF
Comprehensive AWS + EKS security posture audit.

Usage: bash validate-aws-security.sh --cluster NAME [OPTIONS]

Options:
  --cluster NAME       EKS cluster name (required)
  --region REGION       AWS region (default: us-east-1)
  --output FILE        Write markdown report to file
  --skip-network       Skip network/VPC checks
  --skip-iam           Skip IAM checks
  --skip-encryption    Skip encryption checks
  --skip-eks           Skip EKS-specific checks
  --skip-monitoring    Skip monitoring/logging checks
  -h, --help           Show this help

Examples:
  bash validate-aws-security.sh --cluster prod-eks --region us-east-1
  bash validate-aws-security.sh --cluster prod-eks --output /tmp/security-audit.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)         EKS_CLUSTER="$2"; shift 2 ;;
    --region)          AWS_REGION="$2"; shift 2 ;;
    --output)          OUTPUT_FILE="$2"; shift 2 ;;
    --skip-network)    SKIP_NETWORK=true; shift ;;
    --skip-iam)        SKIP_IAM=true; shift ;;
    --skip-encryption) SKIP_ENCRYPTION=true; shift ;;
    --skip-eks)        SKIP_EKS=true; shift ;;
    --skip-monitoring) SKIP_MONITORING=true; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) echo -e "${RED}Unknown: $1${NC}"; usage; exit 1 ;;
  esac
done

if [[ -z "$EKS_CLUSTER" ]]; then
  echo -e "${RED}ERROR: --cluster is required${NC}"
  usage
  exit 1
fi

# Verify AWS CLI
if ! command -v aws &>/dev/null; then
  echo -e "${RED}ERROR: aws CLI not installed${NC}"
  exit 1
fi

# Verify identity
CALLER=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "unknown")
if [[ "$CALLER" == "unknown" ]]; then
  echo -e "${RED}ERROR: AWS credentials not configured${NC}"
  exit 1
fi

check() {
  local label="$1"
  local result="$2"  # pass, fail, warn, skip
  local detail="${3:-}"
  TOTAL=$((TOTAL + 1))
  case "$result" in
    pass) PASSED=$((PASSED + 1)); echo -e "  ${GREEN}PASS${NC}: $label${detail:+ ($detail)}" ;;
    fail) FAILED=$((FAILED + 1)); echo -e "  ${RED}FAIL${NC}: $label${detail:+ ($detail)}" ;;
    warn) WARNED=$((WARNED + 1)); echo -e "  ${YELLOW}WARN${NC}: $label${detail:+ ($detail)}" ;;
    skip) echo -e "  ${YELLOW}SKIP${NC}: $label${detail:+ ($detail)}" ;;
  esac
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  AWS Security Posture Audit                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo "  Cluster:  $EKS_CLUSTER"
echo "  Region:   $AWS_REGION"
echo "  Identity: $CALLER"
echo "  Date:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ── NETWORK SECURITY ────────────────────────────────────────────────────────
if [[ "$SKIP_NETWORK" == "false" ]]; then
  echo -e "${BLUE}── Network Security ──${NC}"

  # Open security groups (0.0.0.0/0)
  OPEN_SGS=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --query "SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]].GroupId" \
    --output text 2>/dev/null | wc -w || echo "0")
  if [[ "$OPEN_SGS" -eq 0 ]]; then
    check "No SGs open to 0.0.0.0/0" "pass"
  else
    check "SGs open to 0.0.0.0/0" "warn" "$OPEN_SGS found — verify they are ALB-only"
  fi

  # VPC Flow Logs
  VPC_ID=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null || echo "")
  if [[ -n "$VPC_ID" ]]; then
    FLOW_LOGS=$(aws ec2 describe-flow-logs --region "$AWS_REGION" \
      --filter "Name=resource-id,Values=$VPC_ID" \
      --query "FlowLogs[?FlowLogStatus=='ACTIVE']" --output text 2>/dev/null | wc -l || echo "0")
    if [[ "$FLOW_LOGS" -gt 0 ]]; then
      check "VPC Flow Logs enabled" "pass" "VPC $VPC_ID"
    else
      check "VPC Flow Logs enabled" "fail" "VPC $VPC_ID has no active flow logs"
    fi
  fi

  # VPC Endpoints
  ENDPOINTS=$(aws ec2 describe-vpc-endpoints --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "VpcEndpoints[].ServiceName" --output text 2>/dev/null | wc -w || echo "0")
  if [[ "$ENDPOINTS" -gt 0 ]]; then
    check "VPC Endpoints configured" "pass" "$ENDPOINTS endpoint(s)"
  else
    check "VPC Endpoints configured" "warn" "No endpoints — S3/DynamoDB traffic goes via NAT"
  fi

  # IMDSv2
  IMDSV1_INSTANCES=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --query "Reservations[].Instances[?MetadataOptions.HttpTokens!='required'].InstanceId" \
    --output text 2>/dev/null | wc -w || echo "0")
  if [[ "$IMDSV1_INSTANCES" -eq 0 ]]; then
    check "IMDSv2 enforced (HttpTokens=required)" "pass"
  else
    check "IMDSv2 enforced" "fail" "$IMDSV1_INSTANCES instance(s) still allow IMDSv1"
  fi
  echo ""
fi

# ── IAM SECURITY ─────────────────────────────────────────────────────────────
if [[ "$SKIP_IAM" == "false" ]]; then
  echo -e "${BLUE}── IAM Security ──${NC}"

  # Root MFA
  ROOT_MFA=$(aws iam get-account-summary --query "SummaryMap.AccountMFAEnabled" --output text 2>/dev/null || echo "0")
  if [[ "$ROOT_MFA" -eq 1 ]]; then
    check "Root account MFA enabled" "pass"
  else
    check "Root account MFA enabled" "fail" "CRITICAL — enable immediately"
  fi

  # Access Analyzer
  ANALYZERS=$(aws accessanalyzer list-analyzers --region "$AWS_REGION" \
    --query "analyzers[?status=='ACTIVE']" --output text 2>/dev/null | wc -l || echo "0")
  if [[ "$ANALYZERS" -gt 0 ]]; then
    check "IAM Access Analyzer enabled" "pass"
  else
    check "IAM Access Analyzer enabled" "warn" "Enable for policy analysis"
  fi

  # Stale access keys (>90 days)
  STALE_KEYS=$(aws iam generate-credential-report 2>/dev/null && sleep 2 && \
    aws iam get-credential-report --query "Content" --output text 2>/dev/null | \
    base64 -d 2>/dev/null | \
    awk -F, 'NR>1 && $9=="true" && $10!="N/A" {print $10}' | \
    while read -r date; do
      if [[ -n "$date" ]]; then
        AGE=$(( ($(date +%s) - $(date -d "$date" +%s 2>/dev/null || echo $(date +%s))) / 86400 ))
        [[ "$AGE" -gt 90 ]] && echo "stale"
      fi
    done | wc -l 2>/dev/null || echo "0")
  if [[ "$STALE_KEYS" -eq 0 ]]; then
    check "No stale access keys (>90 days)" "pass"
  else
    check "Stale access keys" "warn" "$STALE_KEYS key(s) older than 90 days"
  fi
  echo ""
fi

# ── ENCRYPTION ───────────────────────────────────────────────────────────────
if [[ "$SKIP_ENCRYPTION" == "false" ]]; then
  echo -e "${BLUE}── Encryption ──${NC}"

  # EBS default encryption
  EBS_DEFAULT=$(aws ec2 get-ebs-encryption-by-default --region "$AWS_REGION" \
    --query "EbsEncryptionByDefault" --output text 2>/dev/null || echo "false")
  if [[ "$EBS_DEFAULT" == "True" || "$EBS_DEFAULT" == "true" ]]; then
    check "EBS default encryption enabled" "pass"
  else
    check "EBS default encryption enabled" "fail" "Run: aws ec2 enable-ebs-encryption-by-default"
  fi

  # S3 public access block (account level)
  S3_BLOCK=$(aws s3control get-public-access-block --account-id "$(aws sts get-caller-identity --query Account --output text)" \
    --query "PublicAccessBlockConfiguration.BlockPublicAcls" --output text 2>/dev/null || echo "false")
  if [[ "$S3_BLOCK" == "True" || "$S3_BLOCK" == "true" ]]; then
    check "S3 account-level public access blocked" "pass"
  else
    check "S3 account-level public access blocked" "fail"
  fi

  # KMS key rotation
  KMS_KEYS=$(aws kms list-keys --region "$AWS_REGION" --query "Keys[].KeyId" --output text 2>/dev/null || echo "")
  ROTATION_OK=true
  for KEY in $KMS_KEYS; do
    MANAGED=$(aws kms describe-key --key-id "$KEY" --region "$AWS_REGION" \
      --query "KeyMetadata.KeyManager" --output text 2>/dev/null || echo "AWS")
    if [[ "$MANAGED" == "CUSTOMER" ]]; then
      ROTATION=$(aws kms get-key-rotation-status --key-id "$KEY" --region "$AWS_REGION" \
        --query "KeyRotationEnabled" --output text 2>/dev/null || echo "false")
      if [[ "$ROTATION" != "True" && "$ROTATION" != "true" ]]; then
        ROTATION_OK=false
      fi
    fi
  done
  if [[ "$ROTATION_OK" == "true" ]]; then
    check "KMS key rotation enabled" "pass"
  else
    check "KMS key rotation enabled" "warn" "Some customer-managed keys lack rotation"
  fi
  echo ""
fi

# ── EKS SECURITY ─────────────────────────────────────────────────────────────
if [[ "$SKIP_EKS" == "false" ]]; then
  echo -e "${BLUE}── EKS Security ──${NC}"

  # Private endpoint
  ENDPOINT_PUBLIC=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
    --query "cluster.resourcesVpcConfig.endpointPublicAccess" --output text 2>/dev/null || echo "unknown")
  if [[ "$ENDPOINT_PUBLIC" == "False" || "$ENDPOINT_PUBLIC" == "false" ]]; then
    check "EKS API endpoint private" "pass"
  elif [[ "$ENDPOINT_PUBLIC" == "unknown" ]]; then
    check "EKS API endpoint private" "skip" "Cannot query"
  else
    check "EKS API endpoint private" "fail" "Public access enabled"
  fi

  # Control plane logging
  LOG_TYPES=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
    --query "cluster.logging.clusterLogging[?enabled==\`true\`].types[]" --output text 2>/dev/null || echo "")
  LOG_COUNT=$(echo "$LOG_TYPES" | wc -w)
  if [[ "$LOG_COUNT" -ge 5 ]]; then
    check "All 5 EKS log types enabled" "pass"
  else
    check "EKS logging" "warn" "$LOG_COUNT/5 types enabled"
  fi

  # Envelope encryption
  ENCRYPTION=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
    --query "cluster.encryptionConfig[0].resources[0]" --output text 2>/dev/null || echo "None")
  if [[ "$ENCRYPTION" == "secrets" ]]; then
    check "EKS secrets envelope encryption" "pass"
  else
    check "EKS secrets envelope encryption" "fail"
  fi

  # OIDC provider
  OIDC=$(aws eks describe-cluster --name "$EKS_CLUSTER" --region "$AWS_REGION" \
    --query "cluster.identity.oidc.issuer" --output text 2>/dev/null || echo "None")
  if [[ "$OIDC" != "None" && -n "$OIDC" ]]; then
    check "OIDC provider configured (IRSA ready)" "pass"
  else
    check "OIDC provider configured" "fail" "Required for IRSA"
  fi

  # ECR scan on push
  ECR_REPOS=$(aws ecr describe-repositories --region "$AWS_REGION" \
    --query "repositories[?imageScanningConfiguration.scanOnPush==\`false\`].repositoryName" \
    --output text 2>/dev/null || echo "")
  if [[ -z "$ECR_REPOS" ]]; then
    check "ECR scanOnPush enabled" "pass"
  else
    check "ECR scanOnPush" "warn" "Disabled on: $ECR_REPOS"
  fi
  echo ""
fi

# ── MONITORING & LOGGING ────────────────────────────────────────────────────
if [[ "$SKIP_MONITORING" == "false" ]]; then
  echo -e "${BLUE}── Monitoring & Logging ──${NC}"

  # CloudTrail
  TRAILS=$(aws cloudtrail describe-trails --region "$AWS_REGION" \
    --query "trailList[?IsMultiRegionTrail==\`true\`].Name" --output text 2>/dev/null || echo "")
  if [[ -n "$TRAILS" ]]; then
    check "CloudTrail multi-region enabled" "pass"
  else
    check "CloudTrail multi-region" "fail" "No multi-region trail"
  fi

  # GuardDuty
  GD_DETECTORS=$(aws guardduty list-detectors --region "$AWS_REGION" \
    --query "DetectorIds" --output text 2>/dev/null || echo "")
  if [[ -n "$GD_DETECTORS" ]]; then
    check "GuardDuty enabled" "pass"
  else
    check "GuardDuty enabled" "fail"
  fi

  # Security Hub
  SH_STATUS=$(aws securityhub describe-hub --region "$AWS_REGION" \
    --query "HubArn" --output text 2>/dev/null || echo "")
  if [[ -n "$SH_STATUS" && "$SH_STATUS" != "None" ]]; then
    check "Security Hub enabled" "pass"
  else
    check "Security Hub enabled" "warn" "Enable for centralized findings"
  fi

  # AWS Config
  CONFIG_RECORDERS=$(aws configservice describe-configuration-recorders --region "$AWS_REGION" \
    --query "ConfigurationRecorders[].name" --output text 2>/dev/null || echo "")
  if [[ -n "$CONFIG_RECORDERS" ]]; then
    check "AWS Config recorder active" "pass"
  else
    check "AWS Config recorder" "warn" "Enable for compliance rules"
  fi

  # CloudWatch alarms
  ALARM_COUNT=$(aws cloudwatch describe-alarms --region "$AWS_REGION" \
    --query "MetricAlarms | length(@)" --output text 2>/dev/null || echo "0")
  if [[ "$ALARM_COUNT" -gt 0 ]]; then
    check "CloudWatch alarms configured" "pass" "$ALARM_COUNT alarm(s)"
  else
    check "CloudWatch alarms" "warn" "No alarms configured"
  fi
  echo ""
fi

# ── SUMMARY ──────────────────────────────────────────────────────────────────
echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
echo -e "  ${BOLD}Security Audit Summary${NC}"
echo -e "  Total checks: $TOTAL"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${YELLOW}Warned: $WARNED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo -e "  Score: $PASSED/$TOTAL ($(( TOTAL > 0 ? PASSED * 100 / TOTAL : 0 ))%)"
echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"

# Write markdown report if requested
if [[ -n "$OUTPUT_FILE" ]]; then
  cat > "$OUTPUT_FILE" <<EOF
# AWS Security Posture Audit

**Cluster:** $EKS_CLUSTER
**Region:** $AWS_REGION
**Identity:** $CALLER
**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Summary

| Metric | Count |
|--------|-------|
| Total checks | $TOTAL |
| Passed | $PASSED |
| Warned | $WARNED |
| Failed | $FAILED |
| **Score** | **$PASSED/$TOTAL ($(( TOTAL > 0 ? PASSED * 100 / TOTAL : 0 ))%)** |

---

*Generated by GP-Copilot validate-aws-security.sh*
EOF
  echo ""
  echo -e "  Report written to: ${GREEN}$OUTPUT_FILE${NC}"
fi

# Exit with failure if any critical checks failed
if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
