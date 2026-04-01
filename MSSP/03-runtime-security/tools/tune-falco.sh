#!/usr/bin/env bash
# tune-falco.sh
# Add Falco rule allowlists to reduce false positives.
# Run after 1 week of baseline telemetry collection.
#
# Usage:
#   bash tune-falco.sh --show-top                              # show top noisy rules
#   bash tune-falco.sh --add-allowlist 01-detection/falco-rules/allowlist.yaml
#   bash tune-falco.sh --add-allowlist 01-detection/falco-rules/allowlist.yaml --dry-run

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"

ACTION=""
ALLOWLIST_FILE=""
DRY_RUN=false
NAMESPACE_FALCO="falco"

usage() {
  echo "Usage: $0 [ACTION] [OPTIONS]"
  echo ""
  echo "Actions:"
  echo "  --show-top                 Show top 10 noisiest Falco rules from logs"
  echo "  --add-allowlist FILE       Add a Falco allowlist rules file"
  echo "  --list-rules               List currently loaded custom rules"
  echo ""
  echo "Options:"
  echo "  --dry-run                  Show what would change, don't apply"
  echo "  --namespace NS             Falco namespace (default: falco)"
  echo ""
  echo "Examples:"
  echo "  bash tune-falco.sh --show-top"
  echo "  bash tune-falco.sh --add-allowlist 01-detection/falco-rules/allowlist.yaml"
  echo "  bash tune-falco.sh --add-allowlist 01-detection/falco-rules/allowlist.yaml --dry-run"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show-top)       ACTION="show-top"; shift ;;
    --add-allowlist)  ACTION="add-allowlist"; ALLOWLIST_FILE="$2"; shift 2 ;;
    --list-rules)     ACTION="list-rules"; shift ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --namespace)      NAMESPACE_FALCO="$2"; shift 2 ;;
    --help|-h)        usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  usage; exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
  echo -e "${RED}ERROR: Cannot reach cluster${NC}"; exit 1
fi

echo ""
echo -e "${BLUE}=== Falco Tuning ===${NC}"
echo ""

# ── Show top noisy rules ───────────────────────────────────────────────────
if [[ "$ACTION" == "show-top" ]]; then
  echo -e "${BLUE}Top 10 noisy Falco rules (last 1000 log lines):${NC}"
  echo ""

  FALCO_POD=$(kubectl get pods -n "$NAMESPACE_FALCO" -l app.kubernetes.io/name=falco \
    --no-headers 2>/dev/null | awk '{print $1}' | head -1 || echo "")

  if [[ -z "$FALCO_POD" ]]; then
    echo -e "${RED}No Falco pods found in namespace $NAMESPACE_FALCO${NC}"
    echo "Run: bash tools/deploy.sh"
    exit 1
  fi

  echo "  From pod: $FALCO_POD"
  echo ""

  kubectl logs -n "$NAMESPACE_FALCO" "$FALCO_POD" --tail=1000 2>/dev/null | \
    python3 -c "
import sys, json
from collections import Counter
counts = Counter()
for line in sys.stdin:
    line = line.strip()
    try:
        d = json.loads(line)
        rule = d.get('rule', '')
        if rule:
            counts[rule] += 1
    except:
        # Non-JSON line
        if 'output' in line and ':' in line:
            try:
                rule = line.split('output:')[1].strip().split('(')[0].strip()[:60]
                counts[rule] += 1
            except:
                pass

print(f'  {\"Count\":>6}  Rule')
print(f'  {\"-\"*6}  {\"-\"*50}')
for rule, count in counts.most_common(10):
    print(f'  {count:>6}  {rule}')
print()
print('  To suppress a rule, add it to 01-detection/falco-rules/allowlist.yaml')
print('  Then run: bash tools/tune-falco.sh --add-allowlist 01-detection/falco-rules/allowlist.yaml')
" 2>/dev/null || echo "  (could not parse Falco logs — check: kubectl logs -n $NAMESPACE_FALCO $FALCO_POD)"
fi

# ── Add allowlist ──────────────────────────────────────────────────────────
if [[ "$ACTION" == "add-allowlist" ]]; then
  if [[ -z "$ALLOWLIST_FILE" ]]; then
    echo -e "${RED}ERROR: --add-allowlist requires a file path${NC}"
    exit 1
  fi

  # Resolve relative path from PKG_DIR
  if [[ ! -f "$ALLOWLIST_FILE" ]]; then
    ALLOWLIST_FILE="$PKG_DIR/$ALLOWLIST_FILE"
  fi

  if [[ ! -f "$ALLOWLIST_FILE" ]]; then
    echo -e "${RED}ERROR: Allowlist file not found: $ALLOWLIST_FILE${NC}"
    echo ""
    echo "Available rule files:"
    ls "$PKG_DIR/01-detection/falco-rules/"*.yaml 2>/dev/null | sed 's|.*/||' | sed 's/^/  /'
    exit 1
  fi

  RULE_NAME=$(basename "$ALLOWLIST_FILE" .yaml)
  echo -e "  Allowlist : $ALLOWLIST_FILE"
  echo -e "  Rule name : $RULE_NAME"
  echo ""

  # Validate YAML
  if command -v python3 &>/dev/null; then
    python3 -c "import yaml; yaml.safe_load(open('$ALLOWLIST_FILE'))" 2>/dev/null \
      && echo -e "  ${GREEN}✓${NC}  YAML valid" \
      || { echo -e "  ${RED}✗${NC}  Invalid YAML in $ALLOWLIST_FILE"; exit 1; }
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} would run:"
    echo "    helm upgrade falco falcosecurity/falco \\"
    echo "      --namespace $NAMESPACE_FALCO \\"
    echo "      --reuse-values \\"
    echo "      --set-file customRules.$RULE_NAME=$ALLOWLIST_FILE"
  else
    if ! command -v helm &>/dev/null; then
      echo -e "${RED}ERROR: helm not found${NC}"; exit 1
    fi

    echo -e "  Applying allowlist via helm upgrade..."
    helm upgrade falco falcosecurity/falco \
      --namespace "$NAMESPACE_FALCO" \
      --reuse-values \
      --set-file "customRules.$RULE_NAME=$ALLOWLIST_FILE"

    echo ""
    echo -e "  ${GREEN}✓${NC}  Custom rules applied"
    echo ""
    echo "  Falco will reload rules automatically."
    echo "  Watch: kubectl logs -n $NAMESPACE_FALCO -l app.kubernetes.io/name=falco -f | grep 'Loading rules'"
    echo ""
    echo "  After 24h — re-check top noisy rules:"
    echo "  bash tools/tune-falco.sh --show-top"
  fi
fi

# ── List current rules ─────────────────────────────────────────────────────
if [[ "$ACTION" == "list-rules" ]]; then
  echo -e "${BLUE}Custom Falco rules currently loaded:${NC}"
  echo ""

  CUSTOM_CM=$(kubectl get configmap -n "$NAMESPACE_FALCO" \
    --no-headers 2>/dev/null | grep -i "custom\|rules" || echo "")

  if [[ -z "$CUSTOM_CM" ]]; then
    echo "  No custom rules configmaps found."
    echo "  Add rules: bash tools/tune-falco.sh --add-allowlist 01-detection/falco-rules/allowlist.yaml"
  else
    echo "$CUSTOM_CM" | while read -r line; do
      cm_name=$(echo "$line" | awk '{print $1}')
      echo -e "  ${GREEN}✓${NC}  ConfigMap: $cm_name"
    done
  fi

  # Show Helm release custom rules
  if command -v helm &>/dev/null; then
    echo ""
    echo -e "${BLUE}Helm values (customRules):${NC}"
    helm get values falco -n "$NAMESPACE_FALCO" 2>/dev/null \
      | python3 -c "
import sys, yaml
try:
    d = yaml.safe_load(sys.stdin)
    cr = d.get('customRules', {})
    if cr:
        for name in cr.keys():
            print(f'  {name}')
    else:
        print('  (none)')
except:
    print('  (could not parse)')
" 2>/dev/null || echo "  (helm get values failed)"
  fi
fi

echo ""
