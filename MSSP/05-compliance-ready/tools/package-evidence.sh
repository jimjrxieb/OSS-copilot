#!/usr/bin/env bash
# package-evidence.sh
# Bundle all compliance evidence into an auditor-ready archive.
#
# Enterprise equivalent: Drata evidence export ($20-100K), Vanta report builder ($15-80K).
# Those pull from 100+ integrations and manage freshness. This script bundles
# the technical evidence from GP-Copilot's scan pipeline into a structured archive.
#
# Usage:
#   bash package-evidence.sh --evidence-dir evidence-20260327/ --client "NovaSec Cloud"
#   bash package-evidence.sh --evidence-dir evidence-*/ --client "NovaSec Cloud" --include-ssp
#   bash package-evidence.sh --evidence-dir evidence-*/ --client "NovaSec Cloud" --s3-upload s3://bucket/evidence/
#
# What it packages:
#   1. Scan reports (Trivy, Semgrep, Gitleaks, Checkov, Kubescape, Prowler)
#   2. NIST control mapping (scan-and-map.py output)
#   3. Control matrix (gap-analysis.py output)
#   4. POA&M (pre-populated from findings)
#   5. Remediation plan (priority-sorted)
#   6. SSP sections (if --include-ssp)
#   7. Cluster state snapshot (if cluster evidence exists)
#   8. Manifest of all files with SHA256 checksums
#
# NIST 800-53: AU-9 (Protection of Audit Information), CA-2 (Security Assessments)
#
# Requires: tar, sha256sum, jq
# Optional: aws cli (for S3 upload)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

EVIDENCE_DIR=""
CLIENT=""
INCLUDE_SSP=false
S3_UPLOAD=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --client) CLIENT="$2"; shift 2 ;;
    --include-ssp) INCLUDE_SSP=true; shift ;;
    --s3-upload) S3_UPLOAD="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Package compliance evidence into auditor-ready archive.

Usage:
  bash package-evidence.sh --evidence-dir <dir> --client <name> [OPTIONS]

Options:
  --evidence-dir DIR    Directory with scan results (from run-fedramp-scan.sh)
  --client NAME         Client/system name (for archive naming)
  --include-ssp         Include SSP skeleton and control family docs
  --s3-upload S3_URI    Upload archive to S3 with Object Lock (AU-9)
  --output-dir DIR      Output directory for archive (default: current dir)

Archive contents:
  evidence-package-<client>-<date>/
  ├── MANIFEST.md              ← File list with SHA256 checksums
  ├── 01-scan-reports/         ← Raw scanner outputs (JSON)
  ├── 02-nist-mapping/         ← Findings → NIST control mapping
  ├── 03-control-matrix/       ← MET/PARTIAL/MISSING per control
  ├── 04-poam/                 ← Pre-populated Plan of Action & Milestones
  ├── 05-remediation-plan/     ← Priority-sorted action items
  ├── 06-ssp-sections/         ← SSP skeleton + control families (if --include-ssp)
  └── 07-cluster-state/        ← K8s cluster snapshot (if available)

S3 upload with Object Lock (AU-9 compliance):
  bash package-evidence.sh --evidence-dir evidence-*/ --client "NovaSec" \\
    --s3-upload s3://fedramp-evidence/novasec/

  Bucket must have Object Lock enabled:
    aws s3api put-object-lock-configuration --bucket fedramp-evidence \\
      --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"COMPLIANCE","Years":3}}}'
EOF
      exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
  esac
done

if [[ -z "$EVIDENCE_DIR" || -z "$CLIENT" ]]; then
  echo "Usage: bash package-evidence.sh --evidence-dir <dir> --client <name>"
  exit 1
fi

if [[ ! -d "$EVIDENCE_DIR" ]]; then
  echo -e "${RED}Evidence directory not found: $EVIDENCE_DIR${NC}"
  exit 1
fi

CLIENT_SLUG=$(echo "$CLIENT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
DATE=$(date +%Y%m%d)
PACKAGE_NAME="evidence-package-${CLIENT_SLUG}-${DATE}"

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="."
fi

PACKAGE_DIR="$OUTPUT_DIR/$PACKAGE_NAME"
mkdir -p "$PACKAGE_DIR"/{01-scan-reports,02-nist-mapping,03-control-matrix,04-poam,05-remediation-plan}

echo ""
echo -e "${BLUE}=== Ghost Protocol — Evidence Packaging ===${NC}"
echo "  Client   : $CLIENT"
echo "  Evidence : $EVIDENCE_DIR"
echo "  Package  : $PACKAGE_DIR"
echo ""

# ─── 1. Scan reports ─────────────────────────────────────────────────────────

echo -e "${BLUE}[1/7] Packaging scan reports...${NC}"
SCAN_COUNT=0

for ext in json jsonl csv; do
  for f in "$EVIDENCE_DIR"/scan-reports/*."$ext" "$EVIDENCE_DIR"/*."$ext" 2>/dev/null; do
    [[ -f "$f" ]] || continue
    cp "$f" "$PACKAGE_DIR/01-scan-reports/"
    SCAN_COUNT=$((SCAN_COUNT + 1))
  done
done

echo "  $SCAN_COUNT scan report(s) packaged"

# ─── 2. NIST mapping ─────────────────────────────────────────────────────────

echo -e "${BLUE}[2/7] Packaging NIST mapping...${NC}"

for f in "$EVIDENCE_DIR"/nist-mapping-report.json "$EVIDENCE_DIR"/scan-reports/nist-mapping-report.json 2>/dev/null; do
  [[ -f "$f" ]] && cp "$f" "$PACKAGE_DIR/02-nist-mapping/" && echo "  NIST mapping report copied"
done

# ─── 3. Control matrix ───────────────────────────────────────────────────────

echo -e "${BLUE}[3/7] Packaging control matrix...${NC}"

for f in "$EVIDENCE_DIR"/gap-analysis/control-matrix.md "$EVIDENCE_DIR"/control-matrix.md 2>/dev/null; do
  [[ -f "$f" ]] && cp "$f" "$PACKAGE_DIR/03-control-matrix/" && echo "  Control matrix copied"
done

# ─── 4. POA&M ────────────────────────────────────────────────────────────────

echo -e "${BLUE}[4/7] Packaging POA&M...${NC}"

for f in "$EVIDENCE_DIR"/gap-analysis/poam.md "$EVIDENCE_DIR"/poam.md 2>/dev/null; do
  [[ -f "$f" ]] && cp "$f" "$PACKAGE_DIR/04-poam/" && echo "  POA&M copied"
done

# ─── 5. Remediation plan ─────────────────────────────────────────────────────

echo -e "${BLUE}[5/7] Packaging remediation plan...${NC}"

for f in "$EVIDENCE_DIR"/gap-analysis/remediation-plan.md "$EVIDENCE_DIR"/remediation-plan.md 2>/dev/null; do
  [[ -f "$f" ]] && cp "$f" "$PACKAGE_DIR/05-remediation-plan/" && echo "  Remediation plan copied"
done

# ─── 6. SSP sections ─────────────────────────────────────────────────────────

if $INCLUDE_SSP; then
  echo -e "${BLUE}[6/7] Packaging SSP sections...${NC}"
  mkdir -p "$PACKAGE_DIR/06-ssp-sections/control-families"

  if [[ -d "$PKG_DIR/02-compliance-docs" ]]; then
    cp "$PKG_DIR/02-compliance-docs/ssp-skeleton.md" "$PACKAGE_DIR/06-ssp-sections/" 2>/dev/null || true
    cp "$PKG_DIR/02-compliance-docs/system-description.md" "$PACKAGE_DIR/06-ssp-sections/" 2>/dev/null || true
    cp "$PKG_DIR/02-compliance-docs/authorization-boundary.md" "$PACKAGE_DIR/06-ssp-sections/" 2>/dev/null || true
    cp "$PKG_DIR/02-compliance-docs/control-families/"*.md "$PACKAGE_DIR/06-ssp-sections/control-families/" 2>/dev/null || true
    echo "  SSP skeleton + $(ls "$PACKAGE_DIR/06-ssp-sections/control-families/" 2>/dev/null | wc -l) control families copied"
  else
    echo -e "  ${YELLOW}02-compliance-docs not found${NC}"
  fi
else
  echo -e "${YELLOW}[6/7] SSP sections skipped (use --include-ssp)${NC}"
fi

# ─── 7. Cluster state ────────────────────────────────────────────────────────

echo -e "${BLUE}[7/7] Packaging cluster state...${NC}"

for f in "$EVIDENCE_DIR"/cluster-audit.md "$EVIDENCE_DIR"/scan-reports/cluster-audit.md 2>/dev/null; do
  if [[ -f "$f" ]]; then
    mkdir -p "$PACKAGE_DIR/07-cluster-state"
    cp "$f" "$PACKAGE_DIR/07-cluster-state/"
    echo "  Cluster audit snapshot copied"
  fi
done

# ─── Generate MANIFEST.md ────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}Generating manifest with checksums...${NC}"

{
  echo "# Evidence Package Manifest"
  echo ""
  echo "**Client:** $CLIENT"
  echo "**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
  echo "**Package:** $PACKAGE_NAME"
  echo ""
  echo "## File Inventory"
  echo ""
  echo "| File | SHA256 | Size |"
  echo "|------|--------|------|"

  find "$PACKAGE_DIR" -type f -not -name "MANIFEST.md" | sort | while read -r f; do
    REL_PATH="${f#$PACKAGE_DIR/}"
    HASH=$(sha256sum "$f" | cut -d' ' -f1)
    SIZE=$(du -h "$f" | cut -f1)
    echo "| $REL_PATH | \`${HASH:0:16}...\` | $SIZE |"
  done

  echo ""
  echo "## Integrity Verification"
  echo ""
  echo '```bash'
  echo "# Verify all checksums"
  echo "cd $PACKAGE_NAME/"
  echo "sha256sum -c CHECKSUMS.txt"
  echo '```'
  echo ""
  echo "---"
  echo "*Generated by Ghost Protocol package-evidence.sh*"
} > "$PACKAGE_DIR/MANIFEST.md"

# Generate machine-readable checksums
find "$PACKAGE_DIR" -type f -not -name "CHECKSUMS.txt" -not -name "MANIFEST.md" | sort | while read -r f; do
  REL_PATH="${f#$PACKAGE_DIR/}"
  sha256sum "$f" | sed "s|$PACKAGE_DIR/||"
done > "$PACKAGE_DIR/CHECKSUMS.txt"

# ─── Create archive ──────────────────────────────────────────────────────────

ARCHIVE="$OUTPUT_DIR/${PACKAGE_NAME}.tar.gz"
tar -czf "$ARCHIVE" -C "$OUTPUT_DIR" "$PACKAGE_NAME"

ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
FILE_COUNT=$(find "$PACKAGE_DIR" -type f | wc -l)

echo ""
echo -e "${GREEN}=== Evidence Package Complete ===${NC}"
echo "  Archive : $ARCHIVE ($ARCHIVE_SIZE)"
echo "  Files   : $FILE_COUNT"
echo "  Client  : $CLIENT"
echo ""

# ─── S3 upload ────────────────────────────────────────────────────────────────

if [[ -n "$S3_UPLOAD" ]]; then
  echo -e "${BLUE}Uploading to S3...${NC}"

  if ! command -v aws &>/dev/null; then
    echo -e "${RED}aws cli not found — skipping S3 upload${NC}"
  else
    S3_PATH="${S3_UPLOAD%/}/${PACKAGE_NAME}.tar.gz"
    aws s3 cp "$ARCHIVE" "$S3_PATH"
    echo -e "${GREEN}Uploaded: $S3_PATH${NC}"

    echo ""
    echo -e "${YELLOW}For AU-9 compliance (immutable evidence), enable Object Lock on the bucket:${NC}"
    echo "  aws s3api put-object-lock-configuration --bucket <bucket> \\"
    echo "    --object-lock-configuration '{\"ObjectLockEnabled\":\"Enabled\",\"Rule\":{\"DefaultRetention\":{\"Mode\":\"COMPLIANCE\",\"Years\":3}}}'"
  fi
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review: tar -tzf $ARCHIVE"
echo "  2. Verify: cd $PACKAGE_NAME && sha256sum -c CHECKSUMS.txt"
echo "  3. Share with 3PAO via secure transfer (not email)"
echo "  4. Store in S3 with Object Lock for AU-9 compliance"
echo "  5. Re-package after remediation: run-fedramp-scan.sh → package-evidence.sh"
echo ""
