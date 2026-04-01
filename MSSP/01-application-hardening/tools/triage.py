#!/usr/bin/env python3
"""
triage.py
Read a run-all-scanners.sh output directory and generate REMEDIATION-PLAN.md
with the exact fixer command for every finding.

Usage:
    python3 triage.py --scan-dir GP-S3/consulting-reports/acme-corp-20260225
    python3 triage.py --scan-dir GP-S3/consulting-reports/acme-corp-20260225 --project acme-corp

Output:
    <scan-dir>/REMEDIATION-PLAN.md   ← grouped, prioritized, copy-paste commands
"""

import argparse
import csv
import json
import sys
from pathlib import Path
from datetime import datetime

# Resolve PKG_DIR (01-APP-SEC/) from tools/triage.py
PKG_DIR = Path(__file__).resolve().parent.parent
FIXERS_DIR = PKG_DIR / "02-fixers"
FIXERS_K8S = PKG_DIR / "02-fixers" / "k8s-manifests"

# ---------------------------------------------------------------------------
# Fixer routing — scanner + rule_id → (fixer_cmd_template, manual_note)
# {file} {line} are filled in from the finding.
# Entries with manual_note are flagged as needing human judgment.
# ---------------------------------------------------------------------------

# For rules not in the explicit map, these scanner-level defaults apply
_SCANNER_DEFAULTS = {
    "gitleaks": ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} <VAR_NAME>", None),
    "trivy":    ("bash {FIXERS}/dependencies/bump-cves.sh <ecosystem> <package> <fixed_version>", None),
    "grype":    ("bash {FIXERS}/dependencies/bump-cves.sh <ecosystem> <package> <fixed_version>", None),
    "zap":      (None, "Manual — DAST finding, fix in application code (B-rank)"),
    "nuclei":   (None, "Manual — DAST finding, fix in application code (B-rank)"),
}

_RULE_MAP = {
    # ── Gitleaks ────────────────────────────────────────────────────────────
    "aws-access-key":        ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} AWS_ACCESS_KEY_ID", None),
    "aws-secret-key":        ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} AWS_SECRET_ACCESS_KEY", None),
    "generic-api-key":       ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} API_KEY", None),
    "generic-secret":        ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} SECRET", None),
    "private-key":           ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} PRIVATE_KEY", None),
    "github-token":          ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} GITHUB_TOKEN", None),
    "slack-token":           ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} SLACK_TOKEN", None),
    "jwt-secret":            ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} JWT_SECRET", None),
    "database-connection-string": ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} DATABASE_URL", None),

    # ── Bandit ──────────────────────────────────────────────────────────────
    "B303": ("python3 {FIXERS}/python/fix-md5.py {file}", None),
    "B324": ("python3 {FIXERS}/python/fix-md5.py {file}", None),
    "B311": ("bash {FIXERS}/python/fix-weak-random.sh {file}", None),
    "B312": ("bash {FIXERS}/python/fix-weak-random.sh {file}", None),
    "B602": ("bash {FIXERS}/python/fix-shell-injection.sh {file}", None),
    "B603": ("bash {FIXERS}/python/fix-shell-injection.sh {file}", None),
    "B607": ("bash {FIXERS}/python/fix-shell-injection.sh {file}", None),
    "B105": ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} PASSWORD", None),
    "B106": ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} PASSWORD", None),
    "B107": ("bash {FIXERS}/secrets/fix-env-reference.sh {file} {line} PASSWORD", None),
    "B102": ("bash {FIXERS}/python/fix-exec.sh {file}", None),
    "B301": ("bash {FIXERS}/python/fix-pickle.sh {file}", None),
    "B314": ("bash {FIXERS}/python/fix-defusedxml.sh {file}", None),
    "B501": (None, "Manual — enforce TLS 1.2+ in SSL context"),
    "B506": ("bash {FIXERS}/python/fix-yaml-load.sh {file}", None),
    "B608": (None, "Manual — use parameterized queries (cursor.execute(sql, params))"),

    # ── Semgrep ─────────────────────────────────────────────────────────────
    "python.lang.security.audit.md5-used":                    ("python3 {FIXERS}/python/fix-md5.py {file}", None),
    "python.lang.security.audit.subprocess-shell-true":       ("bash {FIXERS}/python/fix-shell-injection.sh {file}", None),
    "python.lang.security.audit.insecure-random":             ("bash {FIXERS}/python/fix-weak-random.sh {file}", None),
    "yaml.kubernetes.security.run-as-non-root":               ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "yaml.kubernetes.security.allow-privilege-escalation":    ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "yaml.kubernetes.security.missing-resource-limits":       ("bash {FIXERS_K8S}/add-resource-limits.sh {file}", None),
    "dockerfile.security.last-user-is-root":                  ("bash {FIXERS}/dockerfile/add-nonroot-user.sh {file}", None),
    "dockerfile.security.missing-healthcheck":                ("bash {FIXERS}/dockerfile/add-healthcheck.sh {file}", None),
    "python.django.security.injection.sql":                   (None, "Manual — use parameterized queries"),
    "javascript.browser.security.wildcard-cors":              ("bash {FIXERS}/web/fix-cors-config.sh {file}", None),

    # ── Hadolint ─────────────────────────────────────────────────────────────
    "DL3002": ("bash {FIXERS}/dockerfile/add-nonroot-user.sh {file}", None),
    "DL3025": ("bash {FIXERS}/dockerfile/fix-cmd-format.sh {file}", None),
    "DL3003": ("bash {FIXERS}/dockerfile/fix-workdir.sh {file}", None),
    "DL3006": ("bash {FIXERS}/supply-chain/pin-base-image.sh {file}", None),
    "DL3007": ("bash {FIXERS}/supply-chain/pin-base-image.sh {file}", None),
    "DL3008": (None, "Manual — pin apt-get package version"),
    "DL3013": (None, "Manual — pin pip package version in requirements"),
    "DL4000": ("bash {FIXERS}/dockerfile/fix-maintainer.sh {file}", None),
    "SC2086": ("bash {FIXERS}/dockerfile/fix-shell-quotes.sh {file}", None),

    # ── Trivy IaC (KSV / DS) ────────────────────────────────────────────────
    "DS002": ("bash {FIXERS}/dockerfile/add-nonroot-user.sh {file}", None),
    "DS026": ("bash {FIXERS}/dockerfile/add-healthcheck.sh {file}", None),
    "KSV001": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "KSV003": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "KSV011": ("bash {FIXERS_K8S}/add-resource-limits.sh {file}", None),
    "KSV016": ("bash {FIXERS_K8S}/add-resource-limits.sh {file}", None),
    "KSV020": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "KSV021": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),

    # ── Checkov ──────────────────────────────────────────────────────────────
    "CKV_K8S_6":  ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "CKV_K8S_11": ("bash {FIXERS_K8S}/add-resource-limits.sh {file}", None),
    "CKV_K8S_12": ("bash {FIXERS_K8S}/add-resource-limits.sh {file}", None),
    "CKV_K8S_13": ("bash {FIXERS_K8S}/add-resource-limits.sh {file}", None),
    "CKV_K8S_20": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "CKV_K8S_22": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "CKV_K8S_25": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "CKV_K8S_28": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "CKV_K8S_30": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "CKV_K8S_8":  ("bash {FIXERS_K8S}/add-probes.sh {file}", None),
    "CKV_K8S_9":  ("bash {FIXERS_K8S}/add-probes.sh {file}", None),
    "CKV_K8S_14": ("bash {FIXERS}/supply-chain/pin-base-image.sh {file}", None),
    "CKV_K8S_15": ("bash {FIXERS_K8S}/fix-image-pull-policy.sh {file}", None),
    "CKV_K8S_36": (None, "Manual — remove hostPath mount"),
    "CKV_K8S_43": ("bash {FIXERS}/supply-chain/pin-base-image.sh {file}", None),
    "CKV_K8S_153": (None, "Manual — add nginx.ingress.kubernetes.io/force-ssl-redirect annotation"),
    "CKV_DOCKER_2": ("bash {FIXERS}/dockerfile/add-nonroot-user.sh {file}", None),
    "CKV_DOCKER_3": ("bash {FIXERS}/dockerfile/add-healthcheck.sh {file}", None),

    # ── Kubescape ────────────────────────────────────────────────────────────
    "C-0013": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "C-0016": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "C-0017": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "C-0034": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "C-0046": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "C-0055": ("bash {FIXERS_K8S}/add-security-context.sh {file}", None),
    "C-0074": ("bash {FIXERS_K8S}/fix-nodeport.sh {file}", None),
    "C-0001": (None, "Manual — update image registry allowlist"),
    "C-0018": ("bash {FIXERS_K8S}/add-probes.sh {file}", None),
    "C-0020": (None, "Manual — review ServiceAccount automountToken"),
    "C-0044": (None, "Manual — remove hostPort, use a Service instead"),

    # ── ZAP (DAST) — infrastructure-level fixes (D-rank) ─────────────────────
    "10038":  ("bash {FIXERS}/web/add-security-headers.sh {file}", None),      # CSP
    "10020":  ("bash {FIXERS}/web/add-security-headers.sh {file}", None),      # X-Frame-Options
    "10021":  ("bash {FIXERS}/web/add-security-headers.sh {file}", None),      # X-Content-Type-Options
    "10035":  ("bash {FIXERS}/web/add-security-headers.sh {file}", None),      # HSTS
    "10036":  ("bash {FIXERS}/web/add-security-headers.sh {file}", None),      # Server header leak
    "10010":  ("bash {FIXERS}/web/fix-cookie-flags.sh {file}", None),          # Cookie no Secure
    "10054":  ("bash {FIXERS}/web/fix-cookie-flags.sh {file}", None),          # Cookie no HttpOnly
    "10029":  ("bash {FIXERS}/web/fix-cookie-flags.sh {file}", None),          # Cookie no SameSite
    "90033":  ("bash {FIXERS}/web/fix-cors-config.sh {file}", None),           # Insecure CORS

    # ── ZAP (DAST) — application-level (B-rank, manual) ───────────────────
    "40012":  (None, "Manual — fix reflected XSS (sanitize/encode user input)"),
    "40014":  (None, "Manual — fix persistent XSS (sanitize/encode stored data)"),
    "40018":  (None, "Manual — fix SQL injection (use parameterized queries)"),
    "40043":  (None, "Manual — fix SSRF (validate/allowlist outbound URLs)"),
}

SEV_ORDER = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4}


# ---------------------------------------------------------------------------
# Parsers (same logic as parse_findings.py — normalized finding dicts)
# ---------------------------------------------------------------------------

def _sev(raw):
    return {
        "critical": "CRITICAL", "high": "HIGH", "medium": "MEDIUM",
        "moderate": "MEDIUM",   "low": "LOW",   "info": "INFO",
        "informational": "INFO","warning": "LOW","error": "HIGH",
    }.get(str(raw).lower(), "MEDIUM")


def parse_gitleaks(data):
    if not isinstance(data, list):
        return []
    return [{"scanner": "gitleaks", "severity": "CRITICAL",
             "rule_id": f.get("RuleID", "generic-secret"),
             "file": f.get("File", ""), "line": f.get("StartLine", ""),
             "description": f.get("Description", "Secret detected")} for f in data]


def parse_bandit(data):
    findings = []
    for f in data.get("results", []):
        findings.append({"scanner": "bandit",
                         "severity": _sev(f.get("issue_severity", "MEDIUM")),
                         "rule_id": f.get("test_id", ""),
                         "file": f.get("filename", ""),
                         "line": f.get("line_number", ""),
                         "description": f.get("issue_text", "")})
    return findings


def parse_semgrep(data):
    findings = []
    sev_map = {"ERROR": "HIGH", "WARNING": "MEDIUM", "INFO": "LOW"}
    for f in data.get("results", []):
        findings.append({"scanner": "semgrep",
                         "severity": sev_map.get(f.get("extra", {}).get("severity", "WARNING"), "MEDIUM"),
                         "rule_id": f.get("check_id", ""),
                         "file": f.get("path", ""),
                         "line": f.get("start", {}).get("line", ""),
                         "description": f.get("extra", {}).get("message", "")})
    return findings


_TRIVY_ECOSYSTEM_MAP = {
    "pip": "pip", "poetry": "pip", "pipenv": "pip",
    "npm": "npm", "yarn": "npm", "pnpm": "npm",
    "gomod": "go", "gobinary": "go",
    "bundler": "gem",
    "cargo": "cargo",
    "maven": "maven", "gradle": "maven",
    "nuget": "nuget",
    "apk": "apk", "dpkg": "deb", "rpm": "rpm",
}

def parse_trivy(data):
    findings = []
    for result in data.get("Results", []):
        target = result.get("Target", "")
        result_type = result.get("Type", "").lower()
        ecosystem = _TRIVY_ECOSYSTEM_MAP.get(result_type, result_type or "pip")
        for v in result.get("Vulnerabilities") or []:
            pkg = v.get("PkgName", "")
            installed = v.get("InstalledVersion", "?")
            fixed = v.get("FixedVersion", "")
            findings.append({"scanner": "trivy",
                              "severity": _sev(v.get("Severity", "MEDIUM")),
                              "rule_id": v.get("VulnerabilityID", ""),
                              "file": target,
                              "line": "",
                              "description": f"{pkg}@{installed} — {v.get('Title','')} (fix: {fixed or 'no fix available'})",
                              "pkg_name": pkg,
                              "pkg_version": installed,
                              "fix_version": fixed,
                              "ecosystem": ecosystem})
        for m in result.get("Misconfigurations") or []:
            findings.append({"scanner": "trivy",
                              "severity": _sev(m.get("Severity", "MEDIUM")),
                              "rule_id": m.get("ID", ""),
                              "file": target,
                              "line": "",
                              "description": m.get("Title", "")})
    return findings


_GRYPE_ECOSYSTEM_MAP = {
    "go-module": "go", "gobinary": "go",
    "npm": "npm", "node-pkg": "npm",
    "python": "pip", "python-pkg": "pip",
    "gem": "gem", "ruby-gem": "gem",
    "java-archive": "maven", "java": "maven",
    "rust-crate": "cargo",
    "apk": "apk", "deb": "deb", "rpm": "rpm",
}

def parse_grype(data):
    findings = []
    for m in data.get("matches", []):
        v = m.get("vulnerability", {})
        art = m.get("artifact", {})
        fix_versions = v.get("fix", {}).get("versions", [])
        fix_vers = fix_versions[0] if fix_versions else ""
        art_type = art.get("type", "").lower()
        ecosystem = _GRYPE_ECOSYSTEM_MAP.get(art_type, art_type or "pip")
        pkg_name = art.get("name", "")
        pkg_version = art.get("version", "?")
        findings.append({"scanner": "grype",
                          "severity": _sev(v.get("severity", "MEDIUM")),
                          "rule_id": v.get("id", ""),
                          "file": art.get("locations", [{}])[0].get("path", ""),
                          "line": "",
                          "description": f"{pkg_name}@{pkg_version} → fix: {fix_vers or 'no fix available'}",
                          "pkg_name": pkg_name,
                          "pkg_version": pkg_version,
                          "fix_version": fix_vers,
                          "ecosystem": ecosystem})
    return findings


def parse_hadolint(data):
    items = data if isinstance(data, list) else data.get("results", [])
    sev_map = {"error": "HIGH", "warning": "MEDIUM", "info": "LOW", "style": "LOW"}
    return [{"scanner": "hadolint",
             "severity": sev_map.get(f.get("level", "warning"), "MEDIUM"),
             "rule_id": f.get("code", ""),
             "file": f.get("file", ""),
             "line": f.get("line", ""),
             "description": f.get("message", "")} for f in items]


def parse_checkov(data):
    findings = []
    # Checkov output can be a list (one entry per framework) or a single dict
    frameworks = data if isinstance(data, list) else [data]
    for framework in frameworks:
        check_type = framework.get("check_type", "")
        for f in framework.get("results", {}).get("failed_checks", []):
            # Prefer file_abs_path (full absolute path) over repo_file_path (truncated)
            file_path = (f.get("file_abs_path")
                         or f.get("repo_file_path")
                         or f.get("file_path", ""))
            findings.append({"scanner": "checkov",
                              "severity": "MEDIUM",
                              "rule_id": f.get("check_id", ""),
                              "file": file_path,
                              "line": (f.get("file_line_range") or [None])[0] or "",
                              "description": f"{check_type or f.get('check_type','')} — {f.get('resource','')}"})
    return findings


def parse_kubescape(data):
    findings = []
    for result in data.get("results", []):
        for c in result.get("controls", []):
            if c.get("status", {}).get("status") != "failed":
                continue
            findings.append({"scanner": "kubescape",
                              "severity": "HIGH" if (c.get("scoreFactor", 5) or 5) > 7 else "MEDIUM",
                              "rule_id": c.get("controlID", ""),
                              "file": "",
                              "line": "",
                              "description": c.get("name", "")})
            break
    return findings


def parse_zap(data):
    """Parse ZAP JSON report (site[].alerts[])."""
    findings = []
    risk_map = {"0": "INFO", "1": "LOW", "2": "MEDIUM", "3": "HIGH"}
    for site in data.get("site", []):
        for alert in site.get("alerts", []):
            riskcode = str(alert.get("riskcode", "0"))
            instances = alert.get("instances", [])
            first_url = instances[0].get("uri", "") if instances else ""
            findings.append({
                "scanner": "zap",
                "severity": risk_map.get(riskcode, "MEDIUM"),
                "rule_id": alert.get("alertRef", alert.get("pluginid", "")),
                "file": "",
                "line": "",
                "url": first_url,
                "description": alert.get("alert", alert.get("name", "")),
            })
    return findings


def parse_nuclei(data):
    """Parse Nuclei JSONL — expects a list of parsed JSON objects."""
    sev_map = {"critical": "CRITICAL", "high": "HIGH", "medium": "MEDIUM",
               "low": "LOW", "info": "INFO"}
    findings = []
    for f in data:
        info = f.get("info", {})
        classification = info.get("classification", {})
        raw_sev = info.get("severity", "medium")
        cve_ids = classification.get("cve-id") or []
        template_id = f.get("template-id", "unknown")
        rule_id = cve_ids[0] if cve_ids else template_id
        findings.append({
            "scanner": "nuclei",
            "severity": sev_map.get(str(raw_sev).lower(), "MEDIUM"),
            "rule_id": rule_id,
            "file": "",
            "line": "",
            "url": f.get("matched-at", f.get("host", "")),
            "description": info.get("name", template_id),
        })
    return findings


PARSERS = {
    "gitleaks.json":     parse_gitleaks,
    "bandit.json":       parse_bandit,
    "semgrep.json":      parse_semgrep,
    "trivy-fs.json":     parse_trivy,
    "grype.json":        parse_grype,
    "checkov.json":      parse_checkov,
    "results_json.json": parse_checkov,
    "kubescape.json":    parse_kubescape,
    "zap-results.json":  parse_zap,
}


# ---------------------------------------------------------------------------
# Post-processing: remap, filter, deduplicate
# ---------------------------------------------------------------------------

# File suffixes that are scanner backup artefacts — never real targets
_BACKUP_SUFFIXES = (".bak", ".jade_backup", ".backup", ".orig")


def _is_backup_file(file_path: str) -> bool:
    p = file_path.lower()
    return any(p.endswith(s) for s in _BACKUP_SUFFIXES)


def _npm_parent_from_path(file_path: str):
    """
    Given a path like /node_modules/@scope/pkg/node_modules/esbuild/bin/esbuild,
    return the top-level npm package name (e.g. '@scope/pkg').
    Returns None if the path isn't under node_modules.
    """
    parts = file_path.lstrip("/").split("/")
    for i, part in enumerate(parts):
        if part == "node_modules" and i + 1 < len(parts):
            name = parts[i + 1]
            if name.startswith("@") and i + 2 < len(parts):
                return f"{name}/{parts[i + 2]}"
            return name
    return None


def _remap_and_filter(findings):
    """
    1. Drop findings whose file is a backup artefact.
    2. Remap Go stdlib CVEs found inside node_modules binaries → npm update <pkg>.
    """
    out = []
    for f in findings:
        file_path = f.get("file", "")

        # Drop backup files
        if _is_backup_file(file_path):
            continue

        # Remap Go binary CVEs inside node_modules → npm update
        if (f.get("ecosystem") == "go"
                and f.get("pkg_name") == "stdlib"
                and "node_modules" in file_path):
            npm_pkg = _npm_parent_from_path(file_path)
            if npm_pkg:
                f = dict(f)
                f["_remap_cmd"] = f"npm update {npm_pkg}"
                f["_remap_note"] = (
                    f"Go stdlib CVE in embedded binary — upgrade npm package {npm_pkg}"
                )

        out.append(f)
    return out


def _deduplicate(findings):
    """
    Collapse duplicate fix actions:
    - CVE findings (grype/trivy): deduplicate by (pkg_name, fix_version).
      Same package bump regardless of how many file paths triggered it.
    - Remapped node_modules: deduplicate by _remap_cmd.
    - IaC/SAST/secrets: deduplicate by (scanner, rule_id, file).
    Returns (deduped_findings, skipped_count).
    """
    seen = {}
    out = []
    skipped = 0

    for f in findings:
        rule_id = f.get("rule_id", "")
        scanner = f.get("scanner", "")

        if "_remap_cmd" in f:
            key = f["_remap_cmd"]
        elif rule_id.startswith(("CVE-", "GHSA-")):
            key = (f.get("pkg_name", ""), f.get("fix_version", ""))
        else:
            key = (scanner, rule_id, f.get("file", ""))

        if key in seen:
            skipped += 1
            continue
        seen[key] = True
        out.append(f)

    return out, skipped


# ---------------------------------------------------------------------------
# Fixer lookup
# ---------------------------------------------------------------------------

def _lookup_fixer(scanner, rule_id):
    """
    Returns (cmd_template, manual_note) — one of them will be None.
    cmd_template uses {FIXERS}, {file}, {line} placeholders.
    """
    # Exact rule match
    if rule_id in _RULE_MAP:
        return _RULE_MAP[rule_id]

    # CVE pattern (trivy/grype)
    if rule_id.startswith("CVE-") or rule_id.startswith("GHSA-"):
        return ("bash {FIXERS}/dependencies/bump-cves.sh <ecosystem> <package> <fixed_version>", None)

    # Semgrep prefix match — only for dotted rule IDs (e.g. python.lang.security.*)
    # NOT for numbered IDs like CKV_K8S_15 where CKV_K8S_153 would falsely match
    if "." in rule_id:
        for key in _RULE_MAP:
            if rule_id.startswith(key):
                return _RULE_MAP[key]

    # Scanner-level default
    if scanner in _SCANNER_DEFAULTS:
        return _SCANNER_DEFAULTS[scanner]

    return (None, "Manual — no automated fixer. See 02-fixers/README.md")


def _render_cmd(template, finding):
    file = finding.get("file", "")
    line = finding.get("line", "")
    cmd = template.replace("{FIXERS_K8S}", str(FIXERS_K8S))
    cmd = cmd.replace("{FIXERS}", str(FIXERS_DIR))
    cmd = cmd.replace("{file}", str(file) if file else "<file>")
    cmd = cmd.replace("{line}", str(line) if line else "<line>")
    # Fill in real package details for dependency CVE commands
    if "<ecosystem>" in cmd or "<package>" in cmd or "<fixed_version>" in cmd:
        cmd = cmd.replace("<ecosystem>",    finding.get("ecosystem", "<ecosystem>"))
        cmd = cmd.replace("<package>",      finding.get("pkg_name", "<package>"))
        cmd = cmd.replace("<fixed_version>", finding.get("fix_version", "<fixed_version>") or "no-fix-available")
    return cmd


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _load_jsonl(path: Path):
    """Load a JSONL file (one JSON object per line) into a list."""
    items = []
    for line in path.read_text().strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            items.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return items


def load_findings(scan_dir: Path):
    all_findings = []

    # Standard JSON files
    for json_file in sorted(scan_dir.rglob("*.json")):
        parser = PARSERS.get(json_file.name)
        if parser is None and json_file.name.startswith("hadolint"):
            parser = parse_hadolint
        if parser is None:
            continue
        try:
            text = json_file.read_text().strip()
            if not text:
                print(f"  —  {json_file.name}: empty (0 findings)")
                continue
            data = json.loads(text)
        except Exception as e:
            print(f"  ⚠  Skipping {json_file.name}: {e}")
            continue
        findings = parser(data)
        if findings:
            print(f"  ✓  {json_file.name}: {len(findings)} findings")
        all_findings.extend(findings)

    # JSONL files (Nuclei output)
    for jsonl_file in sorted(scan_dir.rglob("*.jsonl")):
        if jsonl_file.name.startswith("nuclei"):
            try:
                text = jsonl_file.read_text().strip()
                if not text:
                    print(f"  —  {jsonl_file.name}: empty (0 findings)")
                    continue
                data = _load_jsonl(jsonl_file)
                findings = parse_nuclei(data)
                if findings:
                    print(f"  ✓  {jsonl_file.name}: {len(findings)} findings")
                all_findings.extend(findings)
            except Exception as e:
                print(f"  ⚠  Skipping {jsonl_file.name}: {e}")

    return all_findings


def _extract_engagement_context(scan_dir: Path):
    """Extract instance/slot/project/scan_label from the scan_dir path.

    Expected:  .../5-consulting-reports/<instance>/<slot>/<label>-YYYYMMDD/
    Fallback:  .../5-consulting-reports/<project-slug>/<label>-YYYYMMDD/
    """
    parts = scan_dir.resolve().parts
    ctx = {"instance": "", "slot": "", "scan_label": "", "scan_date": ""}

    # Try to find the consulting-reports anchor
    for i, part in enumerate(parts):
        if part == "5-consulting-reports" and i + 1 < len(parts):
            remaining = parts[i + 1:]
            # Pattern: <instance>/<slot>/<label-date>
            if (len(remaining) >= 3
                    and "instance" in remaining[0]
                    and remaining[1].startswith("slot-")):
                ctx["instance"] = remaining[0]
                ctx["slot"] = remaining[1]
                label_date = remaining[2]
            elif len(remaining) >= 2:
                # Fallback: <slug>/<label-date>
                ctx["instance"] = remaining[0]
                label_date = remaining[1]
            else:
                break

            # Split "baseline-20260225" → label + date
            if "-" in label_date:
                dash_idx = label_date.rfind("-")
                date_part = label_date[dash_idx + 1:]
                if date_part.isdigit() and len(date_part) == 8:
                    ctx["scan_label"] = label_date[:dash_idx]
                    ctx["scan_date"] = date_part
                else:
                    ctx["scan_label"] = label_date
            else:
                ctx["scan_label"] = label_date
            break

    # Fill scan_date from dir name if not extracted
    if not ctx["scan_date"]:
        dirname = scan_dir.name
        # Look for YYYYMMDD at the end
        if len(dirname) >= 8 and dirname[-8:].isdigit():
            ctx["scan_date"] = dirname[-8:]

    return ctx


# Fixer script → category mapping for analytics
_FIXER_CATEGORY = {
    "fix-env-reference": "secrets",
    "git-purge-secret": "secrets",
    "fix-md5": "python-sast",
    "fix-weak-random": "python-sast",
    "fix-shell-injection": "python-sast",
    "fix-yaml-load": "python-sast",
    "fix-pickle": "python-sast",
    "fix-defusedxml": "python-sast",
    "fix-exec": "python-sast",
    "add-nonroot-user": "dockerfile",
    "add-healthcheck": "dockerfile",
    "fix-maintainer": "dockerfile",
    "fix-cmd-format": "dockerfile",
    "fix-workdir": "dockerfile",
    "fix-shell-quotes": "dockerfile",
    "add-security-context": "kubernetes",
    "add-resource-limits": "kubernetes",
    "fix-nodeport": "kubernetes",
    "add-probes": "kubernetes",
    "fix-pull-policy": "kubernetes",
    "fix-image-pull-policy": "kubernetes",
    "disable-service-account-token": "kubernetes",
    "pin-base-image": "supply-chain",
    "generate-sbom": "supply-chain",
    "check-licenses": "supply-chain",
    "bump-cves": "dependencies",
    "add-security-headers": "web-security",
    "fix-cookie-flags": "web-security",
    "fix-cors-config": "web-security",
}

# E-rank: deterministic, near-100% safe
_E_RANK_FIXERS = {"fix-env-reference", "fix-md5", "fix-yaml-load", "fix-maintainer"}
# C-rank: context-dependent, needs JADE review
_C_RANK_FIXERS = {"fix-pickle", "fix-exec", "add-probes", "fix-shell-quotes"}


def _classify_fixer(cmd: str):
    """Return (category, rank) from a fixer command string."""
    for fixer_name, category in _FIXER_CATEGORY.items():
        if fixer_name in cmd:
            if fixer_name in _E_RANK_FIXERS:
                rank = "E"
            elif fixer_name in _C_RANK_FIXERS:
                rank = "C"
            else:
                rank = "D"
            return category, rank
    return "unknown", "D"


def export_csv(scan_dir: Path, project: str, findings: list, auto_fixable: list, manual: list):
    """Export findings as a flat CSV designed for accumulation across engagements.

    Columns are designed for pandas analysis:
    - Engagement context: project, instance, slot, scan_label, scan_date
    - Finding identity: severity, scanner, rule_id, category
    - Location: file, line, file_ext, ecosystem
    - Fix info: fix_type, fix_category, fixer_script, rank
    - Description: description (truncated for cleanliness)
    """
    csv_path = scan_dir / "findings.csv"
    ctx = _extract_engagement_context(scan_dir)

    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            # Engagement context (so you can pd.concat across runs)
            "project", "instance", "slot", "scan_label", "scan_date",
            # Finding identity
            "severity", "scanner", "rule_id", "category",
            # Location
            "file", "line", "file_ext", "ecosystem",
            # Fix info
            "fix_type", "fix_category", "fixer_script", "rank",
            # Human-readable
            "description",
        ])

        for finding in auto_fixable:
            cmd = finding.get("cmd", "")
            fix_category, rank = _classify_fixer(cmd)

            # Extract just the script name (not the full path)
            fixer_script = ""
            if "/" in cmd:
                # "bash /long/path/02-fixers/python/fix-md5.py file.py" → "python/fix-md5.py"
                for part in cmd.split():
                    if "02-fixers/" in part:
                        fixer_script = part.split("02-fixers/")[-1]
                        break

            file_path = finding.get("file", "")
            file_ext = Path(file_path).suffix if file_path else ""

            writer.writerow([
                project,
                ctx["instance"], ctx["slot"], ctx["scan_label"], ctx["scan_date"],
                finding["severity"], finding["scanner"], finding["rule_id"], fix_category,
                file_path, finding.get("line", ""), file_ext,
                finding.get("ecosystem", ""),
                "auto", fix_category, fixer_script, rank,
                finding.get("description", "")[:200],
            ])

        for finding in manual:
            file_path = finding.get("file", "")
            file_ext = Path(file_path).suffix if file_path else ""

            writer.writerow([
                project,
                ctx["instance"], ctx["slot"], ctx["scan_label"], ctx["scan_date"],
                finding["severity"], finding["scanner"], finding["rule_id"], "manual",
                file_path, finding.get("line", ""), file_ext,
                finding.get("ecosystem", ""),
                "manual", "", "", "B",
                finding.get("description", "")[:200],
            ])

    print(f"  CSV exported: {csv_path}")
    return csv_path


def _generate_fix_script(scan_dir: Path, project: str, auto_fixable: list,
                         artifact_auto: list, target_dir: str = None):
    """Generate fix-auto.sh — a runnable bash script with deduplicated fixer commands.

    Groups commands by target file so each file is only backed up once.
    Client code fixes run first, then artifact fixes (commented out by default).
    """
    script_path = scan_dir / "fix-auto.sh"

    # Deduplicate: same command string → run only once
    seen_cmds = set()

    def _dedup(items):
        out = []
        for f in items:
            cmd = f.get("cmd", "")
            if cmd and cmd not in seen_cmds:
                seen_cmds.add(cmd)
                out.append(f)
        return out

    client_deduped = _dedup(auto_fixable)
    artifact_deduped = _dedup(artifact_auto)

    # Group by target file for cleaner execution
    def _group_by_file(items):
        groups = {}
        for f in items:
            cmd = f["cmd"]
            # Extract the target file (last argument in the command)
            parts = cmd.rstrip().split()
            target = parts[-1] if parts else ""
            groups.setdefault(target, []).append(f)
        return groups

    client_groups = _group_by_file(client_deduped)
    artifact_groups = _group_by_file(artifact_deduped)

    lines = [
        "#!/usr/bin/env bash",
        f"# fix-auto.sh — Auto-generated by triage.py",
        f"# Project: {project}",
        f"# Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"# Scan dir: {scan_dir}",
        "#",
        f"# Client code fixes: {len(client_deduped)}",
        f"# Artifact fixes: {len(artifact_deduped)} (commented out — uncomment to run)",
        "#",
        "# Usage:",
        "#   bash fix-auto.sh          # Run all client code fixes",
        "#   bash fix-auto.sh --dry    # Print commands without running",
        "",
        'set -euo pipefail',
        '',
        'RED=\'\\033[0;31m\'; GREEN=\'\\033[0;32m\'; YELLOW=\'\\033[1;33m\'',
        'BLUE=\'\\033[0;34m\'; NC=\'\\033[0m\'',
        '',
        'DRY_RUN=false',
        '[[ "${1:-}" == "--dry" ]] && DRY_RUN=true',
        '',
        'run_fix() {',
        '    local cmd="$1"',
        '    local desc="$2"',
        '    echo -e "${BLUE}[FIX]${NC} $desc"',
        '    # Skip commands with unresolved placeholders',
        '    if [[ "$cmd" == *"<"*">"* ]]; then',
        '        echo -e "${YELLOW}  SKIP: contains placeholder — needs manual input${NC}"',
        '        echo "  $cmd"',
        '        echo ""',
        '        return 0',
        '    fi',
        '    if $DRY_RUN; then',
        '        echo "  $cmd"',
        '    else',
        '        bash -c "$cmd" || echo -e "${RED}  FAILED (non-zero exit)${NC}"',
        '    fi',
        '    echo ""',
        '}',
        '',
        'echo ""',
        f'echo -e "${{BLUE}}=== Ghost Protocol — Auto-Fix ({len(client_deduped)} client fixes) ===${{NC}}"',
        'echo ""',
        '',
        '# ── Client Code Fixes ─────────────────────────────────────────────────────',
        '',
    ]

    if not client_deduped:
        lines.append('echo "No auto-fixable client code findings."')
        lines.append('')
    else:
        for target_file, fixes in client_groups.items():
            short_file = Path(target_file).name if target_file else "unknown"
            lines.append(f'# --- {short_file} ---')
            for f in fixes:
                desc = f"[{f['scanner']}] {f['rule_id']}"
                # Escape single quotes in command for the run_fix wrapper
                cmd_escaped = f["cmd"].replace("'", "'\\''")
                lines.append(f"run_fix '{cmd_escaped}' '{desc}'")
            lines.append('')

    # Artifact fixes — commented out
    if artifact_deduped:
        lines += [
            '# ── GP-Copilot Artifact Fixes (uncomment to run) ─────────────────────────',
            '# These fix consulting templates, not client code.',
            '',
        ]
        for target_file, fixes in artifact_groups.items():
            short_file = Path(target_file).name if target_file else "unknown"
            lines.append(f'# --- {short_file} ---')
            for f in fixes:
                desc = f"[{f['scanner']}] {f['rule_id']}"
                cmd_escaped = f["cmd"].replace("'", "'\\''")
                lines.append(f"# run_fix '{cmd_escaped}' '{desc}'")
            lines.append('')

    # Re-scan command
    target_placeholder = target_dir if target_dir else "<client-repo>"
    lines += [
        '# ── Re-scan ───────────────────────────────────────────────────────────────',
        'echo ""',
        'echo -e "${GREEN}=== Fixes complete ===${NC}"',
        'echo ""',
        'echo "Re-scan:"',
        f'echo "  bash {PKG_DIR}/tools/run-all-scanners.sh \\\\"',
        f'echo "    --target-dir {target_placeholder} \\\\"',
        f'echo "    --output-dir {scan_dir.parent}/post-fix-$(date +%Y%m%d)"',
    ]

    script_path.write_text("\n".join(lines) + "\n")
    script_path.chmod(0o755)
    print(f"  fix-auto.sh exported: {script_path}")
    return script_path


def generate_plan(scan_dir: Path, project: str, target_dir: str = None, write_csv: bool = False):
    print(f"\nReading scan dir: {scan_dir}")
    findings = load_findings(scan_dir)

    if not findings:
        print("\nNo findings parsed. Check scan directory contains scanner JSON files.")
        return

    raw_count = len(findings)
    findings = _remap_and_filter(findings)
    findings, skipped = _deduplicate(findings)
    print(f"  Deduplicated : {raw_count} raw → {len(findings)} unique ({skipped} duplicates removed)")

    # Sort by severity
    findings.sort(key=lambda f: SEV_ORDER.get(f["severity"], 99))

    # Separate GP-Copilot consulting artifacts from client code.
    # Findings in GP-Copilot/ are our templates/remediations — not the client's app.
    _ARTIFACT_MARKERS = ("GP-Copilot/", "/GP-Copilot/", "gp-copilot/")

    def _is_artifact(f):
        path = str(f.get("file", ""))
        return any(m in path for m in _ARTIFACT_MARKERS)

    client_findings = [f for f in findings if not _is_artifact(f)]
    artifact_findings = [f for f in findings if _is_artifact(f)]

    auto_fixable = []
    manual = []
    artifact_auto = []
    artifact_manual = []

    for f in client_findings:
        if "_remap_cmd" in f:
            auto_fixable.append({**f, "cmd": f["_remap_cmd"]})
        else:
            cmd_tpl, note = _lookup_fixer(f["scanner"], f["rule_id"])
            if cmd_tpl:
                cmd = _render_cmd(cmd_tpl, f)
                auto_fixable.append({**f, "cmd": cmd})
            else:
                manual.append({**f, "note": note or "Manual fix required"})

    for f in artifact_findings:
        if "_remap_cmd" in f:
            artifact_auto.append({**f, "cmd": f["_remap_cmd"]})
        else:
            cmd_tpl, note = _lookup_fixer(f["scanner"], f["rule_id"])
            if cmd_tpl:
                cmd = _render_cmd(cmd_tpl, f)
                artifact_auto.append({**f, "cmd": cmd})
            else:
                artifact_manual.append({**f, "note": note or "Manual fix required"})

    # Write REMEDIATION-PLAN.md
    out = scan_dir / "REMEDIATION-PLAN.md"
    lines = []

    total_client = len(auto_fixable) + len(manual)
    total_artifact = len(artifact_auto) + len(artifact_manual)

    lines += [
        f"# Remediation Plan — {project}",
        f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Scan dir: `{scan_dir}`",
        "",
        f"**{raw_count} raw findings → {len(findings)} unique**",
        "",
        f"| Category | Auto-Fixable | Manual | Total |",
        f"|----------|-------------|--------|-------|",
        f"| **Client code** | {len(auto_fixable)} | {len(manual)} | {total_client} |",
        f"| GP-Copilot artifacts | {len(artifact_auto)} | {len(artifact_manual)} | {total_artifact} |",
        f"| **Total** | {len(auto_fixable) + len(artifact_auto)} | {len(manual) + len(artifact_manual)} | {len(findings)} |",
        "",
    ]

    # Stats table — client code only
    by_sev = {}
    for f in client_findings:
        by_sev[f["severity"]] = by_sev.get(f["severity"], 0) + 1
    lines += ["## Client Code — Severity Breakdown", ""]
    lines += ["| Severity | Count |", "|----------|-------|"]
    for sev in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]:
        if sev in by_sev:
            lines.append(f"| {sev} | {by_sev[sev]} |")
    lines += [""]

    # ── CLIENT CODE: Auto-fixable ──
    lines += [
        "---",
        "",
        f"## Auto-Fixable — Client Code ({len(auto_fixable)} findings)",
        "",
        "> Run these commands from your repo root. Each script creates a `.bak` backup.",
        "",
    ]

    if not auto_fixable:
        lines += ["*No auto-fixable findings in client code.*", ""]

    current_sev = None
    for f in auto_fixable:
        if f["severity"] != current_sev:
            current_sev = f["severity"]
            lines += [f"### {current_sev}", ""]
        loc = f"{f['file']}:{f['line']}" if f.get("line") else f.get("file", "")
        lines += [
            f"**[{f['scanner']}] {f['rule_id']}** — {f['description'][:80]}",
            f"`{loc}`" if loc else "",
            "```bash",
            f["cmd"],
            "```",
            "",
        ]

    # ── CLIENT CODE: Manual ──
    lines += [
        "---",
        "",
        f"## Manual Fixes Required — Client Code ({len(manual)} findings)",
        "",
        "| Severity | Scanner | Rule | File | Guidance |",
        "|----------|---------|------|------|----------|",
    ]
    for f in manual:
        file_path = str(f.get("file", ""))
        # Show last 60 chars for readability but keep enough context
        file_short = file_path[-60:] if len(file_path) > 60 else file_path
        if not file_short:
            file_short = "—"
        note = f.get("note", "See 02-fixers/README.md")
        lines.append(
            f"| {f['severity']} | {f['scanner']} | `{f['rule_id']}` "
            f"| `{file_short}` | {note} |"
        )

    # ── GP-COPILOT ARTIFACTS ──
    if artifact_auto or artifact_manual:
        lines += [
            "",
            "---",
            "",
            f"## GP-Copilot Artifacts ({total_artifact} findings)",
            "",
            "> These findings are in consulting templates and remediation examples (`GP-Copilot/`).",
            "> They are **not client code** — fix only if you want clean templates.",
            "",
        ]

        if artifact_auto:
            lines += [f"### Auto-Fixable ({len(artifact_auto)})", ""]
            current_sev = None
            for f in artifact_auto:
                if f["severity"] != current_sev:
                    current_sev = f["severity"]
                    lines += [f"#### {current_sev}", ""]
                loc = f"{f['file']}:{f['line']}" if f.get("line") else f.get("file", "")
                lines += [
                    f"**[{f['scanner']}] {f['rule_id']}** — {f['description'][:80]}",
                    f"`{loc}`" if loc else "",
                    "```bash",
                    f["cmd"],
                    "```",
                    "",
                ]

        if artifact_manual:
            lines += [f"### Manual ({len(artifact_manual)})", ""]
            lines += [
                "| Severity | Scanner | Rule | File | Guidance |",
                "|----------|---------|------|------|----------|",
            ]
            for f in artifact_manual:
                file_path = str(f.get("file", ""))
                file_short = file_path[-60:] if len(file_path) > 60 else file_path
                if not file_short:
                    file_short = "—"
                note = f.get("note", "See 02-fixers/README.md")
                lines.append(
                    f"| {f['severity']} | {f['scanner']} | `{f['rule_id']}` "
                    f"| `{file_short}` | {note} |"
                )

    target_placeholder = target_dir if target_dir else "<client-repo>"
    lines += [
        "",
        "---",
        "",
        "## Re-scan After Fixes",
        "",
        "```bash",
        f"bash {PKG_DIR}/tools/run-all-scanners.sh \\",
        f"  --target-dir {target_placeholder} \\",
        f"  --output-dir {scan_dir.parent}/post-fix-$(date +%Y%m%d)",
        "```",
        "",
        "*Ghost Protocol — Pre-Deployment Package*",
    ]

    out.write_text("\n".join(lines))

    if write_csv:
        export_csv(scan_dir, project, findings, auto_fixable, manual)

    # Always generate fix-auto.sh
    fix_script = _generate_fix_script(
        scan_dir, project, auto_fixable, artifact_auto, target_dir=target_dir
    )

    print(f"\n{'='*60}")
    print(f"Raw findings   : {raw_count}")
    print(f"Deduplicated   : {len(findings)} ({skipped} removed)")
    print(f"Client code    : {total_client} ({len(auto_fixable)} auto, {len(manual)} manual)")
    print(f"GP-Copilot     : {total_artifact} (consulting artifacts, not client code)")
    print(f"{'='*60}")
    print(f"\nREMEDIATION-PLAN.md written to:")
    print(f"  {out}")
    print(f"\nRun all auto-fixes:")
    print(f"  bash {fix_script}")
    print(f"  bash {fix_script} --dry   # preview only")
    print(f"\nRe-scan when done:")
    print(f"  bash {PKG_DIR}/tools/run-all-scanners.sh \\")
    print(f"    --target-dir {target_placeholder} \\")
    print(f"    --output-dir {scan_dir.parent}/post-fix-$(date +%Y%m%d)")


def main():
    parser = argparse.ArgumentParser(
        description="Read scanner outputs → generate REMEDIATION-PLAN.md with fixer commands"
    )
    parser.add_argument("--scan-dir", required=True,
                        help="Path to run-all-scanners.sh output directory")
    parser.add_argument("--project", default="client",
                        help="Project/client name for the report header")
    parser.add_argument("--target-dir", default=None,
                        help="Client repo path — pre-fills the re-scan command")
    parser.add_argument("--csv", action="store_true",
                        help="Also export findings.csv (flat spreadsheet format)")
    args = parser.parse_args()

    scan_dir = Path(args.scan_dir)
    if not scan_dir.exists():
        print(f"ERROR: scan directory not found: {scan_dir}", file=sys.stderr)
        sys.exit(1)

    generate_plan(scan_dir, args.project, target_dir=args.target_dir, write_csv=args.csv)


if __name__ == "__main__":
    main()
