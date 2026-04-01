#!/usr/bin/env bash
# verify-container-hardening.sh
# Verify that container hardening from 01-APP-SEC and 02-CLUSTER-HARDEN
# is actually applied to running containers in the cluster.
#
# This is the "Container" layer of the 4 C's (Cloud, Cluster, Container, Code).
# Hardening is defined in 01-APP-SEC (image level) and 02-CLUSTER-HARDEN
# (security contexts, admission control). This tool verifies it's in place at runtime.
#
# Usage:
#   bash verify-container-hardening.sh
#   bash verify-container-hardening.sh --namespace production
#   bash verify-container-hardening.sh --output /tmp/container-hardening-report.md
#   bash verify-container-hardening.sh --skip-system    # skip kube-system, kube-public, kube-node-lease
#   bash verify-container-hardening.sh --fix-hints       # show remediation commands per violation
#
# Checks (mapped to source package):
#   From 01-APP-SEC:
#     - Image uses :latest tag                    (Dockerfile best practice)
#     - Image uses no tag at all                  (Dockerfile best practice)
#   From 02-CLUSTER-HARDEN:
#     - Container runs as root (UID 0)            (CKV_K8S_6, C-0013)
#     - runAsNonRoot not set                      (CKV_K8S_22, C-0013)
#     - allowPrivilegeEscalation not false        (CKV_K8S_20, C-0016)
#     - Capabilities not dropped                  (CKV_K8S_28, C-0046)
#     - Privileged container                      (CKV_K8S_16, C-0057)
#     - readOnlyRootFilesystem not set            (CKV_K8S_25, C-0017)
#     - No resource limits                        (CKV_K8S_13, C-0009)
#     - No resource requests                      (CKV_K8S_11, C-0009)
#     - No liveness probe                         (CKV_K8S_8)
#     - No readiness probe                        (CKV_K8S_9)
#     - hostNetwork enabled                       (CKV_K8S_19, C-0041)
#     - hostPID enabled                           (CKV_K8S_17, C-0038)
#     - No seccomp profile                        (C-0055)
#   Namespace level:
#     - No NetworkPolicy in namespace
#     - No PSA labels on namespace

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

NAMESPACE=""
OUTPUT=""
SKIP_SYSTEM=false
FIX_HINTS=false
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --namespace NS    Only check a specific namespace (default: all)"
  echo "  --output FILE     Write report to file (default: stdout + ./container-hardening-DATE.md)"
  echo "  --skip-system     Skip kube-system, kube-public, kube-node-lease, local-path-storage"
  echo "  --fix-hints       Show remediation commands for each violation type"
  echo "  --help|-h         Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)  NAMESPACE="$2"; shift 2 ;;
    --output)     OUTPUT="$2"; shift 2 ;;
    --skip-system) SKIP_SYSTEM=true; shift ;;
    --fix-hints)  FIX_HINTS=true; shift ;;
    --help|-h)    usage; exit 0 ;;
    *)            echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPORTS_DIR="$(dirname "$SCRIPT_DIR")/reports"
  if [[ -d "$REPORTS_DIR" && -w "$REPORTS_DIR" ]]; then
    OUTPUT="$REPORTS_DIR/container-hardening-${DATE}.md"
  else
    OUTPUT="./container-hardening-${DATE}.md"
  fi
fi

# Verify cluster access
if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster. Check kubectl context.${NC}"
  exit 1
fi

CLUSTER_CTX=$(kubectl config current-context 2>/dev/null || echo "unknown")
CLUSTER_VER=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion // "unknown"' 2>/dev/null || echo "unknown")

echo ""
echo -e "${BLUE}=== Container Hardening Verification ===${NC}"
echo "  Cluster : $CLUSTER_CTX ($CLUSTER_VER)"
echo "  Output  : $OUTPUT"
[[ -n "$NAMESPACE" ]] && echo "  Scope   : namespace/$NAMESPACE" || echo "  Scope   : all namespaces"
$SKIP_SYSTEM && echo "  Skipping: kube-system, kube-public, kube-node-lease, local-path-storage"
echo ""

# Build namespace selector
NS_ARGS="-A"
if [[ -n "$NAMESPACE" ]]; then
  NS_ARGS="-n $NAMESPACE"
fi

SYSTEM_NS=("kube-system" "kube-public" "kube-node-lease" "local-path-storage")

# Get all pods as JSON
PODS_JSON=$(kubectl get pods $NS_ARGS -o json 2>/dev/null)

# Run the full audit via Python for reliable JSON parsing
AUDIT_RESULT=$(echo "$PODS_JSON" | python3 -c "
import json, sys

data = json.load(sys.stdin)
skip_system = $( $SKIP_SYSTEM && echo 'True' || echo 'False' )
system_ns = set(['kube-system', 'kube-public', 'kube-node-lease', 'local-path-storage'])

# Counters
total_pods = 0
total_containers = 0
violations = {
    'latest_tag': [],
    'no_tag': [],
    'run_as_root': [],
    'no_run_as_nonroot': [],
    'allow_priv_esc': [],
    'no_drop_caps': [],
    'privileged': [],
    'no_readonly_rootfs': [],
    'no_resource_limits': [],
    'no_resource_requests': [],
    'no_liveness_probe': [],
    'no_readiness_probe': [],
    'host_network': [],
    'host_pid': [],
    'no_seccomp': [],
}

ns_pods = {}  # track pods per namespace for network policy check

for pod in data.get('items', []):
    ns = pod['metadata']['namespace']
    name = pod['metadata']['name']

    if skip_system and ns in system_ns:
        continue

    total_pods += 1
    ns_pods.setdefault(ns, []).append(name)
    spec = pod['spec']
    pod_sc = spec.get('securityContext', {})

    # Host-level checks (pod level)
    if spec.get('hostNetwork', False):
        violations['host_network'].append(f'{ns}/{name}')
    if spec.get('hostPID', False):
        violations['host_pid'].append(f'{ns}/{name}')

    # Seccomp at pod level
    pod_has_seccomp = 'seccompProfile' in pod_sc

    for c in spec.get('containers', []):
        total_containers += 1
        c_name = c['name']
        c_sc = c.get('securityContext', {})
        ident = f'{ns}/{name}/{c_name}'

        # Image tag checks (from 01-APP-SEC)
        image = c.get('image', '')
        if ':latest' in image:
            violations['latest_tag'].append(ident)
        elif ':' not in image or image.endswith(':'):
            violations['no_tag'].append(ident)

        # runAsUser / runAsNonRoot
        run_as_user = c_sc.get('runAsUser', pod_sc.get('runAsUser', None))
        run_as_nonroot = c_sc.get('runAsNonRoot', pod_sc.get('runAsNonRoot', None))

        if run_as_user is not None and run_as_user == 0:
            violations['run_as_root'].append(ident)
        if not run_as_nonroot:
            violations['no_run_as_nonroot'].append(ident)

        # allowPrivilegeEscalation
        ape = c_sc.get('allowPrivilegeEscalation', None)
        if ape is None or ape is True:
            violations['allow_priv_esc'].append(ident)

        # Capabilities
        caps = c_sc.get('capabilities', {})
        drop = caps.get('drop', [])
        if 'ALL' not in [str(d).upper() for d in drop]:
            violations['no_drop_caps'].append(ident)

        # Privileged
        if c_sc.get('privileged', False):
            violations['privileged'].append(ident)

        # readOnlyRootFilesystem
        if not c_sc.get('readOnlyRootFilesystem', False):
            violations['no_readonly_rootfs'].append(ident)

        # Resource limits/requests
        resources = c.get('resources', {})
        if not resources.get('limits'):
            violations['no_resource_limits'].append(ident)
        if not resources.get('requests'):
            violations['no_resource_requests'].append(ident)

        # Probes
        if not c.get('livenessProbe'):
            violations['no_liveness_probe'].append(ident)
        if not c.get('readinessProbe'):
            violations['no_readiness_probe'].append(ident)

        # Seccomp (container or pod level)
        c_has_seccomp = 'seccompProfile' in c_sc
        if not c_has_seccomp and not pod_has_seccomp:
            violations['no_seccomp'].append(ident)

# Output as JSON for the shell to parse
result = {
    'total_pods': total_pods,
    'total_containers': total_containers,
    'violations': {k: {'count': len(v), 'items': v[:10], 'overflow': max(0, len(v) - 10)} for k, v in violations.items()},
    'namespaces': list(ns_pods.keys()),
}
print(json.dumps(result))
" 2>/dev/null)

if [[ -z "$AUDIT_RESULT" ]]; then
  echo -e "${RED}ERROR: Failed to audit pods. Check cluster access.${NC}"
  exit 1
fi

TOTAL_PODS=$(echo "$AUDIT_RESULT" | jq -r '.total_pods')
TOTAL_CONTAINERS=$(echo "$AUDIT_RESULT" | jq -r '.total_containers')

echo -e "${CYAN}Scanned: $TOTAL_PODS pods, $TOTAL_CONTAINERS containers${NC}"
echo ""

# Check namespace-level controls
NS_LIST=$(echo "$AUDIT_RESULT" | jq -r '.namespaces[]' 2>/dev/null)
NS_NO_NP=()
NS_NO_PSA=()

for ns in $NS_LIST; do
  # NetworkPolicy check
  np_count=$(kubectl get networkpolicy -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$np_count" -eq 0 ]]; then
    NS_NO_NP+=("$ns")
  fi
  # PSA label check
  psa_label=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
  if [[ -z "$psa_label" ]]; then
    NS_NO_PSA+=("$ns")
  fi
done

# Display results
print_check() {
  local key="$1"
  local label="$2"
  local source="$3"
  local severity="$4"
  local count
  count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")

  if [[ "$count" -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC}  $label"
  elif [[ "$severity" == "CRITICAL" ]]; then
    echo -e "  ${RED}FAIL${NC}  $label — ${RED}$count violations${NC}  [$source]"
  elif [[ "$severity" == "HIGH" ]]; then
    echo -e "  ${RED}FAIL${NC}  $label — ${YELLOW}$count violations${NC}  [$source]"
  else
    echo -e "  ${YELLOW}WARN${NC}  $label — $count violations  [$source]"
  fi
}

echo -e "${BLUE}--- Image Security (from 01-APP-SEC) ---${NC}"
print_check "latest_tag"    "No :latest tags"          "01-APP-SEC" "HIGH"
print_check "no_tag"        "All images have tags"     "01-APP-SEC" "HIGH"
echo ""

echo -e "${BLUE}--- Container Security Context (from 02-CLUSTER-HARDEN) ---${NC}"
print_check "privileged"         "No privileged containers"          "02-CLUSTER" "CRITICAL"
print_check "run_as_root"        "No containers running as UID 0"   "02-CLUSTER" "CRITICAL"
print_check "no_run_as_nonroot"  "runAsNonRoot: true set"           "02-CLUSTER" "HIGH"
print_check "allow_priv_esc"     "allowPrivilegeEscalation: false"  "02-CLUSTER" "HIGH"
print_check "no_drop_caps"       "capabilities.drop: [ALL]"        "02-CLUSTER" "HIGH"
print_check "no_readonly_rootfs" "readOnlyRootFilesystem: true"    "02-CLUSTER" "MEDIUM"
print_check "no_seccomp"         "seccomp profile set"             "02-CLUSTER" "MEDIUM"
print_check "host_network"       "No hostNetwork"                  "02-CLUSTER" "CRITICAL"
print_check "host_pid"           "No hostPID"                      "02-CLUSTER" "CRITICAL"
echo ""

echo -e "${BLUE}--- Resource & Availability (from 02-CLUSTER-HARDEN) ---${NC}"
print_check "no_resource_limits"   "Resource limits defined"       "02-CLUSTER" "HIGH"
print_check "no_resource_requests" "Resource requests defined"     "02-CLUSTER" "MEDIUM"
print_check "no_liveness_probe"    "Liveness probes defined"       "02-CLUSTER" "MEDIUM"
print_check "no_readiness_probe"   "Readiness probes defined"      "02-CLUSTER" "MEDIUM"
echo ""

echo -e "${BLUE}--- Namespace Controls ---${NC}"
if [[ ${#NS_NO_NP[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}PASS${NC}  All namespaces have NetworkPolicy"
else
  echo -e "  ${RED}FAIL${NC}  Namespaces without NetworkPolicy — ${YELLOW}${#NS_NO_NP[@]}${NC}  [02-CLUSTER]"
  for ns in "${NS_NO_NP[@]}"; do
    echo -e "        - $ns"
  done
fi

if [[ ${#NS_NO_PSA[@]} -eq 0 ]]; then
  echo -e "  ${GREEN}PASS${NC}  All namespaces have PSA enforce labels"
else
  echo -e "  ${YELLOW}WARN${NC}  Namespaces without PSA enforce label — ${#NS_NO_PSA[@]}  [02-CLUSTER]"
  for ns in "${NS_NO_PSA[@]}"; do
    echo -e "        - $ns"
  done
fi
echo ""

# Score
TOTAL_CHECKS=15
PASS_COUNT=0
for key in latest_tag no_tag privileged run_as_root no_run_as_nonroot allow_priv_esc no_drop_caps no_readonly_rootfs no_seccomp host_network host_pid no_resource_limits no_resource_requests no_liveness_probe no_readiness_probe; do
  count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")
  [[ "$count" -eq 0 ]] && PASS_COUNT=$((PASS_COUNT + 1))
done

SCORE=$(( (PASS_COUNT * 100) / TOTAL_CHECKS ))

if [[ $SCORE -ge 90 ]]; then
  echo -e "${GREEN}Container Hardening Score: ${SCORE}% ($PASS_COUNT/$TOTAL_CHECKS checks passing)${NC}"
elif [[ $SCORE -ge 60 ]]; then
  echo -e "${YELLOW}Container Hardening Score: ${SCORE}% ($PASS_COUNT/$TOTAL_CHECKS checks passing)${NC}"
else
  echo -e "${RED}Container Hardening Score: ${SCORE}% ($PASS_COUNT/$TOTAL_CHECKS checks passing)${NC}"
fi
echo ""

# Fix hints
if $FIX_HINTS; then
  echo -e "${BLUE}=== Remediation Hints ===${NC}"
  echo ""

  for key in privileged run_as_root no_run_as_nonroot allow_priv_esc no_drop_caps no_readonly_rootfs no_seccomp host_network host_pid no_resource_limits latest_tag; do
    count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")
    [[ "$count" -eq 0 ]] && continue

    case "$key" in
      latest_tag)
        echo -e "  ${YELLOW}:latest tags ($count):${NC}"
        echo "    Pin images to a specific semver tag (e.g., nginx:1.25.3)"
        echo "    Fixer: bash 01-APP-SEC/fixers/dockerfile/fix-cmd-format.sh"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/disallow-latest-tag.yaml"
        ;;
      privileged)
        echo -e "  ${RED}Privileged containers ($count):${NC}"
        echo "    Remove privileged: true from securityContext"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/disallow-privileged.yaml"
        ;;
      run_as_root|no_run_as_nonroot)
        echo -e "  ${RED}Root / no runAsNonRoot ($count):${NC}"
        echo "    Fixer: bash 02-CLUSTER-HARDEN/fixers/add-security-context.sh <manifest>"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/require-run-as-nonroot.yaml"
        ;;
      allow_priv_esc)
        echo -e "  ${YELLOW}allowPrivilegeEscalation not disabled ($count):${NC}"
        echo "    Fixer: bash 02-CLUSTER-HARDEN/fixers/add-security-context.sh <manifest>"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/disallow-privilege-escalation.yaml"
        ;;
      no_drop_caps)
        echo -e "  ${YELLOW}Capabilities not dropped ($count):${NC}"
        echo "    Add capabilities.drop: [ALL] to container securityContext"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/require-drop-all-capabilities.yaml"
        ;;
      no_readonly_rootfs)
        echo -e "  ${YELLOW}readOnlyRootFilesystem not set ($count):${NC}"
        echo "    Add readOnlyRootFilesystem: true + emptyDir for /tmp"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/require-readonly-rootfs.yaml"
        ;;
      no_seccomp)
        echo -e "  ${YELLOW}No seccomp profile ($count):${NC}"
        echo "    Add seccompProfile.type: RuntimeDefault at pod or container level"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/require-seccomp-strict.yaml"
        ;;
      host_network)
        echo -e "  ${RED}hostNetwork enabled ($count):${NC}"
        echo "    Remove hostNetwork: true from pod spec"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/disallow-host-namespaces.yaml"
        ;;
      host_pid)
        echo -e "  ${RED}hostPID enabled ($count):${NC}"
        echo "    Remove hostPID: true from pod spec"
        echo "    Policy: 02-CLUSTER-HARDEN/templates/policies/kyverno/disallow-host-namespaces.yaml"
        ;;
      no_resource_limits)
        echo -e "  ${YELLOW}No resource limits ($count):${NC}"
        echo "    Fixer: bash 02-CLUSTER-HARDEN/fixers/add-resource-limits.sh <manifest>"
        echo "    Template: 02-CLUSTER-HARDEN/templates/remediation/resource-management.yaml"
        ;;
    esac
    echo ""
  done
fi

# Write markdown report
REPORT_LINES=()
REPORT_LINES+=("# Container Hardening Verification Report")
REPORT_LINES+=("")
REPORT_LINES+=("Date: $DATE | Cluster: \`$CLUSTER_CTX\` | Server: \`$CLUSTER_VER\`")
REPORT_LINES+=("Scope: $TOTAL_PODS pods, $TOTAL_CONTAINERS containers")
REPORT_LINES+=("")
REPORT_LINES+=("**Hardening Score: ${SCORE}% ($PASS_COUNT/$TOTAL_CHECKS checks passing)**")
REPORT_LINES+=("")
REPORT_LINES+=("---")
REPORT_LINES+=("")
REPORT_LINES+=("## Why This Exists")
REPORT_LINES+=("")
REPORT_LINES+=("Container security is the 3rd layer of the 4 C's (Cloud, Cluster, **Container**, Code).")
REPORT_LINES+=("Hardening is *defined* in two places:")
REPORT_LINES+=("- **01-APP-SEC** -- image-level (Dockerfile best practices, image scanning)")
REPORT_LINES+=("- **02-CLUSTER-HARDEN** -- runtime constraints (security contexts, admission control)")
REPORT_LINES+=("")
REPORT_LINES+=("This tool *verifies* that hardening is actually applied to running containers.")
REPORT_LINES+=("It bridges the gap between policy (what should be true) and reality (what is true).")
REPORT_LINES+=("")
REPORT_LINES+=("---")
REPORT_LINES+=("")
REPORT_LINES+=("## Results")
REPORT_LINES+=("")
REPORT_LINES+=("### Image Security (01-APP-SEC)")
REPORT_LINES+=("")
REPORT_LINES+=("| Check | Status | Count |")
REPORT_LINES+=("|-------|--------|-------|")

for key in latest_tag no_tag; do
  count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")
  label=""
  case "$key" in
    latest_tag) label="No :latest tags" ;;
    no_tag)     label="All images tagged" ;;
  esac
  if [[ "$count" -eq 0 ]]; then
    REPORT_LINES+=("| $label | PASS | 0 |")
  else
    REPORT_LINES+=("| $label | **FAIL** | $count |")
  fi
done

REPORT_LINES+=("")
REPORT_LINES+=("### Container Security Context (02-CLUSTER-HARDEN)")
REPORT_LINES+=("")
REPORT_LINES+=("| Check | Status | Count | Severity |")
REPORT_LINES+=("|-------|--------|-------|----------|")

for key in privileged run_as_root no_run_as_nonroot allow_priv_esc no_drop_caps no_readonly_rootfs no_seccomp host_network host_pid; do
  count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")
  label="" sev=""
  case "$key" in
    privileged)         label="No privileged"; sev="CRITICAL" ;;
    run_as_root)        label="No UID 0"; sev="CRITICAL" ;;
    no_run_as_nonroot)  label="runAsNonRoot set"; sev="HIGH" ;;
    allow_priv_esc)     label="Priv esc disabled"; sev="HIGH" ;;
    no_drop_caps)       label="Caps dropped"; sev="HIGH" ;;
    no_readonly_rootfs) label="Read-only rootfs"; sev="MEDIUM" ;;
    no_seccomp)         label="Seccomp profile"; sev="MEDIUM" ;;
    host_network)       label="No hostNetwork"; sev="CRITICAL" ;;
    host_pid)           label="No hostPID"; sev="CRITICAL" ;;
  esac
  if [[ "$count" -eq 0 ]]; then
    REPORT_LINES+=("| $label | PASS | 0 | $sev |")
  else
    REPORT_LINES+=("| $label | **FAIL** | $count | $sev |")
  fi
done

REPORT_LINES+=("")
REPORT_LINES+=("### Resource & Availability (02-CLUSTER-HARDEN)")
REPORT_LINES+=("")
REPORT_LINES+=("| Check | Status | Count |")
REPORT_LINES+=("|-------|--------|-------|")

for key in no_resource_limits no_resource_requests no_liveness_probe no_readiness_probe; do
  count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")
  label=""
  case "$key" in
    no_resource_limits)   label="Resource limits" ;;
    no_resource_requests) label="Resource requests" ;;
    no_liveness_probe)    label="Liveness probes" ;;
    no_readiness_probe)   label="Readiness probes" ;;
  esac
  if [[ "$count" -eq 0 ]]; then
    REPORT_LINES+=("| $label | PASS | 0 |")
  else
    REPORT_LINES+=("| $label | **FAIL** | $count |")
  fi
done

REPORT_LINES+=("")
REPORT_LINES+=("### Namespace Controls")
REPORT_LINES+=("")

if [[ ${#NS_NO_NP[@]} -eq 0 ]]; then
  REPORT_LINES+=("- NetworkPolicy: PASS (all namespaces covered)")
else
  REPORT_LINES+=("- NetworkPolicy: **FAIL** (${#NS_NO_NP[@]} namespaces without NetworkPolicy)")
  for ns in "${NS_NO_NP[@]}"; do
    REPORT_LINES+=("  - \`$ns\`")
  done
fi

if [[ ${#NS_NO_PSA[@]} -eq 0 ]]; then
  REPORT_LINES+=("- PSA Labels: PASS (all namespaces have enforce labels)")
else
  REPORT_LINES+=("- PSA Labels: WARN (${#NS_NO_PSA[@]} namespaces without PSA enforce label)")
  for ns in "${NS_NO_PSA[@]}"; do
    REPORT_LINES+=("  - \`$ns\`")
  done
fi

REPORT_LINES+=("")
REPORT_LINES+=("### Violation Details")
REPORT_LINES+=("")

for key in privileged run_as_root host_network host_pid latest_tag no_run_as_nonroot allow_priv_esc no_drop_caps no_readonly_rootfs no_seccomp no_resource_limits; do
  count=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.count")
  [[ "$count" -eq 0 ]] && continue

  REPORT_LINES+=("#### $key ($count)")
  REPORT_LINES+=("")
  REPORT_LINES+=("\`\`\`")
  items=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.items[]" 2>/dev/null)
  REPORT_LINES+=("$items")
  overflow=$(echo "$AUDIT_RESULT" | jq -r ".violations.${key}.overflow")
  [[ "$overflow" -gt 0 ]] && REPORT_LINES+=("... and $overflow more")
  REPORT_LINES+=("\`\`\`")
  REPORT_LINES+=("")
done

REPORT_LINES+=("---")
REPORT_LINES+=("")
REPORT_LINES+=("## Next Steps")
REPORT_LINES+=("")
REPORT_LINES+=("1. **Fix CRITICAL violations first** -- privileged, hostNetwork, hostPID, running as root")
REPORT_LINES+=("2. **Apply security contexts** -- \`bash 02-CLUSTER-HARDEN/fixers/add-security-context.sh <manifest>\`")
REPORT_LINES+=("3. **Deploy admission control** -- \`bash 02-CLUSTER-HARDEN/tools/deploy-policies.sh --engine kyverno --mode audit\`")
REPORT_LINES+=("4. **Re-run this verifier** -- \`bash 03-RUNTIME-SECURITY/tools/verify-container-hardening.sh\`")
REPORT_LINES+=("5. **Target: 100% score** before enabling 03-RUNTIME-SECURITY auto-fix")
REPORT_LINES+=("")
REPORT_LINES+=("*GP-Consulting -- Container Hardening Verification*")

printf '%s\n' "${REPORT_LINES[@]}" > "$OUTPUT"

echo -e "${GREEN}=== Done ===${NC}"
echo "  Report: $OUTPUT"
echo ""
