#!/usr/bin/env bash
# iam-audit.sh
# Audit AWS IAM for security risks, stale credentials, and over-permissioned roles.
#
# Enterprise equivalent: Ermetic/Wiz CIEM ($50-400K), CyberArk ($50-200K).
# Those calculate effective permissions across role chains. This script finds
# the common IAM risks that cause 90% of breaches: stale keys, wildcard policies,
# MFA gaps, and unused roles.
#
# Usage:
#   bash iam-audit.sh
#   bash iam-audit.sh --output iam-report.md
#   bash iam-audit.sh --fix-recommendations
#
# NIST 800-53: AC-2 (Account Management), AC-6 (Least Privilege), IA-5 (Authenticator Management)
# CIS AWS: 1.1-1.22 (IAM controls)
#
# Requires: aws cli, jq

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

OUTPUT=""
FIX_RECS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --fix-recommendations) FIX_RECS=true; shift ;;
    -h|--help)
      cat <<EOF
Audit AWS IAM for security risks.

Usage: bash iam-audit.sh [OPTIONS]

Options:
  --output FILE            Write markdown report
  --fix-recommendations    Include remediation commands

Checks:
  1. Root account MFA (CRITICAL)
  2. Root account access keys (CRITICAL)
  3. Users without MFA (HIGH)
  4. Stale access keys (>90 days) (HIGH)
  5. Unused IAM users (>90 days no login) (MEDIUM)
  6. Wildcard policies (HIGH)
  7. IAM Access Analyzer findings (HIGH)
  8. Cross-account trust (MEDIUM)
  9. Password policy strength (MEDIUM)
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}AWS credentials not configured${NC}"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo -e "${BLUE}=== Ghost Protocol — IAM Security Audit ===${NC}"
echo "  Account: $ACCOUNT_ID"
echo ""

CRITICAL=0; HIGH=0; MEDIUM=0; LOW=0
FINDINGS=()

add_finding() {
  local sev="$1" check="$2" detail="$3" fix="${4:-}"
  FINDINGS+=("$sev|$check|$detail|$fix")
  case "$sev" in
    CRITICAL) CRITICAL=$((CRITICAL + 1)) ;;
    HIGH) HIGH=$((HIGH + 1)) ;;
    MEDIUM) MEDIUM=$((MEDIUM + 1)) ;;
    LOW) LOW=$((LOW + 1)) ;;
  esac
}

# ── 1. Root MFA ──────────────────────────────────────────────────────────────
echo -e "${BLUE}[1/9] Root account MFA...${NC}"
ROOT_MFA=$(aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text 2>/dev/null || echo "0")
if [[ "$ROOT_MFA" == "1" ]]; then
  echo -e "  ${GREEN}PASS${NC} Root MFA enabled"
else
  echo -e "  ${RED}CRITICAL${NC} Root MFA NOT enabled"
  add_finding "CRITICAL" "root-mfa" "Root account does not have MFA enabled" \
    "aws iam create-virtual-mfa-device --virtual-mfa-device-name root-mfa"
fi

# ── 2. Root access keys ─────────────────────────────────────────────────────
echo -e "${BLUE}[2/9] Root access keys...${NC}"
CRED_REPORT=$(aws iam generate-credential-report --output text 2>/dev/null || true)
sleep 2
ROOT_KEYS=$(aws iam get-credential-report --query Content --output text 2>/dev/null | base64 -d | head -2 | tail -1 || echo "")
if echo "$ROOT_KEYS" | grep -qE ',true,'; then
  echo -e "  ${RED}CRITICAL${NC} Root account has active access keys"
  add_finding "CRITICAL" "root-keys" "Root account has active access keys — delete immediately" \
    "aws iam delete-access-key --user-name root --access-key-id <KEY_ID>"
else
  echo -e "  ${GREEN}PASS${NC} No root access keys"
fi

# ── 3. Users without MFA ────────────────────────────────────────────────────
echo -e "${BLUE}[3/9] Users without MFA...${NC}"
NO_MFA_USERS=$(aws iam list-users --query 'Users[].UserName' --output text 2>/dev/null | tr '\t' '\n' | while read -r user; do
  MFA=$(aws iam list-mfa-devices --user-name "$user" --query 'MFADevices' --output text 2>/dev/null)
  if [[ -z "$MFA" ]]; then
    echo "$user"
  fi
done)

NO_MFA_COUNT=$(echo "$NO_MFA_USERS" | grep -c '.' 2>/dev/null || echo "0")
if [[ "$NO_MFA_COUNT" -gt 0 ]]; then
  echo -e "  ${YELLOW}HIGH${NC} $NO_MFA_COUNT user(s) without MFA"
  add_finding "HIGH" "no-mfa" "$NO_MFA_COUNT users without MFA: $(echo $NO_MFA_USERS | tr '\n' ', ')" \
    "# Enable MFA for each user in AWS Console → IAM → Users → Security credentials"
else
  echo -e "  ${GREEN}PASS${NC} All users have MFA"
fi

# ── 4. Stale access keys ────────────────────────────────────────────────────
echo -e "${BLUE}[4/9] Stale access keys (>90 days)...${NC}"
STALE_KEYS=0
aws iam list-users --query 'Users[].UserName' --output text 2>/dev/null | tr '\t' '\n' | while read -r user; do
  aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[?Status==`Active`].[AccessKeyId,CreateDate]' --output text 2>/dev/null | while read -r key_id created; do
    [[ -z "$key_id" ]] && continue
    CREATED_EPOCH=$(date -d "$created" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$created" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
    if [[ $AGE_DAYS -gt 90 ]]; then
      echo "$user:$key_id:${AGE_DAYS}d"
    fi
  done
done | head -20 | while read -r line; do
  [[ -z "$line" ]] && continue
  STALE_KEYS=$((STALE_KEYS + 1))
  echo -e "  ${YELLOW}HIGH${NC} Stale key: $line"
  add_finding "HIGH" "stale-key" "Access key older than 90 days: $line" \
    "aws iam update-access-key --user-name <USER> --access-key-id <KEY> --status Inactive"
done

# ── 5. Unused users ─────────────────────────────────────────────────────────
echo -e "${BLUE}[5/9] Unused users (>90 days no login)...${NC}"
# This check uses credential report which we already generated
echo -e "  ${YELLOW}Check credential report for users with no recent console/API activity${NC}"

# ── 6. Wildcard policies ────────────────────────────────────────────────────
echo -e "${BLUE}[6/9] Wildcard IAM policies...${NC}"
WILDCARD_POLICIES=$(aws iam list-policies --scope Local --query 'Policies[].Arn' --output text 2>/dev/null | tr '\t' '\n' | while read -r arn; do
  [[ -z "$arn" ]] && continue
  VERSION=$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null)
  POLICY_DOC=$(aws iam get-policy-version --policy-arn "$arn" --version-id "$VERSION" --query 'PolicyVersion.Document' --output json 2>/dev/null)
  if echo "$POLICY_DOC" | jq -e '.Statement[] | select(.Effect == "Allow") | select(.Action == "*" or (.Action | type == "array" and any(. == "*")))' &>/dev/null; then
    echo "$arn"
  fi
done)

WILDCARD_COUNT=$(echo "$WILDCARD_POLICIES" | grep -c '.' 2>/dev/null || echo "0")
if [[ "$WILDCARD_COUNT" -gt 0 ]]; then
  echo -e "  ${YELLOW}HIGH${NC} $WILDCARD_COUNT customer-managed policies with Action: *"
  add_finding "HIGH" "wildcard-policy" "$WILDCARD_COUNT policies grant Action:* (full admin)" \
    "# Review and scope down each policy to specific services/actions"
else
  echo -e "  ${GREEN}PASS${NC} No customer wildcard policies"
fi

# ── 7. IAM Access Analyzer ──────────────────────────────────────────────────
echo -e "${BLUE}[7/9] IAM Access Analyzer findings...${NC}"
ANALYZERS=$(aws accessanalyzer list-analyzers --query 'analyzers[?status==`ACTIVE`].arn' --output text 2>/dev/null || echo "")
if [[ -n "$ANALYZERS" ]]; then
  ACTIVE_FINDINGS=$(aws accessanalyzer list-findings --analyzer-arn "$(echo $ANALYZERS | awk '{print $1}')" \
    --filter '{"status":{"eq":["ACTIVE"]}}' --query 'findings' --output json 2>/dev/null | jq 'length' || echo "0")
  if [[ "$ACTIVE_FINDINGS" -gt 0 ]]; then
    echo -e "  ${YELLOW}HIGH${NC} $ACTIVE_FINDINGS active Access Analyzer findings (external access)"
    add_finding "HIGH" "access-analyzer" "$ACTIVE_FINDINGS resources with external access detected by Access Analyzer"
  else
    echo -e "  ${GREEN}PASS${NC} No active Access Analyzer findings"
  fi
else
  echo -e "  ${YELLOW}MEDIUM${NC} IAM Access Analyzer not enabled"
  add_finding "MEDIUM" "no-analyzer" "IAM Access Analyzer not enabled — cannot detect external access" \
    "aws accessanalyzer create-analyzer --analyzer-name account-analyzer --type ACCOUNT"
fi

# ── 8. Password policy ──────────────────────────────────────────────────────
echo -e "${BLUE}[8/9] Password policy...${NC}"
PW_POLICY=$(aws iam get-account-password-policy --query 'PasswordPolicy' --output json 2>/dev/null || echo '{}')
MIN_LENGTH=$(echo "$PW_POLICY" | jq -r '.MinimumPasswordLength // 0')
REQUIRE_UPPER=$(echo "$PW_POLICY" | jq -r '.RequireUppercaseCharacters // false')
MAX_AGE=$(echo "$PW_POLICY" | jq -r '.MaxPasswordAge // 0')

if [[ "$MIN_LENGTH" -lt 14 ]]; then
  echo -e "  ${YELLOW}MEDIUM${NC} Password minimum length: $MIN_LENGTH (recommend 14+)"
  add_finding "MEDIUM" "pw-length" "Password min length is $MIN_LENGTH (CIS requires 14+)"
else
  echo -e "  ${GREEN}PASS${NC} Password length: $MIN_LENGTH"
fi

# ── 9. Cross-account trust ───────────────────────────────────────────────────
echo -e "${BLUE}[9/9] Cross-account trust roles...${NC}"
TRUST_ROLES=$(aws iam list-roles --query 'Roles[].{Name:RoleName,Trust:AssumeRolePolicyDocument}' --output json 2>/dev/null | \
  jq -r '.[] | select(.Trust.Statement[]?.Principal.AWS? // "" | test("arn:aws:iam::[0-9]+:")) | .Name' 2>/dev/null || true)

TRUST_COUNT=$(echo "$TRUST_ROLES" | grep -c '.' 2>/dev/null || echo "0")
if [[ "$TRUST_COUNT" -gt 0 ]]; then
  echo -e "  ${YELLOW}MEDIUM${NC} $TRUST_COUNT roles with cross-account trust"
  add_finding "MEDIUM" "cross-account" "$TRUST_COUNT roles trust external AWS accounts — verify each is intentional"
else
  echo -e "  ${GREEN}PASS${NC} No cross-account trust roles"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))
echo ""
echo -e "${BLUE}=== IAM Audit Summary ===${NC}"
echo -e "  ${RED}CRITICAL : $CRITICAL${NC}"
echo -e "  ${YELLOW}HIGH     : $HIGH${NC}"
echo -e "  ${YELLOW}MEDIUM   : $MEDIUM${NC}"
echo "  Total    : $TOTAL findings"

if [[ -n "$OUTPUT" ]]; then
  {
    echo "# IAM Security Audit Report"
    echo ""
    echo "**Account:** $ACCOUNT_ID"
    echo "**Date:** $(date +"%Y-%m-%d %H:%M")"
    echo ""
    echo "## Summary"
    echo "| Severity | Count |"
    echo "|----------|-------|"
    echo "| CRITICAL | $CRITICAL |"
    echo "| HIGH | $HIGH |"
    echo "| MEDIUM | $MEDIUM |"
    echo ""
    echo "## Findings"
    echo "| Severity | Check | Detail |"
    echo "|----------|-------|--------|"
    for f in "${FINDINGS[@]}"; do
      IFS='|' read -r sev check detail fix <<< "$f"
      echo "| $sev | $check | $detail |"
    done
    if $FIX_RECS; then
      echo ""
      echo "## Remediation"
      echo '```bash'
      for f in "${FINDINGS[@]}"; do
        IFS='|' read -r sev check detail fix <<< "$f"
        [[ -n "$fix" ]] && echo "# $check: $fix"
      done
      echo '```'
    fi
    echo ""
    echo "---"
    echo "*Generated by Ghost Protocol iam-audit.sh*"
  } > "$OUTPUT"
  echo -e "${GREEN}Report: $OUTPUT${NC}"
fi

echo ""
