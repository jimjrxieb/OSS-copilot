#!/usr/bin/env python3
"""
policy-coverage-report.py
Generate a compliance coverage matrix showing which controls are ENFORCED / AUDIT / MISSING.

Usage:
    python3 policy-coverage-report.py
    python3 policy-coverage-report.py --framework cis
    python3 policy-coverage-report.py --framework fedramp --format json --output report.json
"""

import argparse
import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PKG_DIR = SCRIPT_DIR.parent.parent
KYVERNO_DIR = PKG_DIR / "templates" / "policies" / "kyverno"
CONFTEST_DIR = PKG_DIR / "templates" / "policies" / "conftest"
GATEKEEPER_DIR = PKG_DIR / "templates" / "policies" / "gatekeeper"

# ---------------------------------------------------------------------------
# Control coverage definitions
# policy_name → None (YAML file present = AUDIT by default, Enforce if set)
# ---------------------------------------------------------------------------

POLICY_FILES = {
    "disallow-privileged":           KYVERNO_DIR / "disallow-privileged.yaml",
    "disallow-privilege-escalation": KYVERNO_DIR / "disallow-privilege-escalation.yaml",
    "disallow-host-namespaces":      KYVERNO_DIR / "disallow-host-namespaces.yaml",
    "disallow-latest-tag":           KYVERNO_DIR / "disallow-latest-tag.yaml",
    "require-run-as-nonroot":        KYVERNO_DIR / "require-run-as-nonroot.yaml",
    "require-resource-limits":       KYVERNO_DIR / "require-resource-limits.yaml",
    "require-readonly-rootfs":       KYVERNO_DIR / "require-readonly-rootfs.yaml",
    "require-drop-all-capabilities": KYVERNO_DIR / "require-drop-all-capabilities.yaml",
    "require-seccomp-strict":        KYVERNO_DIR / "require-seccomp-strict.yaml",
    "require-apparmor-profile":      KYVERNO_DIR / "require-apparmor-profile.yaml",
    "require-pss-labels":            KYVERNO_DIR / "require-pss-labels.yaml",
    "require-runtime-class-untrusted": KYVERNO_DIR / "require-runtime-class-untrusted.yaml",
    "require-semver-tags":           KYVERNO_DIR / "require-semver-tags.yaml",
    "cicd-security":                 CONFTEST_DIR / "cicd-security.rego",
    "image-security":                CONFTEST_DIR / "image-security.rego",
    "secrets-management":            CONFTEST_DIR / "secrets-management.rego",
    "prohibit-insecure-services":    CONFTEST_DIR / "03-prohibit-insecure-services.rego",
    "require-resource-limits-ci":    CONFTEST_DIR / "05-require-resource-limits.rego",
    "gatekeeper-nonroot":            GATEKEEPER_DIR / "constraint-templates.yaml",
    "gatekeeper-block-privileged":   GATEKEEPER_DIR / "constraint-templates.yaml",
}

def get_policy_status(policy_name: str) -> str:
    """Returns ENFORCED, AUDIT, or MISSING."""
    path = POLICY_FILES.get(policy_name)
    if path is None or not path.exists():
        return "MISSING"
    try:
        content = path.read_text()
        if "Enforce" in content:
            return "ENFORCED"
        return "AUDIT"
    except Exception:
        return "MISSING"

# ---------------------------------------------------------------------------
# Framework control mappings
# ---------------------------------------------------------------------------

FRAMEWORKS = {
    "cis": {
        "name": "CIS Kubernetes Benchmark v1.8",
        "controls": {
            "5.1.1 — Ensure image pull policy is set":             ["require-semver-tags", "disallow-latest-tag"],
            "5.2.1 — Do not admit privileged containers":          ["disallow-privileged", "gatekeeper-block-privileged"],
            "5.2.2 — Do not admit containers wishing to share host process ID": ["disallow-host-namespaces"],
            "5.2.3 — Do not admit containers wishing to share the host IPC": ["disallow-host-namespaces"],
            "5.2.4 — Do not admit containers wishing to share the host network": ["disallow-host-namespaces"],
            "5.2.5 — Do not admit containers with allowPrivilegeEscalation": ["disallow-privilege-escalation"],
            "5.2.6 — Do not admit root containers":                ["require-run-as-nonroot", "gatekeeper-nonroot"],
            "5.2.7 — Do not admit containers with dangerous capabilities": ["require-drop-all-capabilities"],
            "5.2.8 — Do not admit containers with added capabilities": ["require-drop-all-capabilities"],
            "5.2.9 — Do not admit containers with hostPath":       ["prohibit-insecure-services"],
            "5.2.10 — Do not admit containers that run as root":   ["require-run-as-nonroot"],
            "5.2.11 — Ensure containers use read-only root filesystem": ["require-readonly-rootfs"],
            "5.3.2 — Ensure all Namespaces have Network Policies": ["prohibit-insecure-services"],
            "5.7.2 — Ensure seccomp profiles are restricted":      ["require-seccomp-strict"],
            "5.7.4 — The default namespace should not be used":    ["require-pss-labels"],
        }
    },
    "nist": {
        "name": "NIST SP 800-53 Rev 5",
        "controls": {
            "AC-2 — Account Management":          ["require-run-as-nonroot", "gatekeeper-nonroot"],
            "AC-3 — Access Enforcement":          ["disallow-privileged", "disallow-privilege-escalation"],
            "AC-6 — Least Privilege":             ["require-drop-all-capabilities", "require-readonly-rootfs"],
            "CM-2 — Baseline Configuration":      ["require-resource-limits", "disallow-latest-tag"],
            "CM-6 — Configuration Settings":      ["require-seccomp-strict", "require-apparmor-profile"],
            "CM-7 — Least Functionality":         ["disallow-host-namespaces", "prohibit-insecure-services"],
            "SA-10 — Developer Configuration Mgmt": ["cicd-security", "image-security"],
            "SC-7 — Boundary Protection":         ["prohibit-insecure-services"],
            "SC-28 — Protection of Info at Rest": ["secrets-management"],
            "SI-2 — Flaw Remediation":            ["cicd-security"],
            "SI-4 — System Monitoring":           ["require-seccomp-strict"],
        }
    },
    "soc2": {
        "name": "SOC 2 Type II",
        "controls": {
            "CC6.1 — Logical Access Security":    ["disallow-privileged", "require-run-as-nonroot"],
            "CC6.2 — Prior to Issuing Credentials": ["require-run-as-nonroot"],
            "CC6.3 — Role-Based Access":          ["disallow-privilege-escalation"],
            "CC6.6 — Logical Access Restrictions": ["disallow-host-namespaces"],
            "CC6.7 — Restrict Transmission":      ["prohibit-insecure-services"],
            "CC6.8 — Prevent Unauthorized Software": ["disallow-latest-tag", "image-security"],
            "CC7.1 — Detect/Monitor Config Changes": ["require-seccomp-strict"],
            "CC7.2 — Monitor System Components":  ["cicd-security"],
        }
    },
    "pci-dss": {
        "name": "PCI-DSS v4.0",
        "controls": {
            "Req 1.2 — Network Access Controls":  ["prohibit-insecure-services"],
            "Req 2.2 — Configuration Standards":  ["disallow-privileged", "require-resource-limits"],
            "Req 2.2.1 — Prevent Privileged Access": ["disallow-privileged", "gatekeeper-block-privileged"],
            "Req 2.2.4 — No Root Containers":     ["require-run-as-nonroot", "gatekeeper-nonroot"],
            "Req 3.4 — Protect Stored Data":      ["secrets-management"],
            "Req 6.2 — Security Vulnerabilities": ["cicd-security", "require-semver-tags"],
            "Req 6.3 — Security Patching":        ["disallow-latest-tag", "image-security"],
            "Req 7.2 — Least Privilege":          ["require-drop-all-capabilities"],
            "Req 10.1 — Audit Logging":           ["cicd-security"],
        }
    },
    "fedramp": {
        "name": "FedRAMP Moderate",
        "controls": {
            "AC-2 — Account Mgmt":                ["require-run-as-nonroot"],
            "AC-6 — Least Privilege":             ["disallow-privileged", "require-drop-all-capabilities"],
            "CM-2 — Baseline Configuration":      ["require-resource-limits", "disallow-latest-tag"],
            "CM-6 — Configuration Settings":      ["require-seccomp-strict", "require-apparmor-profile"],
            "CM-7 — Least Functionality":         ["disallow-host-namespaces"],
            "SC-7 — Boundary Protection":         ["prohibit-insecure-services"],
            "SC-8 — Transmission Confidentiality": ["prohibit-insecure-services"],
            "SC-28 — Protection at Rest":         ["secrets-management"],
            "SI-2 — Flaw Remediation":            ["cicd-security"],
            "SI-4 — Monitoring":                  ["require-seccomp-strict"],
        }
    },
    "cks": {
        "name": "CKS Exam Domains",
        "controls": {
            "Cluster Setup (10%) — Network Policies":     ["prohibit-insecure-services"],
            "Cluster Setup (10%) — CIS Benchmark":        ["disallow-privileged", "require-run-as-nonroot"],
            "Cluster Hardening (15%) — RBAC":             ["disallow-privilege-escalation"],
            "Cluster Hardening (15%) — PSA Labels":       ["require-pss-labels"],
            "System Hardening (15%) — AppArmor":          ["require-apparmor-profile"],
            "System Hardening (15%) — Seccomp":           ["require-seccomp-strict"],
            "Microservice Vuln (20%) — Non-root":         ["require-run-as-nonroot", "gatekeeper-nonroot"],
            "Microservice Vuln (20%) — Sandboxing":       ["require-runtime-class-untrusted"],
            "Supply Chain (20%) — Image Signing":         ["image-security"],
            "Supply Chain (20%) — Scan/Verify":           ["cicd-security"],
            "Monitoring/Runtime (20%) — Falco/Audit":     ["require-seccomp-strict"],
            "Monitoring/Runtime (20%) — Container Immutability": ["require-readonly-rootfs"],
        }
    },
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

STATUS_COLORS = {
    "ENFORCED": "\033[0;32m",
    "AUDIT":    "\033[1;33m",
    "MISSING":  "\033[0;31m",
}
NC = "\033[0m"

def coverage_pct(controls: dict) -> float:
    statuses = []
    for policies in controls.values():
        best = "MISSING"
        for p in policies:
            s = get_policy_status(p)
            if s == "ENFORCED":
                best = "ENFORCED"
                break
            elif s == "AUDIT":
                best = "AUDIT"
        statuses.append(best)
    if not statuses:
        return 0.0
    covered = sum(1 for s in statuses if s != "MISSING")
    return round(covered / len(statuses) * 100, 1)

def render_markdown(frameworks: dict) -> str:
    lines = [
        "# Policy Compliance Coverage Report",
        f"Generated: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "",
        "## Coverage Summary",
        "",
        "| Framework | Coverage | Enforced | Audit | Missing |",
        "|-----------|----------|----------|-------|---------|",
    ]

    for key, fw in frameworks.items():
        controls = fw["controls"]
        statuses = []
        for policies in controls.values():
            best = "MISSING"
            for p in policies:
                s = get_policy_status(p)
                if s == "ENFORCED": best = "ENFORCED"; break
                elif s == "AUDIT": best = "AUDIT"
            statuses.append(best)
        enforced = statuses.count("ENFORCED")
        audit = statuses.count("AUDIT")
        missing = statuses.count("MISSING")
        pct = round((enforced + audit) / len(statuses) * 100, 1)
        lines.append(f"| {fw['name']} | {pct}% | {enforced} | {audit} | {missing} |")

    lines += [""]

    for key, fw in frameworks.items():
        lines += [f"---", "", f"## {fw['name']}", "",
                  "| Control | Policies | Status |",
                  "|---------|----------|--------|"]
        for control, policies in fw["controls"].items():
            best = "MISSING"
            for p in policies:
                s = get_policy_status(p)
                if s == "ENFORCED": best = "ENFORCED"; break
                elif s == "AUDIT": best = "AUDIT"
            policy_list = ", ".join(f"`{p}`" for p in policies)
            lines.append(f"| {control} | {policy_list} | **{best}** |")
        lines.append("")

    return "\n".join(lines)

def render_json(frameworks: dict) -> str:
    out = {}
    for key, fw in frameworks.items():
        controls = {}
        for control, policies in fw["controls"].items():
            best = "MISSING"
            for p in policies:
                s = get_policy_status(p)
                if s == "ENFORCED": best = "ENFORCED"; break
                elif s == "AUDIT": best = "AUDIT"
            controls[control] = {"policies": policies, "status": best}
        pct = coverage_pct(fw["controls"])
        out[key] = {"name": fw["name"], "coverage_pct": pct, "controls": controls}
    return json.dumps(out, indent=2)

def print_terminal(frameworks: dict):
    for key, fw in frameworks.items():
        pct = coverage_pct(fw["controls"])
        bar = "█" * int(pct / 5) + "░" * (20 - int(pct / 5))
        print(f"\n  {fw['name']}")
        print(f"  [{bar}] {pct}%")
        for control, policies in fw["controls"].items():
            best = "MISSING"
            for p in policies:
                s = get_policy_status(p)
                if s == "ENFORCED": best = "ENFORCED"; break
                elif s == "AUDIT": best = "AUDIT"
            color = STATUS_COLORS.get(best, "")
            print(f"    {color}{best:10}{NC}  {control}")

def main():
    parser = argparse.ArgumentParser(
        description="Generate compliance coverage matrix for 02-CLUSTER-HARDENING package"
    )
    parser.add_argument("--framework", default="all",
                        choices=list(FRAMEWORKS.keys()) + ["all"],
                        help="Compliance framework (default: all)")
    parser.add_argument("--format", default="markdown", choices=["markdown", "json"],
                        help="Output format (default: markdown)")
    parser.add_argument("--output", default=None,
                        help="Output file (default: print to stdout)")
    args = parser.parse_args()

    selected = FRAMEWORKS if args.framework == "all" else {args.framework: FRAMEWORKS[args.framework]}

    print(f"\n=== Ghost Protocol — Compliance Coverage Report ===")
    print_terminal(selected)
    print()

    if args.format == "markdown":
        content = render_markdown(selected)
    else:
        content = render_json(selected)

    if args.output:
        Path(args.output).write_text(content)
        print(f"Report written to: {args.output}")
    else:
        print(content)

if __name__ == "__main__":
    main()
