#!/usr/bin/env bash
set -euo pipefail

# package-evidence.sh — Package scan results into auditor-ready evidence
# Usage: ./package-evidence.sh [output-name]
# Collects all .oss-copilot/ results into a dated evidence package

PACKAGE_NAME="${1:-evidence}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
EVIDENCE_DIR=".oss-copilot"
OUTPUT_FILE="${PACKAGE_NAME}-${TIMESTAMP}.tar.gz"

echo "=== OSS-Copilot: Evidence Packaging ==="
echo "Timestamp: $TIMESTAMP"
echo "Output: $OUTPUT_FILE"
echo ""

if [ ! -d "$EVIDENCE_DIR" ]; then
    echo "[!] No scan results found. Run scans first:"
    echo "    cd 01-code && ./scan-code.sh /path/to/repo"
    echo "    cd 02-container && ./scan-images.sh"
    echo "    cd 03-cluster && ./scan-cis.sh"
    echo "    cd 04-cloud && ./scan-aws.sh"
    echo "    cd 05-compliance && ./map-nist.sh"
    exit 1
fi

# Generate manifest
MANIFEST="$EVIDENCE_DIR/MANIFEST.txt"
echo "OSS-Copilot Evidence Package" > "$MANIFEST"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$MANIFEST"
echo "Host: $(hostname)" >> "$MANIFEST"
echo "" >> "$MANIFEST"
echo "Contents:" >> "$MANIFEST"
echo "=========" >> "$MANIFEST"

# Inventory what we have
declare -A LAYER_NAMES=(
    ["code"]="01-Code (SAST, Secrets, Dependencies)"
    ["container"]="02-Container (Images, Dockerfile, Runtime)"
    ["cluster"]="03-Cluster (CIS, RBAC, Policies)"
    ["cloud"]="04-Cloud (AWS Posture, IaC)"
    ["compliance"]="05-Compliance (NIST Mapping)"
)

TOTAL_FILES=0
for layer in code container cluster cloud compliance; do
    LAYER_DIR="$EVIDENCE_DIR/$layer"
    if [ -d "$LAYER_DIR" ]; then
        FILE_COUNT=$(find "$LAYER_DIR" -type f | wc -l)
        TOTAL_FILES=$((TOTAL_FILES + FILE_COUNT))
        echo "" >> "$MANIFEST"
        echo "${LAYER_NAMES[$layer]}:" >> "$MANIFEST"
        find "$LAYER_DIR" -type f -printf "  %p (%s bytes, %TY-%Tm-%Td)\n" >> "$MANIFEST" 2>/dev/null || \
        find "$LAYER_DIR" -type f -exec ls -la {} \; >> "$MANIFEST" 2>/dev/null
        echo "  [+] ${LAYER_NAMES[$layer]}: $FILE_COUNT files"
    else
        echo "  [ ] ${LAYER_NAMES[$layer]}: not scanned"
    fi
done

echo "" >> "$MANIFEST"
echo "Total files: $TOTAL_FILES" >> "$MANIFEST"
echo ""

# Generate executive summary
SUMMARY="$EVIDENCE_DIR/EXECUTIVE-SUMMARY.txt"
cat > "$SUMMARY" << 'EOF'
SECURITY POSTURE ASSESSMENT — EXECUTIVE SUMMARY
=================================================

Methodology: OSS-Copilot (https://github.com/jimjrxieb/OSS-copilot)
Framework: 5 C's — Code, Container, Cluster, Cloud, Compliance

This evidence package contains scan results from open source security
tools covering five security domains. Each scan was run against the
target environment and results are provided in machine-readable (JSON)
and human-readable formats.

Tools Used:
-----------
EOF

# List tools based on what results we have
{
    [ -f "$EVIDENCE_DIR/code/semgrep-results.json" ] && echo "  - Semgrep (SAST)"
    [ -f "$EVIDENCE_DIR/code/bandit-results.json" ] && echo "  - Bandit (Python SAST)"
    [ -f "$EVIDENCE_DIR/code/gitleaks-results.json" ] && echo "  - Gitleaks (Secret Detection)"
    [ -f "$EVIDENCE_DIR/code/trivy-deps-results.json" ] && echo "  - Trivy (Dependency CVEs)"
    [ -f "$EVIDENCE_DIR/code/grype-results.json" ] && echo "  - Grype (Dependency CVEs)"
    [ -f "$EVIDENCE_DIR/container/hadolint-Dockerfile.json" ] && echo "  - Hadolint (Dockerfile Lint)"
    [ -f "$EVIDENCE_DIR/cluster/kube-bench-results.json" ] && echo "  - kube-bench (CIS Benchmark)"
    [ -f "$EVIDENCE_DIR/cluster/kubescape-cis-results.json" ] && echo "  - Kubescape (K8s Security)"
    [ -f "$EVIDENCE_DIR/cluster/polaris-results.json" ] && echo "  - Polaris (K8s Best Practices)"
    [ -f "$EVIDENCE_DIR/compliance/nist-800-53-mapping.json" ] && echo "  - NIST 800-53 Control Mapping"
} >> "$SUMMARY"

echo "" >> "$SUMMARY"
echo "For detailed findings, see individual scan results in each layer directory." >> "$SUMMARY"
echo "For NIST 800-53 control mapping, see compliance/nist-800-53-summary.txt." >> "$SUMMARY"

echo "[*] Generated executive summary"

# Package it
echo "[*] Creating evidence package..."
tar -czf "$OUTPUT_FILE" -C "$(dirname "$EVIDENCE_DIR")" "$(basename "$EVIDENCE_DIR")" 2>/dev/null

PACKAGE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
echo ""
echo "=== Evidence package complete ==="
echo ""
echo "Package: $OUTPUT_FILE ($PACKAGE_SIZE)"
echo "Files: $TOTAL_FILES scan result files"
echo "Manifest: $EVIDENCE_DIR/MANIFEST.txt"
echo "Summary: $EVIDENCE_DIR/EXECUTIVE-SUMMARY.txt"
echo ""
echo "Send this to your auditor. They'll have:"
echo "  - Machine-readable JSON for every scan"
echo "  - NIST 800-53 control mapping (if compliance scans were run)"
echo "  - Executive summary with tools and methodology"
echo ""
echo "For continuous monitoring and an auditor portal, you need Drata or Vanta."
echo "This package is a point-in-time snapshot — suitable for Type I audits"
echo "but not for Type II continuous monitoring requirements."
