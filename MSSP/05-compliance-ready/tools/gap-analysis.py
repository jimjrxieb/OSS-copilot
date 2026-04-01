#!/usr/bin/env python3
"""
gap-analysis.py
Read all scan outputs from an evidence folder and map to FedRAMP Moderate
control matrix. Outputs:
  - control-matrix.md     : MET / PARTIAL / MISSING per control
  - poam.md               : Pre-populated Plan of Action & Milestones
  - remediation-plan.md   : Severity-based remediation plan

Usage:
    python3 gap-analysis.py --client-name "Acme Corp" --scan-dir ./evidence/scan-reports
    python3 gap-analysis.py --client-name "Acme Corp" --scan-dir ./evidence/scan-reports --output-dir ./evidence/gap-analysis
"""

import argparse
import json
import os
import sys
from datetime import datetime, date
from pathlib import Path
from collections import defaultdict


# ---------------------------------------------------------------------------
# FedRAMP Moderate control definitions
# Each control has:
#   - description: what it requires
#   - evidenced_by: list of scanners/tools that can confirm this control
#   - remediation: which template to apply
#   - fedramp_priority: HIGH / MEDIUM / LOW (our assessment for initial engagements)
# ---------------------------------------------------------------------------

CONTROLS = {
    # ── AC — Access Control ───────────────────────────────────────────────
    "AC-2":  {"family": "AC", "name": "Account Management",
              "description": "Manage system accounts (creation, activation, modification, disable, remove)",
              "evidenced_by": ["rbac_audit", "kube_bench"],
              "remediation": "04-remediation/rbac-templates.yaml",
              "fedramp_priority": "HIGH"},
    "AC-3":  {"family": "AC", "name": "Access Enforcement",
              "description": "Enforce approved authorizations for access to system resources",
              "evidenced_by": ["kyverno_nonroot", "kube_bench", "polaris"],
              "remediation": "04-remediation/rbac-templates.yaml",
              "fedramp_priority": "HIGH"},
    "AC-6":  {"family": "AC", "name": "Least Privilege",
              "description": "Employ least privilege — no more access than needed",
              "evidenced_by": ["kyverno_drop_caps", "kyverno_nonprivileged", "rbac_audit"],
              "remediation": "04-remediation/pod-security-context.yaml",
              "fedramp_priority": "HIGH"},
    "AC-17": {"family": "AC", "name": "Remote Access",
              "description": "Establish usage restrictions and implement controls for remote access",
              "evidenced_by": ["network_policy_check", "conftest"],
              "remediation": "04-remediation/network-policies.yaml",
              "fedramp_priority": "MEDIUM"},

    # ── AU — Audit and Accountability ─────────────────────────────────────
    "AU-2":  {"family": "AU", "name": "Event Logging",
              "description": "Identify events that the system must be capable of logging",
              "evidenced_by": ["falco", "kube_bench", "cluster_audit"],
              "remediation": "04-remediation/audit-logging.yaml",
              "fedramp_priority": "HIGH"},
    "AU-3":  {"family": "AU", "name": "Content of Audit Records",
              "description": "Ensure audit records contain sufficient information (who, what, when, where, outcome)",
              "evidenced_by": ["falco", "kube_bench"],
              "remediation": "04-remediation/audit-logging.yaml",
              "fedramp_priority": "HIGH"},
    "AU-9":  {"family": "AU", "name": "Protection of Audit Information",
              "description": "Protect audit information from unauthorized access, modification, deletion",
              "evidenced_by": ["rbac_audit", "kube_bench"],
              "remediation": "04-remediation/audit-logging.yaml",
              "fedramp_priority": "MEDIUM"},
    "AU-12": {"family": "AU", "name": "Audit Record Generation",
              "description": "Allow auditable events to be audited by the system components",
              "evidenced_by": ["falco"],
              "remediation": "04-remediation/audit-logging.yaml",
              "fedramp_priority": "HIGH"},

    # ── CM — Configuration Management ─────────────────────────────────────
    "CM-2":  {"family": "CM", "name": "Baseline Configuration",
              "description": "Establish and maintain baseline configurations of the system",
              "evidenced_by": ["kube_bench", "checkov", "polaris"],
              "remediation": "02-CLUSTER-HARDEN/04-remediation/pod-security-context.yaml",
              "fedramp_priority": "HIGH"},
    "CM-6":  {"family": "CM", "name": "Configuration Settings",
              "description": "Establish and document configuration settings reflecting security requirements",
              "evidenced_by": ["kube_bench", "checkov", "kyverno_resource_limits", "conftest"],
              "remediation": "02-CLUSTER-HARDEN/04-remediation/resource-management.yaml",
              "fedramp_priority": "HIGH"},
    "CM-7":  {"family": "CM", "name": "Least Functionality",
              "description": "Configure to provide only essential capabilities; prohibit or restrict functions",
              "evidenced_by": ["kyverno_nonprivileged", "conftest", "checkov"],
              "remediation": "04-remediation/pod-security-context.yaml",
              "fedramp_priority": "HIGH"},
    "CM-8":  {"family": "CM", "name": "System Component Inventory",
              "description": "Develop and document inventory of system components",
              "evidenced_by": ["trivy_sbom", "checkov"],
              "remediation": "ci-templates/container-scan.yml",
              "fedramp_priority": "MEDIUM"},

    # ── IA — Identification and Authentication ─────────────────────────────
    "IA-2":  {"family": "IA", "name": "Identification and Authentication (Org Users)",
              "description": "Uniquely identify and authenticate users; implement MFA",
              "evidenced_by": ["rbac_audit", "kube_bench"],
              "remediation": "04-remediation/rbac-templates.yaml",
              "fedramp_priority": "HIGH"},
    "IA-5":  {"family": "IA", "name": "Authenticator Management",
              "description": "Manage system authenticators (passwords, tokens, PKI certs)",
              "evidenced_by": ["gitleaks", "semgrep_secrets", "kube_bench"],
              "remediation": "04-remediation/pod-security-context.yaml",
              "fedramp_priority": "HIGH"},

    # ── IR — Incident Response ─────────────────────────────────────────────
    "IR-4":  {"family": "IR", "name": "Incident Handling",
              "description": "Implement incident handling capability including preparation, detection, analysis",
              "evidenced_by": ["kubescape", "falco"],
              "remediation": "03-RUNTIME-SECURITY/ENGAGEMENT-GUIDE.md",
              "fedramp_priority": "HIGH"},
    "IR-5":  {"family": "IR", "name": "Incident Monitoring",
              "description": "Track and document incidents",
              "evidenced_by": ["kubescape", "falco", "cluster_audit"],
              "remediation": "03-RUNTIME-SECURITY/ENGAGEMENT-GUIDE.md",
              "fedramp_priority": "MEDIUM"},

    # ── RA — Risk Assessment ───────────────────────────────────────────────
    "RA-2":  {"family": "RA", "name": "Security Categorization",
              "description": "Categorize information and the system in accordance with applicable federal laws",
              "evidenced_by": ["manual"],
              "remediation": "02-compliance-docs/ssp-skeleton.md",
              "fedramp_priority": "HIGH"},
    "RA-5":  {"family": "RA", "name": "Vulnerability Monitoring and Scanning",
              "description": "Monitor and scan for vulnerabilities; remediate based on risk",
              "evidenced_by": ["trivy", "semgrep", "kubescape"],
              "remediation": "ci-templates/container-scan.yml",
              "fedramp_priority": "HIGH"},

    # ── SA — System and Services Acquisition ──────────────────────────────
    "SA-10": {"family": "SA", "name": "Developer Config Management",
              "description": "Require developer to manage and control changes during development",
              "evidenced_by": ["gitleaks", "semgrep", "conftest"],
              "remediation": "ci-templates/fedramp-compliance.yml",
              "fedramp_priority": "HIGH"},
    "SA-11": {"family": "SA", "name": "Developer Testing and Evaluation",
              "description": "Require developer to create and implement security assessment plan",
              "evidenced_by": ["semgrep", "trivy", "conftest"],
              "remediation": "ci-templates/sast-analysis.yml",
              "fedramp_priority": "HIGH"},

    # ── SC — System and Communications Protection ─────────────────────────
    "SC-5":  {"family": "SC", "name": "Denial of Service Protection",
              "description": "Protect against or limit effects of denial of service attacks",
              "evidenced_by": ["kyverno_resource_limits", "polaris"],
              "remediation": "02-CLUSTER-HARDEN/04-remediation/resource-management.yaml",
              "fedramp_priority": "MEDIUM"},
    "SC-7":  {"family": "SC", "name": "Boundary Protection",
              "description": "Monitor and control communications at external and internal boundaries",
              "evidenced_by": ["network_policy_check", "conftest", "kube_bench"],
              "remediation": "04-remediation/network-policies.yaml",
              "fedramp_priority": "HIGH"},
    "SC-8":  {"family": "SC", "name": "Transmission Confidentiality and Integrity",
              "description": "Implement cryptographic mechanisms to prevent disclosure during transmission (mTLS)",
              "evidenced_by": ["checkov", "kube_bench", "conftest"],
              "remediation": "04-remediation/network-policies.yaml",
              "fedramp_priority": "HIGH"},
    "SC-28": {"family": "SC", "name": "Protection of Information at Rest",
              "description": "Implement cryptographic mechanisms to protect data at rest",
              "evidenced_by": ["checkov", "kube_bench"],
              "remediation": "04-remediation/pod-security-context.yaml",
              "fedramp_priority": "HIGH"},

    # ── SI — System and Information Integrity ─────────────────────────────
    "SI-2":  {"family": "SI", "name": "Flaw Remediation",
              "description": "Identify, report, and correct system flaws; install security-relevant updates",
              "evidenced_by": ["trivy", "semgrep"],
              "remediation": "ci-templates/container-scan.yml",
              "fedramp_priority": "HIGH"},
    "SI-3":  {"family": "SI", "name": "Malicious Code Protection",
              "description": "Implement malicious code protection mechanisms at system entry/exit points",
              "evidenced_by": ["trivy", "falco"],
              "remediation": "ci-templates/container-scan.yml",
              "fedramp_priority": "HIGH"},
    "SI-4":  {"family": "SI", "name": "System Monitoring",
              "description": "Monitor the system to detect attacks and indicators of potential attacks",
              "evidenced_by": ["falco", "kubescape"],
              "remediation": "03-RUNTIME-SECURITY/ENGAGEMENT-GUIDE.md",
              "fedramp_priority": "HIGH"},
}


# ---------------------------------------------------------------------------
# Evidenced-by detectors — inspect scan outputs to confirm each evidence tag
# ---------------------------------------------------------------------------

def detect_evidence(scan_dir: Path) -> dict:
    """
    Read scan outputs and return a set of confirmed evidence tags.
    Each tag corresponds to a key in CONTROLS[x]["evidenced_by"].
    """
    confirmed = set()

    # nist-mapping-report.json from scan-and-map.py
    nist_report = scan_dir / "nist-mapping-report.json"
    if nist_report.exists():
        try:
            data = json.loads(nist_report.read_text())
            findings = data.get("findings", [])
            by_control = data.get("summary", {}).get("by_control", {})
            # Code scanners ran
            # scanners_ran: tools that executed (even if 0 findings)
            ran = set(data.get("scanners_ran", []))
            scanners = {f.get("source", "") for f in findings}
            all_ran = scanners | ran
            if "trivy" in all_ran:     confirmed.add("trivy")
            if "semgrep" in all_ran:   confirmed.add("semgrep"); confirmed.add("semgrep_secrets")
            if "gitleaks" in all_ran:  confirmed.add("gitleaks")
            # If IA-5 findings found (secrets) via gitleaks/semgrep
            if "IA-5" in by_control:    confirmed.add("semgrep_secrets")
        except Exception:
            pass

    # checkov results
    checkov_file = scan_dir / "checkov-results.json"
    if checkov_file.exists() and checkov_file.stat().st_size > 100:
        confirmed.add("checkov")
        try:
            data = json.loads(checkov_file.read_text())
            # If results exist (even failures) checkov ran
            if data.get("results") or data.get("summary"):
                confirmed.add("checkov")
        except Exception:
            confirmed.add("checkov")

    # conftest manifests
    conftest_file = scan_dir / "conftest-manifests.txt"
    if conftest_file.exists() and conftest_file.stat().st_size > 10:
        confirmed.add("conftest")
        content = conftest_file.read_text()
        # Check if network policies were tested
        if "network" in content.lower() or "netpol" in content.lower():
            confirmed.add("network_policy_check")

    # conftest terraform
    conftest_tf = scan_dir / "conftest-terraform.txt"
    if conftest_tf.exists() and conftest_tf.stat().st_size > 10:
        confirmed.add("conftest")

    # cluster audit (run-cluster-audit.sh output)
    cluster_audit = scan_dir / "cluster-audit.md"
    if cluster_audit.exists() and cluster_audit.stat().st_size > 100:
        confirmed.add("cluster_audit")
        content = cluster_audit.read_text()
        if "kubescape" in content.lower():   confirmed.add("kubescape")
        if "kube-bench" in content.lower() or "cis" in content.lower(): confirmed.add("kube_bench")
        if "polaris" in content.lower():     confirmed.add("polaris")
        if "falco" in content.lower():      confirmed.add("falco")
        if "rbac" in content.lower():        confirmed.add("rbac_audit")
        if "networkpolicy" in content.lower() or "network policy" in content.lower():
            confirmed.add("network_policy_check")
        # Kyverno policy checks
        if "require-run-as-nonroot" in content or "nonroot" in content:
            confirmed.add("kyverno_nonroot")
        if "disallow-privileged" in content or "privileged" in content:
            confirmed.add("kyverno_nonprivileged")
        if "drop-all" in content or "capabilities" in content:
            confirmed.add("kyverno_drop_caps")
        if "resource-limits" in content or "resource limit" in content:
            confirmed.add("kyverno_resource_limits")

    # trivy image scan
    trivy_images = scan_dir / "trivy-images.json"
    if trivy_images.exists() and trivy_images.stat().st_size > 100:
        confirmed.add("trivy")
        confirmed.add("trivy_sbom")

    # Falco evidence (from cluster audit or dedicated falco check)
    # Falco findings may appear in cluster-audit.md or as separate output
    falco_file = scan_dir / "falco-status.json"
    if falco_file.exists() and falco_file.stat().st_size > 10:
        confirmed.add("falco")
    # Also check cluster audit for falco mentions
    if "falco" in confirmed:
        pass  # Already confirmed from cluster_audit parsing above

    return confirmed


def assess_control(control_id: str, control: dict, confirmed_evidence: set) -> str:
    """
    Return MET / PARTIAL / MISSING based on what evidence was found.
    - MET: at least one evidenced_by tag confirmed, and it's not "manual"
    - PARTIAL: some but not all evidenced_by confirmed
    - MISSING: no evidence found (or only "manual" required)
    """
    required = set(control["evidenced_by"])

    if required == {"manual"}:
        return "MANUAL"  # Requires human documentation, can't be scanner-confirmed

    confirmed_for_control = required & confirmed_evidence

    if not confirmed_for_control:
        return "MISSING"
    elif confirmed_for_control == required:
        return "MET"
    else:
        return "PARTIAL"


def load_findings_by_control(scan_dir: Path) -> dict:
    """Return a dict of control_id → list of finding summaries."""
    by_control = defaultdict(list)
    nist_report = scan_dir / "nist-mapping-report.json"
    if nist_report.exists():
        try:
            data = json.loads(nist_report.read_text())
            for f in data.get("findings", []):
                for ctrl in f.get("nist_controls", []):
                    by_control[ctrl].append({
                        "id": f.get("id", "?"),
                        "title": f.get("title", "")[:80],
                        "severity": f.get("severity", "?"),
                        "source": f.get("source", "?"),
                        "rank": f.get("iron_legion_rank", "D"),
                        "file": f.get("file", ""),
                    })
        except Exception:
            pass
    return by_control


def render_control_matrix(client_name: str, results: dict, findings_by_control: dict) -> str:
    """Render the full FedRAMP Moderate control matrix as markdown."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    met = sum(1 for s in results.values() if s == "MET")
    partial = sum(1 for s in results.values() if s == "PARTIAL")
    missing = sum(1 for s in results.values() if s == "MISSING")
    manual = sum(1 for s in results.values() if s == "MANUAL")
    total = len(results)
    coverage_pct = round((met + partial) / max(total - manual, 1) * 100, 1)

    lines = [
        f"# FedRAMP Moderate — Control Coverage Matrix",
        f"Client: **{client_name}**  |  Generated: {now}",
        "",
        "## Coverage Summary",
        "",
        f"| Status | Count | % |",
        f"|--------|-------|---|",
        f"| ✅ MET | {met} | — |",
        f"| ⚠️ PARTIAL | {partial} | — |",
        f"| ❌ MISSING | {missing} | — |",
        f"| 📋 MANUAL | {manual} | (requires documentation) |",
        f"| **Scanner coverage** | **{met + partial}/{total - manual}** | **{coverage_pct}%** |",
        "",
        "> **Note:** MET/PARTIAL/MISSING is based on scan evidence only.",
        "> MANUAL controls require SSP documentation — see `02-compliance-docs/ssp-skeleton.md`.",
        "",
        "---",
        "",
    ]

    # Group by family
    by_family = defaultdict(list)
    for ctrl_id, status in results.items():
        family = CONTROLS[ctrl_id]["family"]
        by_family[family].append((ctrl_id, status))

    STATUS_ICON = {"MET": "✅", "PARTIAL": "⚠️", "MISSING": "❌", "MANUAL": "📋"}

    for family in sorted(by_family.keys()):
        family_name = {
            "AC": "Access Control", "AU": "Audit & Accountability",
            "CM": "Configuration Management", "IA": "Identification & Authentication",
            "IR": "Incident Response", "RA": "Risk Assessment",
            "SA": "System & Services Acquisition", "SC": "System & Communications Protection",
            "SI": "System & Information Integrity",
        }.get(family, family)

        lines += [f"## {family} — {family_name}", ""]
        lines += ["| Control | Name | Status | Evidence | Remediation |",
                  "|---------|------|--------|----------|-------------|"]

        for ctrl_id, status in sorted(by_family[family]):
            ctrl = CONTROLS[ctrl_id]
            icon = STATUS_ICON.get(status, "?")
            evidence = ", ".join(f"`{e}`" for e in ctrl["evidenced_by"])
            remediation = f"`{ctrl['remediation']}`"
            findings_count = len(findings_by_control.get(ctrl_id, []))
            findings_note = f" ({findings_count} findings)" if findings_count > 0 else ""
            lines.append(f"| {ctrl_id} | {ctrl['name']} | {icon} {status}{findings_note} | {evidence} | {remediation} |")

        lines.append("")

    return "\n".join(lines)


def render_poam(client_name: str, results: dict, findings_by_control: dict) -> str:
    """Render a pre-populated POA&M for MISSING and PARTIAL controls."""
    now = datetime.now().strftime("%Y-%m-%d")
    missing_controls = [(k, v) for k, v in results.items() if v in ("MISSING", "PARTIAL")]
    missing_controls.sort(key=lambda x: (
        {"HIGH": 0, "MEDIUM": 1, "LOW": 2}.get(CONTROLS[x[0]].get("fedramp_priority", "MEDIUM"), 1),
        x[0]
    ))

    lines = [
        f"# Plan of Action & Milestones (POA&M)",
        f"Client: **{client_name}**  |  Date: {now}",
        "",
        "> Pre-populated from scan findings. Fill in milestones and assigned owner.",
        "> FedRAMP requires POA&M to be submitted with the security package.",
        "",
        f"**Open items: {len(missing_controls)}**",
        "",
        "---",
        "",
        "| # | Control | Name | Status | Priority | Findings | Remediation | Target Date | Owner |",
        "|---|---------|------|--------|----------|----------|-------------|-------------|-------|",
    ]

    for i, (ctrl_id, status) in enumerate(missing_controls, 1):
        ctrl = CONTROLS[ctrl_id]
        findings_count = len(findings_by_control.get(ctrl_id, []))
        priority = ctrl.get("fedramp_priority", "MEDIUM")
        remediation = ctrl["remediation"].split("/")[-1]
        lines.append(
            f"| {i} | {ctrl_id} | {ctrl['name']} | {status} | {priority} "
            f"| {findings_count} | `{remediation}` | TBD | TBD |"
        )

    lines += [
        "",
        "---",
        "",
        "## Top Priority Items (HIGH — fix first)",
        "",
    ]

    for ctrl_id, status in missing_controls:
        ctrl = CONTROLS[ctrl_id]
        if ctrl.get("fedramp_priority") != "HIGH":
            continue
        findings = findings_by_control.get(ctrl_id, [])
        lines += [
            f"### {ctrl_id} — {ctrl['name']} ({status})",
            "",
            f"**Requirement:** {ctrl['description']}",
            "",
            f"**Remediation:** `{ctrl['remediation']}`",
            "",
        ]
        if findings:
            lines += ["**Findings driving this gap:**", ""]
            for f in findings[:5]:
                lines.append(f"- `{f['id']}` — {f['title']} (severity: {f['severity']}, rank: {f['rank']})")
            lines.append("")
        lines += [
            "**Milestone:** ___________________",
            "**Owner:** ___________________",
            "**Target Date:** ___________________",
            "",
        ]

    return "\n".join(lines)


def render_remediation_plan(client_name: str, results: dict, findings_by_control: dict) -> str:
    """Render an ordered remediation plan by severity priority."""
    now = datetime.now().strftime("%Y-%m-%d")

    # Collect all findings with their control context
    all_findings = []
    seen = set()
    for ctrl_id, findings in findings_by_control.items():
        for f in findings:
            key = (f["id"], f["source"])
            if key not in seen:
                seen.add(key)
                all_findings.append({**f, "control": ctrl_id})

    # Sort: B/C first (human/JADE), then D/E (auto-fix)
    rank_order = {"B": 0, "C": 1, "D": 2, "E": 3, "S": 0}
    all_findings.sort(key=lambda x: (rank_order.get(x["rank"], 2), x["severity"]))

    lines = [
        f"# Remediation Plan",
        f"Client: **{client_name}**  |  Date: {now}",
        "",
        "> Work top to bottom. B/C priority first (human review needed), then D/E (auto-fixable).",
        "> E/D priority findings can be auto-remediated. C priority requires security review.",
        "> B priority requires human decision.",
        "",
        f"**Total findings to remediate: {len(all_findings)}**",
        "",
        "---",
        "",
    ]

    for rank, label, icon in [
        ("B", "Human Review Required", "🔴"),
        ("C", "Security Review Required", "🟠"),
        ("D", "Auto-remediate with Logging", "🟡"),
        ("E", "Auto-remediate, No Approval", "🟢"),
    ]:
        rank_findings = [f for f in all_findings if f.get("rank") == rank]
        if not rank_findings:
            continue

        lines += [
            f"## {icon} Priority {rank}: {label} ({len(rank_findings)} findings)",
            "",
            "| Finding | Title | Control | Scanner | File |",
            "|---------|-------|---------|---------|------|",
        ]
        for f in rank_findings:
            file_short = f.get("file", "")
            if file_short:
                file_short = "/" + "/".join(file_short.split("/")[-2:])
            ctrl = f.get("control", "?")
            remediaton_ref = CONTROLS.get(ctrl, {}).get("remediation", "")
            lines.append(
                f"| `{f['id'][:40]}` | {f['title'][:50]} | {ctrl} | {f['source']} | {file_short} |"
            )

        lines += [""]

        # Group by control for remediation steps
        by_ctrl = defaultdict(list)
        for f in rank_findings:
            by_ctrl[f.get("control", "?")].append(f)

        for ctrl_id, ctrl_findings in sorted(by_ctrl.items()):
            ctrl = CONTROLS.get(ctrl_id, {})
            if ctrl.get("remediation"):
                lines += [
                    f"**{ctrl_id} fix:** `cat {ctrl.get('remediation', '')}`",
                ]
        lines += [""]

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Map scan evidence to FedRAMP Moderate control matrix"
    )
    parser.add_argument("--client-name", required=True, help="Client name")
    parser.add_argument("--scan-dir", required=True, help="Directory containing scan output files")
    parser.add_argument("--output-dir", default=None, help="Output directory (default: <scan-dir>/../gap-analysis)")
    args = parser.parse_args()

    scan_dir = Path(args.scan_dir).resolve()
    if not scan_dir.exists():
        print(f"ERROR: scan-dir not found: {scan_dir}")
        sys.exit(1)

    output_dir = Path(args.output_dir).resolve() if args.output_dir else scan_dir.parent / "gap-analysis"
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nFedRAMP Gap Analysis — {args.client_name}")
    print(f"Scan inputs : {scan_dir}")
    print(f"Output      : {output_dir}")
    print()

    # Detect evidence
    print("Detecting evidence from scan outputs...")
    confirmed = detect_evidence(scan_dir)
    print(f"  Confirmed evidence tags: {', '.join(sorted(confirmed)) or '(none)'}")
    print()

    # Assess each control
    results = {}
    for ctrl_id, ctrl in CONTROLS.items():
        results[ctrl_id] = assess_control(ctrl_id, ctrl, confirmed)

    met = sum(1 for s in results.values() if s == "MET")
    partial = sum(1 for s in results.values() if s == "PARTIAL")
    missing = sum(1 for s in results.values() if s == "MISSING")
    manual = sum(1 for s in results.values() if s == "MANUAL")
    total = len(results)

    print(f"Control status:")
    print(f"  ✅ MET     : {met}")
    print(f"  ⚠️  PARTIAL : {partial}")
    print(f"  ❌ MISSING : {missing}")
    print(f"  📋 MANUAL  : {manual} (requires SSP documentation)")
    print(f"  Coverage   : {round((met + partial) / max(total - manual, 1) * 100, 1)}%")
    print()

    # Load findings by control
    findings_by_control = load_findings_by_control(scan_dir)

    # Write outputs
    matrix_path = output_dir / "control-matrix.md"
    matrix_path.write_text(render_control_matrix(args.client_name, results, findings_by_control))
    print(f"  ✓ {matrix_path}")

    poam_path = output_dir / "poam.md"
    poam_path.write_text(render_poam(args.client_name, results, findings_by_control))
    print(f"  ✓ {poam_path}")

    plan_path = output_dir / "remediation-plan.md"
    plan_path.write_text(render_remediation_plan(args.client_name, results, findings_by_control))
    print(f"  ✓ {plan_path}")

    print()
    print("Next:")
    print(f"  1. Open {matrix_path.name} — review MISSING controls")
    print(f"  2. Open {poam_path.name} — fill in owners + target dates")
    print(f"  3. Open {plan_path.name} — start remediating B/C rank first")
    print()


if __name__ == "__main__":
    main()
