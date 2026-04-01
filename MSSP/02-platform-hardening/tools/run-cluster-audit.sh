#!/usr/bin/env bash
# run-cluster-audit.sh
# Live cluster audit — CKS + CKA best practices.
# Runs kubescape, kube-bench, polaris, RBAC audit, and resource cliff check.
# Outputs one markdown report per run.
#
# Usage:
#   bash run-cluster-audit.sh
#   bash run-cluster-audit.sh --output ~/reports/client-audit-$(date +%Y%m%d).md
#   bash run-cluster-audit.sh --skip kubescape --skip kube-bench

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

OUTPUT=""
SKIP_TOOLS=()
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --output FILE      Write report to file (default: ./k8s-audit-DATE.md)"
  echo "  --skip TOOL        Skip a tool: kubescape|kube-bench|polaris|rbac|resources (repeatable)"
  echo "  --help|-h          Show this help"
  echo ""
  echo "Examples:"
  echo "  bash run-cluster-audit.sh"
  echo "  bash run-cluster-audit.sh --output ~/reports/acme-audit-$(date +%Y%m%d).md"
  echo "  bash run-cluster-audit.sh --skip kube-bench"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --skip)   SKIP_TOOLS+=("$2"); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

# Default output: use reports/ dir if it exists (container PVC), otherwise CWD
if [[ -z "$OUTPUT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPORTS_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/reports"
  if [[ -d "$REPORTS_DIR" && -w "$REPORTS_DIR" ]]; then
    OUTPUT="$REPORTS_DIR/k8s-audit-${DATE}.md"
  else
    OUTPUT="./k8s-audit-${DATE}.md"
  fi
fi

should_skip() { local t="$1"; for s in "${SKIP_TOOLS[@]:-}"; do [[ "$s" == "$t" ]] && return 0; done; return 1; }

echo ""
echo -e "${BLUE}=== K8s Cluster Audit ===${NC}"
echo "  Output    : $OUTPUT"
echo "  Skipping  : ${SKIP_TOOLS[*]:-none}"
echo ""

# Verify cluster access
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster. Check kubectl context.${NC}"
  exit 1
fi

CLUSTER_CTX=$(kubectl config current-context 2>/dev/null || echo "unknown")
CLUSTER_VER=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"' 2>/dev/null || echo "unknown")
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
NS_COUNT=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
POD_COUNT=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')

echo -e "${GREEN}Connected:${NC} $CLUSTER_CTX  |  $CLUSTER_VER  |  ${NODE_COUNT} nodes  |  ${NS_COUNT} namespaces  |  ${POD_COUNT} pods"
echo ""

# ── Report header ──────────────────────────────────────────────────────────
REPORT_LINES=()
REPORT_LINES+=("# K8s Cluster Audit Report")
REPORT_LINES+=("Date: $DATE  |  Context: \`$CLUSTER_CTX\`  |  Server: \`$CLUSTER_VER\`")
REPORT_LINES+=("")
REPORT_LINES+=("| | |")
REPORT_LINES+=("|---|---|")
REPORT_LINES+=("| Nodes | $NODE_COUNT |")
REPORT_LINES+=("| Namespaces | $NS_COUNT |")
REPORT_LINES+=("| Pods | $POD_COUNT |")
REPORT_LINES+=("")
REPORT_LINES+=("---")
REPORT_LINES+=("")

# ── 1. Kubescape ───────────────────────────────────────────────────────────
if should_skip "kubescape"; then
  echo -e "${YELLOW}[SKIP]${NC} kubescape"
else
  echo -e "${BLUE}[1/5]${NC} kubescape — NSA/CISA + MITRE ATT&CK risk score"
  REPORT_LINES+=("## 1. Kubescape — Risk Score (NSA/CISA + MITRE ATT&CK)")
  REPORT_LINES+=("")
  if command -v kubescape &>/dev/null; then
    # kubescape v4+ uses JSON output for reliable parsing
    kubescape scan --format json --output /tmp/ks-results.json &>/dev/null || true
    KS_JSON=$(cat /tmp/ks-results.json 2>/dev/null || true)
    KS_SCORE=""
    KS_FAILED_COUNT=""
    KS_PASSED_COUNT=""
    if [[ -n "$KS_JSON" ]]; then
      KS_SCORE=$(echo "$KS_JSON" | jq -r '.summaryDetails.complianceScore // .summaryDetails.score // empty' 2>/dev/null || true)
      KS_FAILED_COUNT=$(echo "$KS_JSON" | jq -r '.summaryDetails.ResourceCounters.failedResources // .summaryDetails.failedResources // empty' 2>/dev/null || true)
      KS_PASSED_COUNT=$(echo "$KS_JSON" | jq -r '.summaryDetails.ResourceCounters.passedResources // .summaryDetails.passedResources // empty' 2>/dev/null || true)
    fi
    # Fallback: try pretty-printer and grep
    if [[ -z "$KS_SCORE" ]]; then
      KS_PRETTY=$(kubescape scan --format pretty-printer 2>/dev/null || true)
      KS_SCORE=$(echo "$KS_PRETTY" | grep -iE "score|compliance" | grep -oP '[\d]+\.?[\d]*%?' | head -1 || true)
      KS_FAILED_COUNT=$(echo "$KS_PRETTY" | grep -iE "failed" | grep -oP '\d+' | head -1 || true)
      KS_PASSED_COUNT=$(echo "$KS_PRETTY" | grep -iE "passed" | grep -oP '\d+' | head -1 || true)
    fi
    if [[ -n "$KS_SCORE" ]]; then
      echo -e "  ${GREEN}✓${NC} Compliance score: $KS_SCORE"
      REPORT_LINES+=("\`\`\`")
      REPORT_LINES+=("Compliance score: $KS_SCORE")
      [[ -n "$KS_FAILED_COUNT" ]] && REPORT_LINES+=("Failed resources: $KS_FAILED_COUNT")
      [[ -n "$KS_PASSED_COUNT" ]] && REPORT_LINES+=("Passed resources: $KS_PASSED_COUNT")
      REPORT_LINES+=("\`\`\`")
    else
      echo -e "  ${YELLOW}⚠${NC} kubescape ran but could not parse score"
      REPORT_LINES+=("kubescape ran — check raw output for score")
    fi
    # Top failing controls from JSON
    KS_TOP_CONTROLS=$(echo "$KS_JSON" | jq -r '
      [.summaryDetails.controls | to_entries[] |
       select(.value.status == "failed") |
       .value.name // .value.controlID // .key] | .[0:10] | .[]' 2>/dev/null || true)
    if [[ -n "$KS_TOP_CONTROLS" ]]; then
      REPORT_LINES+=("")
      REPORT_LINES+=("**Top failing controls:**")
      REPORT_LINES+=("\`\`\`")
      REPORT_LINES+=("$KS_TOP_CONTROLS")
      REPORT_LINES+=("\`\`\`")
    fi
    rm -f /tmp/ks-results.json
  else
    echo -e "  ${YELLOW}⚠${NC} kubescape not installed — install: https://kubescape.io/docs/install/"
    REPORT_LINES+=("**kubescape not installed.** Install: \`curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash\`")
  fi
  REPORT_LINES+=("")
fi

# ── 2. Kube-bench ──────────────────────────────────────────────────────────
if should_skip "kube-bench"; then
  echo -e "${YELLOW}[SKIP]${NC} kube-bench"
else
  echo -e "${BLUE}[2/5]${NC} kube-bench — CIS Kubernetes Benchmark"
  REPORT_LINES+=("## 2. Kube-bench — CIS Benchmark")
  REPORT_LINES+=("")
  # kube-bench must run ON a cluster node — try local first, fall back to K8s Job
  KB_OUT=""
  KB_METHOD=""
  if command -v kube-bench &>/dev/null; then
    KB_OUT=$(kube-bench run 2>/dev/null || true)
    # If local run failed (no config / not on a node), KB_OUT will be empty or error
    if echo "$KB_OUT" | grep -q "^\[PASS\]\|^\[FAIL\]\|^\[WARN\]"; then
      KB_METHOD="local"
    else
      KB_OUT=""
    fi
  fi

  # Fallback: run as a Job inside the cluster
  if [[ -z "$KB_OUT" ]]; then
    echo -e "  ${YELLOW}⚠${NC} kube-bench can't run locally (must run on a cluster node)"
    echo -e "  ${BLUE}→${NC} Running as Kubernetes Job..."
    # kube-bench needs hostPID + hostPath mounts — must run in a privileged namespace.
    # kube-system is privileged by default (no PSS enforcement).
    KB_NS="kube-system"
    # Clean up any previous run
    kubectl delete job kube-bench -n "$KB_NS" --ignore-not-found &>/dev/null || true
    if kubectl apply -n "$KB_NS" -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml &>/dev/null; then
      # Wait for job to complete (up to 90s)
      if kubectl wait --for=condition=complete job/kube-bench -n "$KB_NS" --timeout=90s &>/dev/null 2>&1; then
        KB_OUT=$(kubectl logs job.batch/kube-bench -n "$KB_NS" 2>/dev/null || true)
        KB_METHOD="job"
      else
        echo -e "  ${RED}✗${NC} kube-bench Job did not complete in 90s"
      fi
      # Clean up
      kubectl delete job kube-bench -n "$KB_NS" --ignore-not-found &>/dev/null || true
    else
      echo -e "  ${RED}✗${NC} Could not create kube-bench Job"
    fi
  fi

  if [[ -n "$KB_OUT" ]] && echo "$KB_OUT" | grep -q "^\[PASS\]\|^\[FAIL\]\|^\[WARN\]"; then
    [[ "$KB_METHOD" == "job" ]] && echo -e "  ${GREEN}✓${NC} Results from cluster Job"
    KB_SUMMARY=$(echo "$KB_OUT" | grep -E "^== Summary" -A10 | head -15 || true)
    KB_FAIL_COUNT=$(echo "$KB_OUT" | grep -c "^\[FAIL\]" || echo "0")
    KB_WARN_COUNT=$(echo "$KB_OUT" | grep -c "^\[WARN\]" || echo "0")
    KB_PASS_COUNT=$(echo "$KB_OUT" | grep -c "^\[PASS\]" || echo "0")
    echo -e "  PASS: ${GREEN}$KB_PASS_COUNT${NC}  FAIL: ${RED}$KB_FAIL_COUNT${NC}  WARN: ${YELLOW}$KB_WARN_COUNT${NC}"
    REPORT_LINES+=("| PASS | FAIL | WARN | Method |")
    REPORT_LINES+=("|------|------|------|--------|")
    REPORT_LINES+=("| $KB_PASS_COUNT | $KB_FAIL_COUNT | $KB_WARN_COUNT | $KB_METHOD |")
    REPORT_LINES+=("")
    if [[ -n "$KB_SUMMARY" ]]; then
      REPORT_LINES+=("\`\`\`")
      REPORT_LINES+=("$KB_SUMMARY")
      REPORT_LINES+=("\`\`\`")
    fi
    # Top 10 FAILs
    KB_FAILS=$(echo "$KB_OUT" | grep "^\[FAIL\]" | head -10 || true)
    if [[ -n "$KB_FAILS" ]]; then
      REPORT_LINES+=("")
      REPORT_LINES+=("**Top failures:**")
      REPORT_LINES+=("\`\`\`")
      REPORT_LINES+=("$KB_FAILS")
      REPORT_LINES+=("\`\`\`")
    fi
  else
    echo -e "  ${RED}✗${NC} kube-bench could not produce results (local or Job)"
    REPORT_LINES+=("**kube-bench could not run.** It must execute on a cluster node.")
    REPORT_LINES+=("")
    REPORT_LINES+=("Manual run:")
    REPORT_LINES+=("\`\`\`bash")
    REPORT_LINES+=("# SSH to a node and run directly:")
    REPORT_LINES+=("ssh <node> 'kube-bench run'")
    REPORT_LINES+=("")
    REPORT_LINES+=("# Or run as a Kubernetes Job:")
    REPORT_LINES+=("kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml")
    REPORT_LINES+=("kubectl wait --for=condition=complete job/kube-bench --timeout=90s")
    REPORT_LINES+=("kubectl logs job.batch/kube-bench")
    REPORT_LINES+=("\`\`\`")
  fi
  REPORT_LINES+=("")
fi

# ── 3. Polaris ─────────────────────────────────────────────────────────────
if should_skip "polaris"; then
  echo -e "${YELLOW}[SKIP]${NC} polaris"
else
  echo -e "${BLUE}[3/5]${NC} polaris — best practices score"
  REPORT_LINES+=("## 3. Polaris — Best Practices Score")
  REPORT_LINES+=("")
  if command -v polaris &>/dev/null; then
    # polaris v8+/v9+ — JSON output, parse with jq
    POL_JSON=$(polaris audit --format json 2>/dev/null || true)
    POL_SCORE=""
    if [[ -n "$POL_JSON" ]]; then
      # Try known JSON keys across polaris versions
      POL_SCORE=$(echo "$POL_JSON" | jq -r '.score // .Score // .summary.score // empty' 2>/dev/null || true)
    fi

    if [[ -n "$POL_SCORE" ]]; then
      echo -e "  ${GREEN}✓${NC} Score: $POL_SCORE/100"
      REPORT_LINES+=("\`\`\`")
      REPORT_LINES+=("Score: $POL_SCORE/100")
      REPORT_LINES+=("\`\`\`")
    else
      echo -e "  ${YELLOW}⚠${NC} polaris could not determine score"
      REPORT_LINES+=("polaris ran — could not parse score from JSON output")
    fi

    # Extract failed checks from JSON — polaris v9 structure:
    # .Results[].PodResult.ContainerResults[].Results = { checkName: {Success: bool, Severity: str, Message: str} }
    POL_FAILURES=$(echo "$POL_JSON" | jq -r '
      [.Results[]? |
       .Name as $name | .Namespace as $ns |
       (.PodResult.ContainerResults[]?.Results // {} | to_entries[]) |
       select(.value.Success == false) |
       "\($ns)/\($name): \(.key) (\(.value.Severity // "unknown"))"] |
      unique | .[0:30] | .[]' 2>/dev/null || true)
    if [[ -n "$POL_FAILURES" ]]; then
      REPORT_LINES+=("")
      REPORT_LINES+=("**Failed checks:**")
      REPORT_LINES+=("\`\`\`")
      REPORT_LINES+=("$POL_FAILURES")
      REPORT_LINES+=("\`\`\`")
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} polaris not installed — install: brew install fairwindsops/tap/polaris"
    REPORT_LINES+=("**polaris not installed.** Install: \`brew install fairwindsops/tap/polaris\`")
  fi
  REPORT_LINES+=("")
fi

# ── 4. RBAC audit ──────────────────────────────────────────────────────────
if should_skip "rbac"; then
  echo -e "${YELLOW}[SKIP]${NC} rbac"
else
  echo -e "${BLUE}[4/5]${NC} RBAC — cluster-admin bindings + wildcard roles"
  REPORT_LINES+=("## 4. RBAC Audit")
  REPORT_LINES+=("")

  # Who has cluster-admin
  CA_BINDINGS=$(kubectl get clusterrolebindings -A -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
admins = []
for b in d.get('items', []):
    if b.get('roleRef', {}).get('name') == 'cluster-admin':
        subjects = b.get('subjects', [])
        for s in subjects:
            admins.append(f\"  {b['metadata']['name']}: {s.get('kind','?')}/{s.get('name','?')} (ns:{s.get('namespace','-')})\")
for a in admins:
    print(a)
" 2>/dev/null || echo "  (could not query)")

  CA_COUNT=$(echo "$CA_BINDINGS" | grep -c "^  " || echo "0")
  echo -e "  cluster-admin bindings: ${YELLOW}$CA_COUNT${NC}"
  REPORT_LINES+=("### cluster-admin bindings ($CA_COUNT found)")
  REPORT_LINES+=("")
  REPORT_LINES+=("\`\`\`")
  REPORT_LINES+=("$CA_BINDINGS")
  REPORT_LINES+=("\`\`\`")
  REPORT_LINES+=("")
  [[ "$CA_COUNT" -gt 3 ]] && REPORT_LINES+=("**⚠ >3 cluster-admin bindings is excessive. Review and remove unused ones.**") && REPORT_LINES+=("")

  # Wildcard rules in ClusterRoles
  WILDCARD_ROLES=$(kubectl get clusterroles -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
hits = []
skip = {'system:', 'kubeadm:', 'flannel', 'calico', 'aws-', 'eks:', 'kube-', 'helm-', 'tiller'}
for r in d.get('items', []):
    name = r['metadata']['name']
    if any(name.startswith(s) for s in skip):
        continue
    for rule in r.get('rules', []):
        if '*' in rule.get('verbs', []) or '*' in rule.get('resources', []):
            hits.append(f'  {name}: verbs={rule.get(\"verbs\")} resources={rule.get(\"resources\")}')
            break
for h in hits[:15]:
    print(h)
" 2>/dev/null || echo "  (could not query)")

  WC_COUNT=$(echo "$WILDCARD_ROLES" | grep -c "^  " 2>/dev/null || echo "0")
  echo -e "  wildcard roles: ${YELLOW}$WC_COUNT${NC}"
  if [[ "$WC_COUNT" -gt 0 ]]; then
    REPORT_LINES+=("### Wildcard rules in ClusterRoles ($WC_COUNT found — non-system)")
    REPORT_LINES+=("")
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("$WILDCARD_ROLES")
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("**Fix:** Replace wildcard verbs/resources with explicit permissions. See \`02-hardening/remediation/rbac-templates.yaml\`.")
    REPORT_LINES+=("")
  fi
fi

# ── 5. Resource cliff + pod security ──────────────────────────────────────
if should_skip "resources"; then
  echo -e "${YELLOW}[SKIP]${NC} resources"
else
  echo -e "${BLUE}[5/5]${NC} Resource cliff + pod security quick check"
  REPORT_LINES+=("## 5. Resource Cliff + Pod Security")
  REPORT_LINES+=("")

  # Pods with no resource limits
  NO_LIMITS=$(kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
hits = []
for pod in d.get('items', []):
    ns = pod['metadata']['namespace']
    name = pod['metadata']['name']
    for c in pod['spec'].get('containers', []):
        res = c.get('resources', {})
        if not res.get('limits'):
            hits.append(f'  {ns}/{name} — container: {c[\"name\"]}')
            break
for h in hits[:20]:
    print(h)
extra = len(hits) - 20
if extra > 0:
    print(f'  ... and {extra} more')
print(f'TOTAL_NO_LIMITS:{len(hits)}')
" 2>/dev/null || echo "  (could not query)")

  NL_COUNT=$(echo "$NO_LIMITS" | grep "^TOTAL_NO_LIMITS:" | cut -d: -f2 || echo "?")
  NL_LIST=$(echo "$NO_LIMITS" | grep -v "^TOTAL_NO_LIMITS:" || true)
  echo -e "  pods without resource limits: ${RED}$NL_COUNT${NC}"
  REPORT_LINES+=("### Pods without resource limits ($NL_COUNT)")
  REPORT_LINES+=("")
  if [[ -n "$NL_LIST" && "$NL_COUNT" != "0" ]]; then
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("$NL_LIST")
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("**Fix:** Add \`resources.limits.cpu/memory\` to every container. See \`02-hardening/remediation/pod-security-context.yaml\`.")
    REPORT_LINES+=("**Also:** Apply \`02-hardening/remediation/resource-management.yaml\` — LimitRange sets namespace-wide defaults.")
  else
    REPORT_LINES+=("✅ All pods have resource limits defined.")
  fi
  REPORT_LINES+=("")

  # Pods running as root
  ROOT_PODS=$(kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
hits = []
for pod in d.get('items', []):
    ns = pod['metadata']['namespace']
    name = pod['metadata']['name']
    spec = pod['spec']
    pod_sc = spec.get('securityContext', {})
    for c in spec.get('containers', []):
        c_sc = c.get('securityContext', {})
        run_as_non_root = c_sc.get('runAsNonRoot', pod_sc.get('runAsNonRoot', False))
        run_as_user = c_sc.get('runAsUser', pod_sc.get('runAsUser', None))
        if not run_as_non_root and (run_as_user is None or run_as_user == 0):
            hits.append(f'  {ns}/{name} — {c[\"name\"]}')
            break
for h in hits[:15]:
    print(h)
extra = len(hits) - 15
if extra > 0:
    print(f'  ... and {extra} more')
print(f'TOTAL_ROOT:{len(hits)}')
" 2>/dev/null || echo "  TOTAL_ROOT:?")

  ROOT_COUNT=$(echo "$ROOT_PODS" | grep "^TOTAL_ROOT:" | cut -d: -f2 || echo "?")
  ROOT_LIST=$(echo "$ROOT_PODS" | grep -v "^TOTAL_ROOT:" || true)
  echo -e "  pods potentially running as root: ${YELLOW}$ROOT_COUNT${NC}"
  REPORT_LINES+=("### Pods potentially running as root ($ROOT_COUNT)")
  REPORT_LINES+=("")
  if [[ -n "$ROOT_LIST" && "$ROOT_COUNT" != "0" ]]; then
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("$ROOT_LIST")
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("**Fix:** Add \`runAsNonRoot: true\` + \`runAsUser: 1000\` to securityContext. See \`02-hardening/remediation/pod-security-context.yaml\`.")
  else
    REPORT_LINES+=("✅ All pods have runAsNonRoot set.")
  fi
  REPORT_LINES+=("")

  # Namespaces without network policies
  NS_NO_NP=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | while read ns; do
    count=$(kubectl get networkpolicy -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -eq 0 ]] && echo "  $ns"
  done || true)
  NNP_COUNT=$(echo "$NS_NO_NP" | grep -c "^  " 2>/dev/null || echo "0")
  echo -e "  namespaces without NetworkPolicy: ${YELLOW}$NNP_COUNT${NC}"
  REPORT_LINES+=("### Namespaces without NetworkPolicy ($NNP_COUNT)")
  REPORT_LINES+=("")
  if [[ -n "$NS_NO_NP" && "$NNP_COUNT" -gt 0 ]]; then
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("$NS_NO_NP")
    REPORT_LINES+=("\`\`\`")
    REPORT_LINES+=("**Fix:** Apply default-deny + ingress/egress rules. See \`02-hardening/remediation/network-policies.yaml\`.")
  else
    REPORT_LINES+=("✅ All namespaces have at least one NetworkPolicy.")
  fi
  REPORT_LINES+=("")
fi

# ── Summary ────────────────────────────────────────────────────────────────
REPORT_LINES+=("---")
REPORT_LINES+=("")
REPORT_LINES+=("## Next Steps")
REPORT_LINES+=("")
REPORT_LINES+=("1. **Fix violations** — use \`02-hardening/remediation/\` for copy-paste patches")
REPORT_LINES+=("2. **Wire CI/CD** — \`bash setup-cicd.sh --client-repo <path>\` copies conftest policies to the repo")
REPORT_LINES+=("3. **Deploy admission control** — \`bash deploy-policies.sh --engine kyverno --mode audit\`")
REPORT_LINES+=("4. **Enforce** — \`bash audit-to-enforce.sh --strategy critical-first\` after violations hit zero")
REPORT_LINES+=("5. **Compliance report** — \`python3 policy-coverage-report.py --framework all\`")
REPORT_LINES+=("")
REPORT_LINES+=("*GP-Consulting — K8s Package*")

# ── Write report ───────────────────────────────────────────────────────────
printf '%s\n' "${REPORT_LINES[@]}" > "$OUTPUT"

echo ""
echo -e "${GREEN}=== Done ===${NC}"
echo "  Report: $OUTPUT"
echo ""
