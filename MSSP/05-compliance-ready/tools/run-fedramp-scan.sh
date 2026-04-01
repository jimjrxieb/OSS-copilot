#!/usr/bin/env bash
# run-fedramp-scan.sh
# Orchestrate all FedRAMP compliance scans for a client engagement.
# Runs code scanning, K8s manifest checks, and live cluster audit.
# All findings land in one evidence folder, ready for gap-analysis.py.
#
# Usage:
#   bash run-fedramp-scan.sh --client-name "Acme Corp" --target-dir ~/slot-1/acme-app
#   bash run-fedramp-scan.sh --client-name "Acme Corp" --target-dir ~/slot-1/acme-app --cluster
#   bash run-fedramp-scan.sh --client-name "Acme Corp" --target-dir ~/slot-1/acme-app --dry-run

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
K8S_PKG="$HOME/linkops-industries/GP-copilot/GP-CONSULTING/02-CLUSTER-HARDEN"

CLIENT_NAME=""
TARGET_DIR=""
OUTPUT_DIR=""
SCAN_CLUSTER=false
DRY_RUN=false
DATE=$(date +%Y-%m-%d)

usage() {
  echo "Usage: $0 --client-name NAME --target-dir DIR [OPTIONS]"
  echo ""
  echo "Required:"
  echo "  --client-name NAME    Client or project name (for report header)"
  echo "  --target-dir DIR      Client repo / application directory"
  echo ""
  echo "Options:"
  echo "  --output-dir DIR      Evidence output directory (default: ./evidence-DATE/)"
  echo "  --cluster             Also run live cluster audit (requires kubectl)"
  echo "  --dry-run             Show what would run, don't execute"
  echo ""
  echo "Examples:"
  echo "  bash run-fedramp-scan.sh \\"
  echo "    --client-name 'NovaSec Cloud' \\"
  echo "    --target-dir ~/linkops-industries/GP-copilot/GP-PROJECTS/01-instance/slot-3/Anthra-FedRAMP"
  echo ""
  echo "  bash run-fedramp-scan.sh \\"
  echo "    --client-name 'NovaSec Cloud' \\"
  echo "    --target-dir ~/linkops-industries/GP-copilot/GP-PROJECTS/01-instance/slot-3/Anthra-FedRAMP \\"
  echo "    --cluster"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client-name) CLIENT_NAME="$2"; shift 2 ;;
    --target-dir)  TARGET_DIR="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --cluster)     SCAN_CLUSTER=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --help|-h)     usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

if [[ -z "$CLIENT_NAME" || -z "$TARGET_DIR" ]]; then
  echo -e "${RED}ERROR: --client-name and --target-dir are required${NC}"
  usage; exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo -e "${RED}ERROR: Target directory not found: $TARGET_DIR${NC}"
  exit 1
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-./evidence-${DATE}}"
mkdir -p "$OUTPUT_DIR/scan-reports"

PASS=0; WARN=0; FAIL_COUNT=0

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       FedRAMP Compliance Scan — $CLIENT_NAME${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo "  Target     : $TARGET_DIR"
echo "  Evidence   : $OUTPUT_DIR"
echo "  Cluster    : $SCAN_CLUSTER"
echo "  Dry run    : $DRY_RUN"
echo ""

run_scanner() {
  local name="$1"; local cmd="$2"; local outfile="$3"
  echo -e "  ${BLUE}▶${NC} $name"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "    ${YELLOW}[DRY RUN]${NC} $cmd"
    return 0
  fi
  if eval "$cmd" > "$outfile" 2>/dev/null; then
    local size=$(wc -c < "$outfile" 2>/dev/null | tr -d ' ')
    echo -e "    ${GREEN}✓${NC} → $outfile ($size bytes)"
    PASS=$((PASS+1))
  else
    local exit_code=$?
    local size=$(wc -c < "$outfile" 2>/dev/null | tr -d ' ' || echo "0")
    if [[ "$size" -gt 10 ]]; then
      # Non-zero exit with output is normal for scanners (findings exist)
      echo -e "    ${GREEN}✓${NC} → $outfile ($size bytes, exit $exit_code — findings present)"
      PASS=$((PASS+1))
    else
      echo -e "    ${YELLOW}⚠${NC} $name not installed or failed (skipping)"
      WARN=$((WARN+1))
    fi
  fi
}

# ── 1. Code scanning (scan-and-map.py) ────────────────────────────────────
echo -e "${BLUE}[1/5] Code Scanning${NC}"
echo "  trivy + semgrep + gitleaks → NIST 800-53 mapping"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "  ${YELLOW}[DRY RUN]${NC} python3 $SCRIPT_DIR/scan-and-map.py \\"
  echo "    --client-name '$CLIENT_NAME' \\"
  echo "    --target-dir '$TARGET_DIR' \\"
  echo "    --output-dir '$OUTPUT_DIR/scan-reports'"
else
  python3 "$SCRIPT_DIR/scan-and-map.py" \
    --client-name "$CLIENT_NAME" \
    --target-dir "$TARGET_DIR" \
    --output-dir "$OUTPUT_DIR/scan-reports" 2>&1 | sed 's/^/  /'
fi
echo ""

# ── 2. IaC scanning (checkov) ─────────────────────────────────────────────
echo -e "${BLUE}[2/5] IaC Scanning (Terraform / CloudFormation / K8s YAML)${NC}"
echo "  checkov → CM-6, CM-7, SC-7 coverage"
echo ""

run_scanner "checkov" \
  "checkov -d '$TARGET_DIR' \
    --framework terraform,cloudformation,kubernetes,dockerfile \
    --compact \
    --output json \
    --soft-fail" \
  "$OUTPUT_DIR/scan-reports/checkov-results.json"
echo ""

# ── 3. K8s manifest policy check (conftest) ───────────────────────────────
echo -e "${BLUE}[3/5] K8s Manifest Policy Check (conftest)${NC}"
echo "  fedramp-controls.rego + 02-CLUSTER-HARDEN conftest policies"
echo ""

# Find K8s manifests
K8S_DIRS=()
for dir in k8s kubernetes infrastructure manifests deploy; do
  [[ -d "$TARGET_DIR/$dir" ]] && K8S_DIRS+=("$TARGET_DIR/$dir")
done
[[ -d "$TARGET_DIR" ]] && K8S_DIRS+=("$TARGET_DIR")

if command -v conftest &>/dev/null; then
  for k8s_dir in "${K8S_DIRS[@]}"; do
    yaml_count=$(find "$k8s_dir" -maxdepth 3 -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$yaml_count" -gt 0 ]]; then
      echo -e "  ${BLUE}▶${NC} conftest on $k8s_dir ($yaml_count YAML files)"
      if [[ "$DRY_RUN" == "false" ]]; then
        conftest test "$k8s_dir" \
          --policy "$PKG_DIR/policies/conftest/" \
          --policy "$K8S_PKG/policy-templates/conftest/" \
          --all-namespaces \
          --output stdout 2>/dev/null \
          > "$OUTPUT_DIR/scan-reports/conftest-manifests.txt" || true
        size=$(wc -c < "$OUTPUT_DIR/scan-reports/conftest-manifests.txt" | tr -d ' ')
        echo -e "    ${GREEN}✓${NC} → $OUTPUT_DIR/scan-reports/conftest-manifests.txt ($size bytes)"
        PASS=$((PASS+1))
      else
        echo -e "    ${YELLOW}[DRY RUN]${NC} conftest test $k8s_dir"
      fi
      break  # scan first K8s dir found
    fi
  done
else
  echo -e "  ${YELLOW}⚠${NC} conftest not installed — install: brew install conftest"
  WARN=$((WARN+1))
fi

# Terraform IaC conftest
TF_COUNT=$(find "$TARGET_DIR" -name "*.tf" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$TF_COUNT" -gt 0 ]]; then
  echo ""
  echo -e "  ${BLUE}▶${NC} conftest on Terraform files ($TF_COUNT .tf files)"
  if [[ "$DRY_RUN" == "false" ]] && command -v conftest &>/dev/null; then
    conftest test "$TARGET_DIR"/*.tf \
      --policy "$K8S_PKG/policy-templates/terraform/" \
      --output stdout 2>/dev/null \
      >> "$OUTPUT_DIR/scan-reports/conftest-terraform.txt" || true
    echo -e "    ${GREEN}✓${NC} → $OUTPUT_DIR/scan-reports/conftest-terraform.txt"
    PASS=$((PASS+1))
  elif [[ "$DRY_RUN" == "true" ]]; then
    echo -e "    ${YELLOW}[DRY RUN]${NC} conftest test *.tf"
  fi
fi
echo ""

# ── 4. Container image scan ───────────────────────────────────────────────
echo -e "${BLUE}[4/5] Container Image Scan${NC}"
echo "  trivy image scan → RA-5, SI-2 (known CVEs in deployed images)"
echo ""

# Find images from K8s manifests (skip policy patterns with wildcards/quotes)
IMAGES=()
while IFS= read -r line; do
  img=$(echo "$line" | grep -oP '(?<=image:\s)[^\s]+' | head -1 || true)
  # Only accept real image refs: no wildcards, no negation, no quotes, starts with alphanum
  if [[ -n "$img" && "$img" != *"{{"* && "$img" != *"*"* && \
        "$img" != *"?"* && "$img" != '"'* && "$img" =~ ^[a-zA-Z0-9] ]]; then
    IMAGES+=("$img")
  fi
done < <(grep -r "image:" "$TARGET_DIR" --include="*.yaml" --include="*.yml" 2>/dev/null | head -20 || true)

if [[ ${#IMAGES[@]} -gt 0 ]]; then
  echo "  Found images in manifests:"
  UNIQUE_IMAGES=($(printf '%s\n' "${IMAGES[@]}" | sort -u | head -5))
  for img in "${UNIQUE_IMAGES[@]}"; do
    echo "    - $img"
  done
  echo ""

  if command -v trivy &>/dev/null; then
    IMG_REPORT="$OUTPUT_DIR/scan-reports/trivy-images.json"
    # Scan first unique image as representative
    FIRST_IMG="${UNIQUE_IMAGES[0]}"
    run_scanner "trivy image $FIRST_IMG" \
      "trivy image --format json --config '$PKG_DIR/01-scanning-configs/trivy-fedramp.yaml' '$FIRST_IMG'" \
      "$IMG_REPORT"
  else
    echo -e "  ${YELLOW}⚠${NC} trivy not installed for image scan"
    WARN=$((WARN+1))
  fi
else
  echo -e "  ${YELLOW}⚠${NC} No container images found in manifests — skipping image scan"
  echo "  To scan manually: trivy image <image:tag> --config $PKG_DIR/01-scanning-configs/trivy-fedramp.yaml"
fi
echo ""

# ── 5. Live cluster audit ──────────────────────────────────────────────────
if [[ "$SCAN_CLUSTER" == "true" ]]; then
  echo -e "${BLUE}[5/5] Live Cluster Audit${NC}"
  echo "  kubescape + kube-bench + polaris + RBAC audit"
  echo ""

  if [[ -x "$K8S_PKG/tools/run-cluster-audit.sh" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo -e "  ${YELLOW}[DRY RUN]${NC} bash $K8S_PKG/tools/run-cluster-audit.sh \\"
      echo "    --output $OUTPUT_DIR/scan-reports/cluster-audit.md"
    else
      bash "$K8S_PKG/tools/run-cluster-audit.sh" \
        --output "$OUTPUT_DIR/scan-reports/cluster-audit.md" 2>&1 | sed 's/^/  /'
      PASS=$((PASS+1))
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} run-cluster-audit.sh not found at $K8S_PKG/tools/"
    WARN=$((WARN+1))
  fi

  # Check Falco deployment status
  echo ""
  echo -e "  ${BLUE}▶${NC} Checking Falco deployment..."
  if [[ "$DRY_RUN" == "false" ]] && command -v kubectl &>/dev/null; then
    FALCO_STATUS="{}"
    if kubectl get daemonset -A -o json 2>/dev/null | grep -q '"falco"'; then
      FALCO_PODS=$(kubectl get pods -A -l app.kubernetes.io/name=falco -o json 2>/dev/null || echo '{"items":[]}')
      FALCO_READY=$(echo "$FALCO_PODS" | jq '[.items[] | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")
      FALCO_TOTAL=$(echo "$FALCO_PODS" | jq '.items | length' 2>/dev/null || echo "0")
      FALCO_STATUS=$(jq -n \
        --arg status "deployed" \
        --arg ready "$FALCO_READY" \
        --arg total "$FALCO_TOTAL" \
        '{status: $status, pods_ready: $ready, pods_total: $total}')
      echo -e "    ${GREEN}✓${NC} Falco deployed ($FALCO_READY/$FALCO_TOTAL pods ready)"
      PASS=$((PASS+1))
    else
      FALCO_STATUS='{"status": "not_deployed"}'
      echo -e "    ${YELLOW}⚠${NC} Falco not found in cluster"
      WARN=$((WARN+1))
    fi
    echo "$FALCO_STATUS" > "$OUTPUT_DIR/scan-reports/falco-status.json"
  elif [[ "$DRY_RUN" == "true" ]]; then
    echo -e "    ${YELLOW}[DRY RUN]${NC} kubectl get daemonset -A | grep falco"
  fi
else
  echo -e "${BLUE}[5/5] Live Cluster Audit${NC}"
  echo -e "  ${YELLOW}⚠${NC} Skipped — add --cluster flag to include"
  echo "  Use: bash $0 ... --cluster"
fi
echo ""

# ── Generate gap analysis ──────────────────────────────────────────────────
echo -e "${BLUE}Running gap analysis...${NC}"
if [[ "$DRY_RUN" == "false" ]]; then
  python3 "$SCRIPT_DIR/gap-analysis.py" \
    --client-name "$CLIENT_NAME" \
    --scan-dir "$OUTPUT_DIR/scan-reports" \
    --output-dir "$OUTPUT_DIR/gap-analysis" 2>&1 | sed 's/^/  /'
else
  echo -e "  ${YELLOW}[DRY RUN]${NC} python3 $SCRIPT_DIR/gap-analysis.py \\"
  echo "    --client-name '$CLIENT_NAME' \\"
  echo "    --scan-dir '$OUTPUT_DIR/scan-reports' \\"
  echo "    --output-dir '$OUTPUT_DIR/gap-analysis'"
fi
echo ""

# ── Summary ────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo -e "  ${GREEN}PASS${NC}: $PASS   ${YELLOW}SKIP${NC}: $WARN   ${RED}FAIL${NC}: $FAIL_COUNT"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Evidence folder: $OUTPUT_DIR"
echo ""
echo "  $OUTPUT_DIR/scan-reports/         ← raw scanner output"
echo "  $OUTPUT_DIR/gap-analysis/         ← control matrix + POA&M + remediation plan"
echo ""
echo "Next:"
echo "  1. Review gap-analysis/control-matrix.md — find MISSING controls"
echo "  2. Work through gap-analysis/remediation-plan.md top to bottom"
echo "  3. Fill in 02-compliance-docs/ssp-skeleton.md with evidence paths"
echo "  4. Re-scan to close gaps: bash $0 --client-name '$CLIENT_NAME' --target-dir '$TARGET_DIR'"
echo ""
