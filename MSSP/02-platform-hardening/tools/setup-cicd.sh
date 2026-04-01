#!/usr/bin/env bash
# setup-cicd.sh
# Copy conftest Rego policies into the client repo and wire a GitHub Actions check.
# Mirrors what the opa-package does in slot-3/Anthra-FedRAMP.
#
# Usage:
#   bash setup-cicd.sh --client-repo /path/to/client-repo
#   bash setup-cicd.sh --client-repo /path/to/client-repo --manifests-dir k8s/
#   bash setup-cicd.sh --client-repo /path/to/client-repo --dry-run

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

CLIENT_REPO=""
MANIFESTS_DIR="k8s"
DRY_RUN=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
CONFTEST_SRC="$PKG_DIR/01-policies/conftest"

usage() {
  echo "Usage: $0 --client-repo DIR [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --client-repo DIR    Path to client repo (required)"
  echo "  --manifests-dir DIR  Subdir containing K8s YAML (default: k8s/)"
  echo "  --dry-run            Show what would be copied, don't write"
  echo ""
  echo "What this does:"
  echo "  1. Copies conftest Rego policies → <client-repo>/policies/conftest/"
  echo "  2. Writes a GitHub Actions workflow → .github/workflows/policy-check.yml"
  echo "  3. Writes a local test script → scripts/test-policies.sh"
  echo ""
  echo "After running, client CI will reject non-compliant K8s manifests on every PR."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client-repo)   CLIENT_REPO="$2"; shift 2 ;;
    --manifests-dir) MANIFESTS_DIR="$2"; shift 2 ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --help|-h)       usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

if [[ -z "$CLIENT_REPO" ]]; then
  echo -e "${RED}ERROR: --client-repo is required${NC}"
  usage; exit 1
fi

if [[ ! -d "$CLIENT_REPO" ]]; then
  echo -e "${RED}ERROR: Client repo not found: $CLIENT_REPO${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}=== Ghost Protocol — Policy CI/CD Setup ===${NC}"
echo "  Client repo  : $CLIENT_REPO"
echo "  Manifests in : $MANIFESTS_DIR/"
echo "  Policies src : $CONFTEST_SRC"
echo "  Dry run      : $DRY_RUN"
echo ""

do_copy() {
  local src="$1" dst="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} would copy $(basename "$src") → $dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo -e "  ${GREEN}✓${NC} $(basename "$src") → $dst"
  fi
}

do_write() {
  local path="$1" content="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} would write $path"
  else
    mkdir -p "$(dirname "$path")"
    echo "$content" > "$path"
    echo -e "  ${GREEN}✓${NC} wrote $path"
  fi
}

# ── 1. Copy conftest Rego policies ─────────────────────────────────────────
echo -e "${BLUE}Step 1 — Copying conftest Rego policies${NC}"
POLICY_DEST="$CLIENT_REPO/policies/conftest"

for rego in "$CONFTEST_SRC"/*.rego; do
  [[ -f "$rego" ]] || continue
  do_copy "$rego" "$POLICY_DEST/$(basename "$rego")"
done

# Count copied
REGO_COUNT=$(ls "$CONFTEST_SRC"/*.rego 2>/dev/null | wc -l | tr -d ' ')
echo "  $REGO_COUNT policies → $POLICY_DEST/"
echo ""

# ── 2. GitHub Actions workflow ─────────────────────────────────────────────
echo -e "${BLUE}Step 2 — Writing GitHub Actions workflow${NC}"
GHA_PATH="$CLIENT_REPO/.github/workflows/policy-check.yml"

GHA_CONTENT="name: K8s Policy Check

on:
  pull_request:
    paths:
      - '${MANIFESTS_DIR}/**'
      - 'policies/conftest/**'

jobs:
  policy-check:
    name: Conftest Policy Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install conftest
        run: |
          VERSION=\$(curl -s https://api.github.com/repos/open-policy-agent/conftest/releases/latest | grep tag_name | cut -d '\"' -f4)
          curl -sLO https://github.com/open-policy-agent/conftest/releases/download/\${VERSION}/conftest_\${VERSION#v}_Linux_x86_64.tar.gz
          tar xzf conftest_*.tar.gz
          sudo mv conftest /usr/local/bin/

      - name: Test K8s manifests against policies
        run: |
          echo 'Testing manifests in ${MANIFESTS_DIR}/ against policies/conftest/'
          conftest test ${MANIFESTS_DIR}/ \\
            --policy policies/conftest/ \\
            --all-namespaces \\
            --output stdout
        # Exit 1 if any FAIL — blocks merge"

do_write "$GHA_PATH" "$GHA_CONTENT"
echo ""

# ── 3. Local test script ───────────────────────────────────────────────────
echo -e "${BLUE}Step 3 — Writing local test script${NC}"
TEST_SCRIPT_PATH="$CLIENT_REPO/scripts/test-policies.sh"

TEST_SCRIPT_CONTENT='#!/usr/bin/env bash
# Test K8s manifests against conftest policies.
# Run this locally before pushing — same check as CI.
#
# Usage:
#   bash scripts/test-policies.sh
#   bash scripts/test-policies.sh k8s/deployments/

set -euo pipefail
MANIFESTS="${1:-'"$MANIFESTS_DIR"'}"
POLICIES="policies/conftest"

if ! command -v conftest &>/dev/null; then
  echo "conftest not installed: https://www.conftest.dev/install/"
  exit 1
fi

echo "Testing $MANIFESTS/ against $POLICIES/"
conftest test "$MANIFESTS" --policy "$POLICIES" --all-namespaces --output stdout'

do_write "$TEST_SCRIPT_PATH" "$TEST_SCRIPT_CONTENT"
if [[ "$DRY_RUN" == "false" && -f "$TEST_SCRIPT_PATH" ]]; then
  chmod +x "$TEST_SCRIPT_PATH"
fi
echo ""

# ── Summary ────────────────────────────────────────────────────────────────
echo -e "${GREEN}=== Done ===${NC}"
echo ""
echo "What was set up:"
echo "  $POLICY_DEST/          ← $REGO_COUNT conftest Rego policies"
echo "  $GHA_PATH"
echo "  $TEST_SCRIPT_PATH"
echo ""
echo "Test it now:"
echo "  bash $CLIENT_REPO/scripts/test-policies.sh"
echo ""
echo "Next: deploy Kyverno to enforce in-cluster:"
echo "  bash $(dirname "$0")/../admission/deploy-policies.sh --engine kyverno --mode audit"
echo ""
