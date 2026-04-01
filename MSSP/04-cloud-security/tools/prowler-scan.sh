#!/usr/bin/env bash
# prowler-scan.sh
# Run Prowler against AWS account with framework-specific profiles.
#
# Enterprise equivalent: Wiz CSPM ($100-400K), Prisma Cloud ($100-400K), Orca ($80-300K).
# Prowler runs 300+ checks covering the same CIS/NIST/PCI/HIPAA controls.
# Honest gap: no attack path analysis, no asset graph visualization.
#
# Usage:
#   bash prowler-scan.sh --profile cis
#   bash prowler-scan.sh --profile nist --output prowler-results/
#   bash prowler-scan.sh --profile all --region us-east-1
#   bash prowler-scan.sh --profile fedramp --security-hub
#
# Profiles: cis, nist, pci, hipaa, gdpr, fedramp, soc2, all
#
# Requires: prowler (pip install prowler), AWS CLI configured
# NIST 800-53: RA-5 (Vulnerability Scanning), CA-7 (Continuous Monitoring)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PROFILE="cis"
OUTPUT_DIR=""
REGION=""
SECURITY_HUB=false
SEVERITY="medium"
SERVICES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --security-hub) SECURITY_HUB=true; shift ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    --services) SERVICES="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Run Prowler AWS security assessment with framework-specific profiles.

Usage: bash prowler-scan.sh --profile <framework> [OPTIONS]

Profiles:
  cis        CIS AWS Foundations Benchmark v3.0 (default)
  nist       NIST 800-53 controls
  pci        PCI-DSS v3.2.1
  hipaa      HIPAA Security Rule
  gdpr       GDPR technical controls
  fedramp    FedRAMP Moderate baseline
  soc2       SOC 2 Type II controls
  all        All frameworks (comprehensive, slow)

Options:
  --output DIR        Output directory (default: prowler-$(date))
  --region REGION     AWS region (default: all configured regions)
  --security-hub      Send findings to AWS Security Hub
  --severity LEVEL    Minimum severity: low|medium|high|critical (default: medium)
  --services LIST     Comma-separated AWS services to scan (default: all)

Enterprise equivalent coverage:
  Wiz:          300+ checks → Prowler: 300+ checks (same CIS controls)
  Prisma Cloud: Multi-framework → Prowler: 7 frameworks built-in
  Orca:         Agentless → Prowler: API-based (no agents needed)

Gap: Prowler finds misconfigurations. Wiz correlates them into attack paths.
     For attack path analysis, recommend Wiz after Prowler baseline.

Examples:
  bash prowler-scan.sh --profile cis --output ~/reports/
  bash prowler-scan.sh --profile fedramp --security-hub --region us-east-1
  bash prowler-scan.sh --profile all --severity high
  bash prowler-scan.sh --profile nist --services "iam,s3,ec2,rds,kms"
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

# Check prerequisites
if ! command -v prowler &>/dev/null; then
  echo -e "${RED}ERROR: prowler not found.${NC}"
  echo "  Install: pip install prowler"
  echo "  Verify:  prowler --version"
  exit 1
fi

if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}ERROR: AWS credentials not configured.${NC}"
  echo "  Run: aws configure  OR  export AWS_PROFILE=<profile>"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ACCOUNT_ALIAS=$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text 2>/dev/null || echo "$ACCOUNT_ID")

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="prowler-${PROFILE}-$(date +%Y%m%d)"
fi
mkdir -p "$OUTPUT_DIR"

echo ""
echo -e "${BLUE}=== Ghost Protocol — Prowler AWS Security Assessment ===${NC}"
echo "  Account  : $ACCOUNT_ALIAS ($ACCOUNT_ID)"
echo "  Profile  : $PROFILE"
echo "  Severity : $SEVERITY+"
echo "  Region   : ${REGION:-all}"
echo "  Output   : $OUTPUT_DIR"
echo ""

# Build prowler command
PROWLER_CMD="prowler aws"

# Map profile to prowler compliance framework
case "$PROFILE" in
  cis)     PROWLER_CMD="$PROWLER_CMD --compliance cis_3.0_aws" ;;
  nist)    PROWLER_CMD="$PROWLER_CMD --compliance nist_800_53_revision_5_aws" ;;
  pci)     PROWLER_CMD="$PROWLER_CMD --compliance pci_3.2.1_aws" ;;
  hipaa)   PROWLER_CMD="$PROWLER_CMD --compliance hipaa_aws" ;;
  gdpr)    PROWLER_CMD="$PROWLER_CMD --compliance gdpr_aws" ;;
  fedramp) PROWLER_CMD="$PROWLER_CMD --compliance fedramp_moderate_revision_4_aws" ;;
  soc2)    PROWLER_CMD="$PROWLER_CMD --compliance soc2_aws" ;;
  all)     PROWLER_CMD="$PROWLER_CMD" ;;  # No filter = all checks
  *)       echo -e "${RED}Unknown profile: $PROFILE${NC}"; exit 1 ;;
esac

# Add common flags
PROWLER_CMD="$PROWLER_CMD --severity $SEVERITY"
PROWLER_CMD="$PROWLER_CMD --output-directory $OUTPUT_DIR"
PROWLER_CMD="$PROWLER_CMD --output-formats json-ocsf csv html"

if [[ -n "$REGION" ]]; then
  PROWLER_CMD="$PROWLER_CMD --region $REGION"
fi

if [[ -n "$SERVICES" ]]; then
  PROWLER_CMD="$PROWLER_CMD --services $SERVICES"
fi

if $SECURITY_HUB; then
  PROWLER_CMD="$PROWLER_CMD --security-hub"
  echo -e "${BLUE}Findings will be sent to AWS Security Hub${NC}"
fi

# Run prowler
echo -e "${BLUE}Running Prowler ($PROFILE framework)...${NC}"
echo "  Command: $PROWLER_CMD"
echo ""

eval "$PROWLER_CMD" || true

# Generate summary
echo ""
echo -e "${BLUE}=== Scan Complete ===${NC}"
echo "  Results: $OUTPUT_DIR"
echo ""

# Count findings if JSON output exists
JSON_FILE=$(find "$OUTPUT_DIR" -name "*.json" -type f | head -1)
if [[ -n "$JSON_FILE" ]] && command -v jq &>/dev/null; then
  TOTAL=$(jq -s 'length' "$JSON_FILE" 2>/dev/null || echo "unknown")
  CRITICAL=$(jq -s '[.[] | select(.severity == "critical")] | length' "$JSON_FILE" 2>/dev/null || echo "0")
  HIGH=$(jq -s '[.[] | select(.severity == "high")] | length' "$JSON_FILE" 2>/dev/null || echo "0")

  echo "  Total findings : $TOTAL"
  echo "  Critical       : $CRITICAL"
  echo "  High           : $HIGH"
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review HTML report: open $OUTPUT_DIR/*.html"
echo "  2. Fix critical findings first"
echo "  3. Map to NIST controls: python3 ../08-FEDRAMP-READY/tools/scan-and-map.py --scan-dir $OUTPUT_DIR"
echo "  4. Re-scan after fixes: bash prowler-scan.sh --profile $PROFILE --output prowler-rescan-$(date +%Y%m%d)"
if $SECURITY_HUB; then
  echo "  5. View in Security Hub: AWS Console → Security Hub → Findings"
fi
echo ""
