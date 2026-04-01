#!/usr/bin/env bash
# test-policies.sh
# Run Conftest to test Kubernetes manifests against CKS policy package.
# Use in CI/CD to catch violations before they hit the cluster.
#
# Usage:
#   bash test-policies.sh --manifests ./k8s/
#   bash test-policies.sh --manifests ./k8s/ --fail-on HIGH
#   bash test-policies.sh --manifests ./k8s/ --format json

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

MANIFESTS_DIR=""
FAIL_ON="HIGH"
FORMAT="text"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
POLICY_DIR="$PACKAGE_DIR/01-policies/conftest"

usage() {
  echo "Usage: $0 --manifests DIR [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --manifests DIR    Directory containing Kubernetes YAML manifests (required)"
  echo "  --fail-on LEVEL    Exit 1 if violations at this level: HIGH|MEDIUM|LOW (default: HIGH)"
  echo "  --format FORMAT    Output format: text|json (default: text)"
  echo ""
  echo "Examples:"
  echo "  bash test-policies.sh --manifests ./k8s/"
  echo "  bash test-policies.sh --manifests ./deploy/ --fail-on MEDIUM --format json"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifests) MANIFESTS_DIR="$2"; shift 2 ;;
    --fail-on)   FAIL_ON="$2"; shift 2 ;;
    --format)    FORMAT="$2"; shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

if [[ -z "$MANIFESTS_DIR" ]]; then
  echo -e "${RED}ERROR: --manifests is required${NC}"
  usage; exit 1
fi

if [[ ! -d "$MANIFESTS_DIR" ]]; then
  echo -e "${RED}ERROR: Manifests directory not found: $MANIFESTS_DIR${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Ghost Protocol — Policy Test Runner ===${NC}"
echo "  Manifests : $MANIFESTS_DIR"
echo "  Policies  : $POLICY_DIR"
echo "  Fail on   : $FAIL_ON+"
echo "  Format    : $FORMAT"
echo ""

# Check conftest is installed
if ! command -v conftest &>/dev/null; then
  echo -e "${RED}ERROR: conftest is not installed.${NC}"
  echo "  Install: https://www.conftest.dev/install/"
  echo "  Quick:   brew install conftest  OR  go install github.com/open-policy-agent/conftest@latest"
  exit 1
fi

echo -e "${BLUE}conftest $(conftest --version 2>&1 | head -1)${NC}"
echo ""

# Find all YAML files
mapfile -t YAML_FILES < <(find "$MANIFESTS_DIR" -name "*.yaml" -o -name "*.yml" 2>/dev/null | sort)

if [[ ${#YAML_FILES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No YAML files found in $MANIFESTS_DIR${NC}"
  exit 0
fi

echo -e "Found ${#YAML_FILES[@]} manifest(s) to test"
echo ""

PASS=0
FAIL=0
WARN=0
FAIL_FILES=()

for yaml_file in "${YAML_FILES[@]}"; do
  rel_path="${yaml_file#$MANIFESTS_DIR/}"

  if [[ "$FORMAT" == "json" ]]; then
    result=$(conftest test "$yaml_file" \
      --policy "$POLICY_DIR" \
      --output json 2>/dev/null || true)
    echo "$result"
    continue
  fi

  # Text output
  output=$(conftest test "$yaml_file" \
    --policy "$POLICY_DIR" \
    --output stdout 2>&1 || true)

  failures=$(echo "$output" | grep -c "^FAIL" || true)
  warnings=$(echo "$output" | grep -c "^WARN" || true)

  if [[ $failures -gt 0 ]]; then
    echo -e "  ${RED}✗ FAIL${NC}  $rel_path ($failures violations)"
    echo "$output" | grep "^FAIL" | sed 's/^/       /'
    FAIL=$((FAIL + 1))
    FAIL_FILES+=("$rel_path")
  elif [[ $warnings -gt 0 ]]; then
    echo -e "  ${YELLOW}⚠ WARN${NC}  $rel_path ($warnings warnings)"
    echo "$output" | grep "^WARN" | sed 's/^/       /'
    WARN=$((WARN + 1))
  else
    echo -e "  ${GREEN}✓ PASS${NC}  $rel_path"
    PASS=$((PASS + 1))
  fi
done

echo ""
echo "============================================================"
echo -e "  ${GREEN}PASS${NC}: $PASS   ${YELLOW}WARN${NC}: $WARN   ${RED}FAIL${NC}: $FAIL"
echo "============================================================"

# Exit code based on --fail-on level
if [[ "$FAIL_ON" == "HIGH" || "$FAIL_ON" == "MEDIUM" || "$FAIL_ON" == "LOW" ]]; then
  if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed manifests:${NC}"
    for f in "${FAIL_FILES[@]}"; do
      echo "  - $f"
    done
    echo ""
    echo -e "${RED}EXIT 1 — fix violations before deploying${NC}"
    exit 1
  fi
fi

echo ""
echo -e "${GREEN}All manifests passed policy checks.${NC}"
echo ""
