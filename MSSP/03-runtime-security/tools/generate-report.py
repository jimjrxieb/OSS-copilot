#!/usr/bin/env python3
"""
generate-report.py
Generate a weekly security report from jsa-infrasec metrics.

Queries Prometheus for runtime security metrics and produces a formatted
report with executive summary, findings breakdown, MITRE coverage, and
recommendations.

Usage:
    python3 tools/generate-report.py
    python3 tools/generate-report.py --start 2026-02-01 --end 2026-02-07
    python3 tools/generate-report.py --format markdown --output report.md
    python3 tools/generate-report.py --format html --output report.html
    python3 tools/generate-report.py --prometheus http://localhost:9090
    python3 tools/generate-report.py --demo
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from typing import Any

# ── Demo data (for --demo flag or when Prometheus is unavailable) ─────────

DEMO_DATA = {
    "period": {"start": "", "end": ""},
    "summary": {
        "total_findings": 47,
        "critical": 3,
        "high": 8,
        "medium": 19,
        "low": 17,
        "mttd_seconds": 4.2,
        "mttf_seconds": 38.7,
        "fix_rate": 0.89,
        "rollbacks": 2,
        "rollback_success_rate": 1.0,
    },
    "top_findings": [
        {"rule": "Terminal shell in container", "severity": "critical", "count": 3, "mitre": "T1059 - Command and Scripting Interpreter"},
        {"rule": "Privileged pod created", "severity": "critical", "count": 2, "mitre": "T1611 - Escape to Host"},
        {"rule": "Sensitive file opened for reading", "severity": "high", "count": 5, "mitre": "T1552 - Unsecured Credentials"},
        {"rule": "K8s secret accessed", "severity": "high", "count": 4, "mitre": "T1528 - Steal Application Access Token"},
        {"rule": "Outbound connection to C2", "severity": "high", "count": 3, "mitre": "T1071 - Application Layer Protocol"},
        {"rule": "Crypto mining process detected", "severity": "medium", "count": 6, "mitre": "T1496 - Resource Hijacking"},
        {"rule": "Unexpected network tool launched", "severity": "medium", "count": 4, "mitre": "T1046 - Network Service Discovery"},
        {"rule": "Package manager in container", "severity": "medium", "count": 3, "mitre": "T1072 - Software Deployment Tools"},
        {"rule": "Non-sudo setuid execution", "severity": "low", "count": 7, "mitre": "T1548 - Abuse Elevation Control Mechanism"},
        {"rule": "DNS query to .onion domain", "severity": "low", "count": 2, "mitre": "T1090 - Proxy"},
    ],
    "mitre_coverage": {
        "initial_access": 2,
        "execution": 5,
        "persistence": 1,
        "privilege_escalation": 4,
        "defense_evasion": 3,
        "credential_access": 4,
        "discovery": 3,
        "lateral_movement": 1,
        "collection": 2,
        "exfiltration": 1,
        "impact": 6,
    },
    "falco_alerts": {
        "Terminal shell in container": 12,
        "Read sensitive file untrusted": 9,
        "Write below etc": 7,
        "Contact K8S API Server From Container": 6,
        "Launch Privileged Container": 5,
        "Unexpected outbound connection": 4,
        "Mkdir binary dirs": 3,
        "Change thread namespace": 2,
    },
    "response_time_p50_seconds": 3.1,
    "response_time_p95_seconds": 12.4,
    "response_time_p99_seconds": 28.6,
    "rollbacks": [
        {"deployment": "payment-api", "reason": "privileged container added", "result": "success", "time": "2026-02-03T14:22:00Z"},
        {"deployment": "frontend-web", "reason": "resource limits removed", "result": "success", "time": "2026-02-05T09:15:00Z"},
    ],
    "recommendations": [
        "Investigate 3 critical findings in Terminal shell in container — potential interactive access.",
        "Review payment-api deployment — triggered 1 rollback this period.",
        "Falco rule 'Read sensitive file untrusted' fired 9 times — consider tuning with allowlist if expected.",
        "MTTF of 38.7s is within SLA. Target: reduce to < 30s by tuning rank classification.",
        "Add Kyverno policy to block privileged containers at admission (02-CLUSTER-HARDEN).",
    ],
}


def query_prometheus(prom_url: str, query: str, start: str, end: str) -> Any:
    """Query Prometheus range API. Returns None on failure."""
    try:
        import requests
        resp = requests.get(
            f"{prom_url}/api/v1/query_range",
            params={"query": query, "start": start, "end": end, "step": "1h"},
            timeout=10,
        )
        if resp.status_code == 200:
            return resp.json().get("data", {}).get("result", [])
    except Exception:
        pass
    return None


def query_instant(prom_url: str, query: str) -> Any:
    """Query Prometheus instant API. Returns None on failure."""
    try:
        import requests
        resp = requests.get(
            f"{prom_url}/api/v1/query",
            params={"query": query},
            timeout=10,
        )
        if resp.status_code == 200:
            result = resp.json().get("data", {}).get("result", [])
            if result:
                return float(result[0]["value"][1])
    except Exception:
        pass
    return None


def collect_metrics(prom_url: str, start: str, end: str) -> dict:
    """Collect jsa-infrasec metrics from Prometheus."""
    data = {
        "period": {"start": start, "end": end},
        "summary": {},
        "top_findings": [],
        "mitre_coverage": {},
        "falco_alerts": {},
        "rollbacks": [],
        "recommendations": [],
    }

    # Total findings by severity
    for sev in ["critical", "high", "medium", "low"]:
        val = query_instant(prom_url, f'sum(jsa_infrasec_findings_total{{severity="{sev}"}})')
        data["summary"][sev] = int(val) if val is not None else None

    total = query_instant(prom_url, "sum(jsa_infrasec_findings_total)")
    data["summary"]["total_findings"] = int(total) if total is not None else None

    # MTTD / MTTF
    mttd = query_instant(prom_url, "avg(jsa_infrasec_mttd_seconds)")
    data["summary"]["mttd_seconds"] = round(mttd, 1) if mttd is not None else None

    mttf = query_instant(prom_url, "avg(jsa_infrasec_mttf_seconds)")
    data["summary"]["mttf_seconds"] = round(mttf, 1) if mttf is not None else None

    # Fix rate
    fix_rate = query_instant(prom_url, "sum(jsa_infrasec_fixes_total) / sum(jsa_infrasec_findings_total)")
    data["summary"]["fix_rate"] = round(fix_rate, 2) if fix_rate is not None else None

    # Rollbacks
    rollbacks = query_instant(prom_url, "sum(jsa_infrasec_rollbacks_total)")
    data["summary"]["rollbacks"] = int(rollbacks) if rollbacks is not None else None

    rollback_success = query_instant(prom_url, "sum(jsa_infrasec_rollbacks_total{result='success'}) / sum(jsa_infrasec_rollbacks_total)")
    data["summary"]["rollback_success_rate"] = round(rollback_success, 2) if rollback_success is not None else None

    # Response times
    for pct, label in [("0.5", "response_time_p50_seconds"), ("0.95", "response_time_p95_seconds"), ("0.99", "response_time_p99_seconds")]:
        val = query_instant(prom_url, f'histogram_quantile({pct}, sum(rate(jsa_infrasec_response_duration_seconds_bucket[7d])) by (le))')
        data[label] = round(val, 1) if val is not None else None

    # Falco alerts
    falco_result = query_prometheus(prom_url, 'sum by (rule)(increase(falco_events_total[7d]))', start, end)
    if falco_result:
        for item in falco_result:
            rule = item["metric"].get("rule", "unknown")
            count = int(float(item["values"][-1][1])) if item.get("values") else 0
            data["falco_alerts"][rule] = count

    # Check if we got any real data
    has_data = any(v is not None for v in data["summary"].values())
    return data if has_data else None


def val_or_na(v: Any) -> str:
    """Format a value or return N/A."""
    if v is None:
        return "N/A"
    return str(v)


def pct_or_na(v: Any) -> str:
    """Format a percentage or return N/A."""
    if v is None:
        return "N/A"
    return f"{v * 100:.0f}%"


def generate_markdown(data: dict) -> str:
    """Generate a markdown report."""
    s = data["summary"]
    lines = []

    lines.append("# jsa-infrasec Weekly Security Report")
    lines.append("")
    lines.append(f"**Period:** {data['period']['start']} to {data['period']['end']}")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    # Executive Summary
    lines.append("## Executive Summary")
    lines.append("")
    lines.append(f"| Metric | Value |")
    lines.append(f"|--------|-------|")
    lines.append(f"| Total Findings | {val_or_na(s.get('total_findings'))} |")
    lines.append(f"| Critical | {val_or_na(s.get('critical'))} |")
    lines.append(f"| High | {val_or_na(s.get('high'))} |")
    lines.append(f"| Medium | {val_or_na(s.get('medium'))} |")
    lines.append(f"| Low | {val_or_na(s.get('low'))} |")
    lines.append(f"| MTTD (Mean Time to Detect) | {val_or_na(s.get('mttd_seconds'))}s |")
    lines.append(f"| MTTF (Mean Time to Fix) | {val_or_na(s.get('mttf_seconds'))}s |")
    lines.append(f"| Fix Rate | {pct_or_na(s.get('fix_rate'))} |")
    lines.append(f"| Rollbacks | {val_or_na(s.get('rollbacks'))} |")
    lines.append(f"| Rollback Success Rate | {pct_or_na(s.get('rollback_success_rate'))} |")
    lines.append("")

    # Top Findings
    if data.get("top_findings"):
        lines.append("## Top Findings by Severity")
        lines.append("")
        lines.append("| # | Rule | Severity | Count | MITRE ATT&CK |")
        lines.append("|---|------|----------|-------|--------------|")
        for i, f in enumerate(data["top_findings"], 1):
            lines.append(f"| {i} | {f['rule']} | {f['severity']} | {f['count']} | {f.get('mitre', 'N/A')} |")
        lines.append("")

    # MITRE ATT&CK Coverage
    if data.get("mitre_coverage"):
        lines.append("## MITRE ATT&CK Coverage")
        lines.append("")
        lines.append("| Tactic | Detections |")
        lines.append("|--------|-----------|")
        for tactic, count in data["mitre_coverage"].items():
            tactic_display = tactic.replace("_", " ").title()
            bar = "█" * count
            lines.append(f"| {tactic_display} | {count} {bar} |")
        lines.append("")

    # Response Time
    lines.append("## Response Time")
    lines.append("")
    lines.append("| Percentile | Time |")
    lines.append("|-----------|------|")
    lines.append(f"| p50 | {val_or_na(data.get('response_time_p50_seconds'))}s |")
    lines.append(f"| p95 | {val_or_na(data.get('response_time_p95_seconds'))}s |")
    lines.append(f"| p99 | {val_or_na(data.get('response_time_p99_seconds'))}s |")
    lines.append("")

    # Falco Alerts
    if data.get("falco_alerts"):
        lines.append("## Falco Alert Breakdown")
        lines.append("")
        lines.append("| Rule | Count |")
        lines.append("|------|-------|")
        sorted_alerts = sorted(data["falco_alerts"].items(), key=lambda x: x[1], reverse=True)
        for rule, count in sorted_alerts:
            lines.append(f"| {rule} | {count} |")
        lines.append("")

    # Rollback Summary
    if data.get("rollbacks"):
        lines.append("## Rollback Summary")
        lines.append("")
        lines.append("| Deployment | Reason | Result | Time |")
        lines.append("|-----------|--------|--------|------|")
        for rb in data["rollbacks"]:
            lines.append(f"| {rb['deployment']} | {rb['reason']} | {rb['result']} | {rb['time']} |")
        lines.append("")

    # Recommendations
    if data.get("recommendations"):
        lines.append("## Recommendations")
        lines.append("")
        for i, rec in enumerate(data["recommendations"], 1):
            lines.append(f"{i}. {rec}")
        lines.append("")

    lines.append("---")
    lines.append("*Generated by GP-Copilot / 03-RUNTIME-SECURITY / generate-report.py*")
    lines.append("")

    return "\n".join(lines)


def generate_html(data: dict) -> str:
    """Generate an HTML report by wrapping the markdown in a simple HTML page."""
    md_content = generate_markdown(data)
    # Simple HTML wrapper — no external dependencies
    html_lines = [
        "<!DOCTYPE html>",
        "<html lang='en'>",
        "<head>",
        "  <meta charset='UTF-8'>",
        "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>",
        "  <title>jsa-infrasec Weekly Security Report</title>",
        "  <style>",
        "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;",
        "           max-width: 900px; margin: 40px auto; padding: 0 20px; color: #333; }",
        "    h1 { color: #1a1a2e; border-bottom: 2px solid #0f3460; padding-bottom: 10px; }",
        "    h2 { color: #0f3460; margin-top: 30px; }",
        "    table { border-collapse: collapse; width: 100%; margin: 15px 0; }",
        "    th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }",
        "    th { background: #0f3460; color: white; }",
        "    tr:nth-child(even) { background: #f9f9f9; }",
        "    .critical { color: #dc3545; font-weight: bold; }",
        "    .high { color: #fd7e14; font-weight: bold; }",
        "    .medium { color: #ffc107; }",
        "    .low { color: #28a745; }",
        "    pre { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; }",
        "    hr { border: none; border-top: 1px solid #ddd; margin: 30px 0; }",
        "  </style>",
        "</head>",
        "<body>",
    ]

    # Convert markdown tables and headings to HTML
    for line in md_content.split("\n"):
        if line.startswith("# "):
            html_lines.append(f"<h1>{line[2:]}</h1>")
        elif line.startswith("## "):
            html_lines.append(f"<h2>{line[3:]}</h2>")
        elif line.startswith("**") and line.endswith("**"):
            html_lines.append(f"<p><strong>{line.strip('*')}</strong></p>")
        elif line.startswith("**"):
            html_lines.append(f"<p>{line.replace('**', '<strong>', 1).replace('**', '</strong>', 1)}</p>")
        elif line.startswith("|") and "---" in line:
            continue  # skip markdown table separators
        elif line.startswith("|"):
            cells = [c.strip() for c in line.split("|")[1:-1]]
            if not hasattr(generate_html, "_in_table"):
                generate_html._in_table = False
            if not generate_html._in_table:
                html_lines.append("<table><thead><tr>")
                html_lines.extend(f"<th>{c}</th>" for c in cells)
                html_lines.append("</tr></thead><tbody>")
                generate_html._in_table = True
            else:
                html_lines.append("<tr>")
                for c in cells:
                    cls = ""
                    if c in ("critical",):
                        cls = ' class="critical"'
                    elif c in ("high",):
                        cls = ' class="high"'
                    elif c in ("medium",):
                        cls = ' class="medium"'
                    elif c in ("low",):
                        cls = ' class="low"'
                    html_lines.append(f"<td{cls}>{c}</td>")
                html_lines.append("</tr>")
        else:
            if hasattr(generate_html, "_in_table") and generate_html._in_table:
                html_lines.append("</tbody></table>")
                generate_html._in_table = False
            if line.startswith("---"):
                html_lines.append("<hr>")
            elif line.startswith("*") and line.endswith("*"):
                html_lines.append(f"<p><em>{line.strip('*')}</em></p>")
            elif line and line[0].isdigit() and ". " in line:
                html_lines.append(f"<p>{line}</p>")
            elif line.strip():
                html_lines.append(f"<p>{line}</p>")

    if hasattr(generate_html, "_in_table") and generate_html._in_table:
        html_lines.append("</tbody></table>")
        generate_html._in_table = False

    html_lines.extend(["</body>", "</html>"])
    return "\n".join(html_lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate a weekly security report from jsa-infrasec metrics."
    )
    parser.add_argument(
        "--start",
        default=(datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d"),
        help="Report start date (default: 7 days ago)",
    )
    parser.add_argument(
        "--end",
        default=datetime.now().strftime("%Y-%m-%d"),
        help="Report end date (default: today)",
    )
    parser.add_argument(
        "--format",
        choices=["markdown", "html", "json"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument(
        "--output", "-o",
        default="",
        help="Output file (default: stdout)",
    )
    parser.add_argument(
        "--prometheus",
        default=os.environ.get("PROMETHEUS_URL", "http://localhost:9090"),
        help="Prometheus URL (default: http://localhost:9090 or $PROMETHEUS_URL)",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Generate report with sample data (for demos/sales)",
    )

    args = parser.parse_args()

    # Collect data
    data = None
    if not args.demo:
        print(f"Querying Prometheus at {args.prometheus}...", file=sys.stderr)
        data = collect_metrics(args.prometheus, args.start, args.end)
        if data is None:
            print(
                "WARNING: Could not reach Prometheus — falling back to demo data.",
                file=sys.stderr,
            )
            print(
                "  Use --prometheus URL to specify, or --demo for sample data.",
                file=sys.stderr,
            )

    if data is None:
        data = DEMO_DATA.copy()
        data["period"]["start"] = args.start
        data["period"]["end"] = args.end

    # Generate report
    if args.format == "markdown":
        output = generate_markdown(data)
    elif args.format == "html":
        output = generate_html(data)
    elif args.format == "json":
        output = json.dumps(data, indent=2)
    else:
        output = generate_markdown(data)

    # Write output
    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Report written to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
