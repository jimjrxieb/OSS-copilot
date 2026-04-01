#!/usr/bin/env bash
# generate-fix-report.sh
# Query live cluster PolicyReports and generate an actionable fix guide.
#
# Usage:
#   bash generate-fix-report.sh
#   bash generate-fix-report.sh --namespace production --top 10
#   bash generate-fix-report.sh --output /tmp/report.md

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

NAMESPACE="all"
TOP=20
OUTPUT=""
DATE=$(date +%Y-%m-%d)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --namespace NS     Namespace to query (default: all)"
  echo "  --top N            Show top N violations (default: 20)"
  echo "  --output FILE      Write report to file (default: ./violation-report-DATE.md)"
  echo ""
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --top) TOP="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

OUTPUT="${OUTPUT:-./violation-report-${DATE}.md}"

echo ""
echo -e "${BLUE}=== Ghost Protocol — Policy Violation Fix Report ===${NC}"
echo "  Namespace : $NAMESPACE"
echo "  Top       : $TOP"
echo "  Output    : $OUTPUT"
echo ""

if ! kubectl get nodes &>/dev/null; then
  echo -e "${RED}ERROR: Cannot connect to cluster.${NC}"
  exit 1
fi

# Collect violations from PolicyReports
echo -e "${BLUE}Querying PolicyReports...${NC}"

NS_FLAG="-A"
[[ "$NAMESPACE" != "all" ]] && NS_FLAG="-n $NAMESPACE"

POLR_TMP=$(mktemp /tmp/polr-XXXXXX.json)
kubectl get polr $NS_FLAG -o json > "$POLR_TMP" 2>/dev/null || echo '{"items":[]}' > "$POLR_TMP"

python3 - "$POLR_TMP" "$TOP" "$NAMESPACE" "$OUTPUT" <<'PYEOF'
import json, sys, os
from datetime import datetime
from collections import defaultdict

polr_file, top_str, namespace, output_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(polr_file) as f:
    data = json.load(f)
items = data.get("items", [])

violations = []
for report in items:
    ns = report.get("metadata", {}).get("namespace", "unknown")
    for result in report.get("results", []):
        if result.get("result") in ("fail", "warn"):
            violations.append({
                "namespace": ns,
                "policy": result.get("policy", "unknown"),
                "rule": result.get("rule", ""),
                "resource": result.get("resources", [{}])[0].get("name", "unknown") if result.get("resources") else "unknown",
                "kind": result.get("resources", [{}])[0].get("kind", "unknown") if result.get("resources") else "unknown",
                "severity": result.get("properties", {}).get("severity", "medium"),
                "message": result.get("message", ""),
                "result": result.get("result", "fail"),
            })

# Group by policy
by_policy = defaultdict(list)
for v in violations:
    by_policy[v["policy"]].append(v)

# Sort by count desc
sorted_policies = sorted(by_policy.items(), key=lambda x: len(x[1]), reverse=True)

# Remediation hints
FIXER_MAP = {
    "disallow-privileged":           "Remove `privileged: true` from securityContext",
    "disallow-privilege-escalation": "Add `allowPrivilegeEscalation: false` to securityContext",
    "require-run-as-nonroot":        "Add `runAsNonRoot: true` and `runAsUser: 1000` to securityContext",
    "require-resource-limits":       "Add `resources.limits.cpu` and `resources.limits.memory`",
    "disallow-latest-tag":           "Pin image tag (e.g., nginx:1.25.3 instead of nginx:latest)",
    "disallow-host-namespaces":      "Remove `hostNetwork`, `hostPID`, `hostIPC` from pod spec",
    "require-seccomp-strict":        "Add `seccompProfile: {type: RuntimeDefault}` to securityContext",
    "require-apparmor-profile":      "Add annotation `container.apparmor.security.beta.kubernetes.io/<name>: runtime/default`",
    "require-drop-all-capabilities": "Add `capabilities: {drop: [ALL]}` to securityContext",
    "require-readonly-rootfs":       "Add `readOnlyRootFilesystem: true` to securityContext",
    "require-pss-labels":            "Add label `pod-security.kubernetes.io/enforce: baseline` to namespace",
}

total = len(violations)
top_n = int(top_str)

lines = []
lines += [
    f"# Policy Violation Fix Report",
    f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
    f"Namespace: `{namespace}`",
    "",
    f"**{total} total violations** across {len(by_policy)} policies",
    "",
    "## Summary",
    "",
    "| Rank | Policy | Violations | Fix |",
    "|------|--------|-----------|-----|",
]

for i, (policy, vs) in enumerate(sorted_policies[:top_n], 1):
    fix = FIXER_MAP.get(policy, f"See 02-hardening/remediation/ for `{policy}`")
    lines.append(f"| {i} | `{policy}` | {len(vs)} | {fix} |")

lines += ["", "---", ""]

for policy, vs in sorted_policies[:top_n]:
    lines += [
        f"## {policy} ({len(vs)} violations)",
        "",
    ]

    fix = FIXER_MAP.get(policy, None)
    if fix:
        lines += [f"> **Fix:** {fix}", ""]

    # Remediation template reference
    tmpl_map = {
        "require-run-as-nonroot":        "pod-security-context.yaml",
        "disallow-privileged":           "pod-security-context.yaml",
        "require-resource-limits":       "pod-security-context.yaml",
        "disallow-host-namespaces":      "pod-security-context.yaml",
        "require-seccomp-strict":        "seccomp-profiles.yaml",
        "require-apparmor-profile":      "apparmor-profiles.yaml",
        "require-pss-labels":            "pss-namespace-labels.yaml",
        "require-drop-all-capabilities": "pod-security-context.yaml",
    }
    tmpl = tmpl_map.get(policy)
    if tmpl:
        lines += [f"Reference: `02-hardening/remediation/{tmpl}`", ""]

    lines += [
        "| Namespace | Kind | Resource | Message |",
        "|-----------|------|----------|---------|",
    ]
    for v in vs[:10]:
        msg = v["message"][:60].replace("|", "\\|") if v["message"] else ""
        lines.append(f"| {v['namespace']} | {v['kind']} | {v['resource']} | {msg} |")
    if len(vs) > 10:
        lines.append(f"| ... | ... | ... | +{len(vs)-10} more |")
    lines.append("")

lines += [
    "---",
    "",
    "## Next Steps",
    "",
    "1. Fix violations top-to-bottom (highest count first)",
    "2. Reference `02-hardening/remediation/` for YAML patches",
    "3. Re-check: `kubectl get polr -A`",
    "4. When violations = 0, run `audit-to-enforce.sh` to harden enforcement",
    "",
    "*Ghost Protocol — CKS Policy Package*",
]

report = "\n".join(lines)
with open(output_file, "w") as f:
    f.write(report)

print(f"  Total violations : {total}")
print(f"  Policies hit     : {len(by_policy)}")
print(f"  Report written   : {output_file}")
PYEOF

rm -f "$POLR_TMP"

echo ""
echo -e "${GREEN}Done. Open $OUTPUT for the full fix guide.${NC}"
echo ""
