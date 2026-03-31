#!/usr/bin/env bash
set -euo pipefail

# map-nist.sh — Map security scan findings to NIST 800-53 controls
# Usage: ./map-nist.sh [scan-results-dir]
# Default: looks for .oss-copilot/ in current directory

RESULTS_DIR="${1:-.oss-copilot}"
OUTPUT_DIR=".oss-copilot/compliance"
mkdir -p "$OUTPUT_DIR"

echo "=== OSS-Copilot: NIST 800-53 Control Mapping ==="
echo "Results dir: $RESULTS_DIR"
echo "Output: $OUTPUT_DIR"
echo ""

# Generate the mapping
python3 - "$RESULTS_DIR" "$OUTPUT_DIR" << 'PYTHON'
import json
import glob
import sys
import os
from datetime import datetime

results_dir = sys.argv[1]
output_dir = sys.argv[2]

# NIST 800-53 control mapping for common finding types
CONTROL_MAP = {
    # Code security
    "sql-injection": ["SI-10", "SA-11"],
    "command-injection": ["SI-10", "SA-11"],
    "xss": ["SI-10", "SA-11"],
    "hardcoded-secret": ["IA-5", "SC-28"],
    "weak-crypto": ["SC-12", "SC-13"],
    "insecure-deserialization": ["SI-10", "SA-11"],

    # Container security
    "privileged-container": ["CM-6", "CM-7", "AC-6"],
    "root-container": ["CM-6", "AC-6"],
    "no-resource-limits": ["SC-6", "CM-6"],
    "no-health-check": ["SI-6", "CM-6"],
    "latest-tag": ["CM-2", "SA-10"],
    "cve-critical": ["SI-2", "RA-5"],
    "cve-high": ["SI-2", "RA-5"],

    # Cluster security
    "cis-fail": ["CM-6", "CM-7"],
    "rbac-wildcard": ["AC-6", "AC-3"],
    "cluster-admin": ["AC-6", "AC-2"],
    "no-network-policy": ["SC-7", "AC-4"],
    "no-psa": ["CM-6", "CM-7"],

    # Cloud security
    "public-s3": ["AC-3", "SC-7"],
    "no-encryption": ["SC-28", "SC-13"],
    "no-logging": ["AU-2", "AU-3", "AU-12"],
    "overprivileged-iam": ["AC-6", "AC-2"],
    "no-mfa": ["IA-2", "IA-5"],
}

# NIST control descriptions
CONTROL_NAMES = {
    "AC-2": "Account Management",
    "AC-3": "Access Enforcement",
    "AC-4": "Information Flow Enforcement",
    "AC-6": "Least Privilege",
    "AU-2": "Event Logging",
    "AU-3": "Content of Audit Records",
    "AU-12": "Audit Record Generation",
    "CM-2": "Baseline Configuration",
    "CM-6": "Configuration Settings",
    "CM-7": "Least Functionality",
    "IA-2": "Identification and Authentication",
    "IA-5": "Authenticator Management",
    "RA-5": "Vulnerability Monitoring and Scanning",
    "SA-10": "Developer Configuration Management",
    "SA-11": "Developer Testing and Evaluation",
    "SC-6": "Resource Availability",
    "SC-7": "Boundary Protection",
    "SC-12": "Cryptographic Key Establishment and Management",
    "SC-13": "Cryptographic Protection",
    "SC-28": "Protection of Information at Rest",
    "SI-2": "Flaw Remediation",
    "SI-6": "Security and Privacy Function Verification",
    "SI-10": "Information Input Validation",
}

# Scan for results
controls_found = {}
total_findings = 0

# Process Trivy results
for f in glob.glob(f"{results_dir}/**/trivy-*.json", recursive=True):
    try:
        data = json.load(open(f))
        for result in data.get("Results", []):
            for vuln in result.get("Vulnerabilities", []):
                sev = vuln.get("Severity", "UNKNOWN")
                key = f"cve-{sev.lower()}" if sev in ("CRITICAL", "HIGH") else None
                if key and key in CONTROL_MAP:
                    total_findings += 1
                    for ctrl in CONTROL_MAP[key]:
                        controls_found.setdefault(ctrl, []).append({
                            "source": "trivy",
                            "finding": vuln.get("VulnerabilityID", "unknown"),
                            "severity": sev,
                            "status": "FAIL"
                        })
    except Exception:
        pass

# Process Semgrep results
for f in glob.glob(f"{results_dir}/**/semgrep-*.json", recursive=True):
    try:
        data = json.load(open(f))
        for result in data.get("results", []):
            rule_id = result.get("check_id", "").lower()
            total_findings += 1
            for pattern, ctrls in CONTROL_MAP.items():
                if pattern.replace("-", "") in rule_id.replace("-", ""):
                    for ctrl in ctrls:
                        controls_found.setdefault(ctrl, []).append({
                            "source": "semgrep",
                            "finding": result.get("check_id", "unknown"),
                            "severity": result.get("extra", {}).get("severity", "UNKNOWN"),
                            "status": "FAIL"
                        })
    except Exception:
        pass

# Generate report
report = {
    "generated": datetime.now().isoformat(),
    "framework": "NIST 800-53 Rev 5",
    "total_findings_mapped": total_findings,
    "controls_affected": len(controls_found),
    "controls": {}
}

for ctrl_id, findings in sorted(controls_found.items()):
    report["controls"][ctrl_id] = {
        "name": CONTROL_NAMES.get(ctrl_id, "Unknown"),
        "status": "FAIL",
        "findings_count": len(findings),
        "findings": findings[:10]  # Cap at 10 per control
    }

# Add controls with no findings (PASS)
for ctrl_id, name in sorted(CONTROL_NAMES.items()):
    if ctrl_id not in report["controls"]:
        report["controls"][ctrl_id] = {
            "name": name,
            "status": "PASS (no findings)",
            "findings_count": 0,
            "findings": []
        }

# Write JSON
output_file = f"{output_dir}/nist-800-53-mapping.json"
with open(output_file, "w") as fh:
    json.dump(report, fh, indent=2)

# Write human-readable summary
summary_file = f"{output_dir}/nist-800-53-summary.txt"
with open(summary_file, "w") as fh:
    fh.write(f"NIST 800-53 Rev 5 — Control Mapping Summary\n")
    fh.write(f"Generated: {report['generated']}\n")
    fh.write(f"Total findings mapped: {report['total_findings_mapped']}\n")
    fh.write(f"Controls affected: {report['controls_affected']}\n")
    fh.write(f"\n{'='*60}\n\n")

    for ctrl_id, ctrl in sorted(report["controls"].items()):
        status = "FAIL" if ctrl["findings_count"] > 0 else "PASS"
        fh.write(f"[{status}] {ctrl_id} — {ctrl['name']}\n")
        if ctrl["findings_count"] > 0:
            fh.write(f"       {ctrl['findings_count']} finding(s)\n")
    fh.write(f"\n{'='*60}\n")

print(f"    Findings mapped: {total_findings}")
print(f"    Controls affected: {len(controls_found)}")
print(f"    JSON: {output_file}")
print(f"    Summary: {summary_file}")
PYTHON

echo ""
echo "=== NIST mapping complete ==="
echo ""
echo "This maps scanner findings to NIST 800-53 controls."
echo "For full compliance automation (continuous monitoring, auditor portal,"
echo "gap tracking across 1,400+ controls), you need Drata or Vanta."
