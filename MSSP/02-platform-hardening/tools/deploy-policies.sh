#!/usr/bin/env bash
# =============================================================================
# Ghost Protocol -- deploy-policies.sh
# Deploy Kyverno or OPA Gatekeeper and policy templates to a Kubernetes cluster
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
POLICY_TEMPLATES_DIR="$PACKAGE_DIR/01-policies"

ENGINE="kyverno"
MODE="audit"
DRY_RUN=false
VERIFY=false

KYVERNO_HELM_VERSION="3.2.6"
GATEKEEPER_HELM_VERSION="3.14.0"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --engine    kyverno|gatekeeper    Policy engine (default: kyverno)"
    echo "  --mode      audit|enforce         Enforcement mode (default: audit)"
    echo "  --dry-run                         Print what would be done, do not apply"
    echo "  --verify                          Verify policies are ready after deploy"
    echo "  -h, --help                        Show this help"
    exit 0
}

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BLUE}=== $* ===${NC}"; }

die() { log_error "$*"; exit 1; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --engine)
                ENGINE="${2:-}"
                [[ "$ENGINE" == "kyverno" || "$ENGINE" == "gatekeeper" ]] \
                    || die "Invalid engine: $ENGINE. Must be kyverno or gatekeeper."
                shift 2 ;;
            --mode)
                MODE="${2:-}"
                [[ "$MODE" == "audit" || "$MODE" == "enforce" ]] \
                    || die "Invalid mode: $MODE. Must be audit or enforce."
                shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --verify)  VERIFY=true; shift ;;
            -h|--help) usage ;;
            *) die "Unknown argument: $1" ;;
        esac
    done
}

check_prerequisites() {
    log_section "Checking Prerequisites"

    command -v kubectl &>/dev/null || die "kubectl not found."
    log_ok "kubectl found: $(kubectl version --client --short 2>/dev/null || true)"

    log_info "Testing cluster connectivity..."
    kubectl cluster-info &>/dev/null || die "Cannot reach cluster. Check KUBECONFIG."
    CLUSTER=$(kubectl config current-context 2>/dev/null || echo "unknown")
    log_ok "Connected to cluster context: ${CLUSTER}"

    # CRITICAL: Detect ArgoCD — mutations on ArgoCD-managed resources cause sync loops
    # Portfolio incident Mar 2026: Gatekeeper mutate → ArgoCD self-heal → loop → crash
    ARGOCD_PRESENT=false
    if kubectl get namespace argocd &>/dev/null || kubectl get applications.argoproj.io -A &>/dev/null 2>&1; then
        ARGOCD_PRESENT=true
        log_warn "ArgoCD detected on this cluster."
        log_warn "Gatekeeper mutations will EXCLUDE ArgoCD-managed resources."
        log_warn "Fix ArgoCD-managed workloads in git, not via admission mutation."
        log_warn "See: .claude/rules/argocd-rules.md"
    fi

    if command -v helm &>/dev/null; then
        log_ok "helm found: $(helm version --short 2>/dev/null)"
    else
        log_warn "helm not found -- cannot auto-install $ENGINE if missing."
    fi

    [[ -d "$POLICY_TEMPLATES_DIR/$ENGINE" ]] \
        || die "Policy templates dir not found: $POLICY_TEMPLATES_DIR/$ENGINE"
    log_ok "Policy templates: $POLICY_TEMPLATES_DIR/$ENGINE"
}

is_kyverno_installed() {
    kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -qE "Running|Pending"
}

is_gatekeeper_installed() {
    # Check helm release first (most reliable), fall back to pod detection
    helm list -n gatekeeper-system 2>/dev/null | grep -q gatekeeper && return 0
    kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | grep -qE "Running|Pending|ContainerCreating"
}

install_kyverno() {
    log_section "Installing Kyverno"

    if is_kyverno_installed; then
        log_ok "Kyverno already installed in namespace 'kyverno'."
        kubectl get pods -n kyverno --no-headers 2>/dev/null | while read -r line; do
            log_info "  Pod: $line"
        done
        return 0
    fi

    log_info "Kyverno not detected. Installing via Helm..."
    if $DRY_RUN; then
        log_warn "[DRY-RUN] helm repo add kyverno https://kyverno.github.io/kyverno/"
        log_warn "[DRY-RUN] helm install kyverno kyverno/kyverno -n kyverno --create-namespace --version $KYVERNO_HELM_VERSION"
        return 0
    fi

    command -v helm &>/dev/null || die "helm required to install Kyverno."
    helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
    helm repo update kyverno
    helm install kyverno kyverno/kyverno \
        --namespace kyverno --create-namespace \
        --version "$KYVERNO_HELM_VERSION" \
        --set admissionController.replicas=1 \
        --set backgroundController.replicas=1 \
        --wait --timeout 300s

    log_ok "Kyverno installed successfully."
}

install_gatekeeper() {
    log_section "Installing OPA Gatekeeper"

    if is_gatekeeper_installed; then
        log_ok "Gatekeeper already installed in namespace 'gatekeeper-system'."
        kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | while read -r line; do
            log_info "  Pod: $line"
        done
        return 0
    fi

    log_info "Gatekeeper not detected. Installing via Helm..."
    if $DRY_RUN; then
        log_warn "[DRY-RUN] helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts"
        log_warn "[DRY-RUN] helm install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace --version $GATEKEEPER_HELM_VERSION"
        return 0
    fi

    command -v helm &>/dev/null || die "helm required to install Gatekeeper."
    helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>/dev/null || true
    helm repo update gatekeeper
    helm install gatekeeper gatekeeper/gatekeeper \
        --namespace gatekeeper-system --create-namespace \
        --version "$GATEKEEPER_HELM_VERSION" \
        --wait --timeout 300s

    log_ok "Gatekeeper installed successfully."
}

deploy_kyverno_policies() {
    log_section "Deploying Kyverno Policies (mode: $MODE)"

    local policy_dir="$POLICY_TEMPLATES_DIR/kyverno"
    local deployed=0 failed=0 skipped=0
    local deployed_names=()

    shopt -s nullglob
    local policy_files=("$policy_dir"/*.yaml)
    shopt -u nullglob

    if [[ ${#policy_files[@]} -eq 0 ]]; then
        log_warn "No YAML files in $policy_dir"
        return 0
    fi

    for policy_file in "${policy_files[@]}"; do
        local policy_name
        policy_name=$(basename "$policy_file" .yaml)
        log_info "Processing: $policy_name"

        if $DRY_RUN; then
            [[ "$MODE" == "enforce" ]] && log_warn "[DRY-RUN] Would patch validationFailureAction=Enforce: $policy_name"
            log_warn "[DRY-RUN] Would apply: $policy_file"
            skipped=$((skipped + 1))
            continue
        fi

        local manifest="$policy_file"
        if [[ "$MODE" == "enforce" ]]; then
            local tmpfile; tmpfile=$(mktemp /tmp/kyverno-XXXXXX.yaml)
            sed 's/validationFailureAction: [Aa]udit/validationFailureAction: Enforce/g' \
                "$policy_file" > "$tmpfile"
            manifest="$tmpfile"
        fi

        if kubectl apply -f "$manifest" 2>&1; then
            log_ok "  Deployed: $policy_name"
            deployed=$((deployed + 1))
            deployed_names+=("$policy_name")
        else
            log_error "  Failed:   $policy_name"
            failed=$((failed + 1))
        fi

        [[ "$manifest" != "$policy_file" ]] && rm -f "$manifest"
    done

    echo ""
    log_section "Kyverno Deployment Summary"
    echo -e "  ${GREEN}Deployed:${NC} $deployed"
    echo -e "  ${RED}Failed:${NC}   $failed"
    echo -e "  ${YELLOW}Skipped (dry-run):${NC} $skipped"
    if [[ ${#deployed_names[@]} -gt 0 ]]; then
        echo ""
        log_info "Policies deployed:"
        for name in "${deployed_names[@]}"; do
            echo -e "    ${GREEN}+${NC} $name"
        done
    fi

    return $failed
}

deploy_gatekeeper_policies() {
    log_section "Deploying OPA Gatekeeper Policies (mode: $MODE)"

    # ArgoCD safety check: verify mutations.yaml has ArgoCD exclusions
    if [[ "$ARGOCD_PRESENT" == "true" ]]; then
        local mutations_file="$POLICY_TEMPLATES_DIR/gatekeeper/mutations.yaml"
        if [[ -f "$mutations_file" ]]; then
            if ! grep -q "app.kubernetes.io/instance" "$mutations_file"; then
                log_error "ABORT: mutations.yaml does NOT exclude ArgoCD-managed resources."
                log_error "Deploying Gatekeeper mutations without ArgoCD exclusion causes sync loops."
                log_error "Add labelSelector with DoesNotExist for app.kubernetes.io/instance."
                die "Fix mutations.yaml before deploying. See argocd-rules.md."
            fi
            log_ok "mutations.yaml has ArgoCD exclusion — safe to deploy."
        fi
    fi

    local policy_dir="$POLICY_TEMPLATES_DIR/gatekeeper"
    local deployed=0 failed=0 skipped=0
    local deployed_names=()

    shopt -s nullglob
    local policy_files=("$policy_dir"/*.yaml)
    shopt -u nullglob

    if [[ ${#policy_files[@]} -eq 0 ]]; then
        log_warn "No YAML files in $policy_dir"
        return 0
    fi

    for policy_file in "${policy_files[@]}"; do
        local policy_name
        policy_name=$(basename "$policy_file" .yaml)
        log_info "Processing: $policy_name"

        if $DRY_RUN; then
            log_warn "[DRY-RUN] Would apply: $policy_file"
            skipped=$((skipped + 1))
            continue
        fi

        local manifest="$policy_file"
        if [[ "$MODE" == "audit" ]]; then
            local tmpfile; tmpfile=$(mktemp /tmp/gatekeeper-XXXXXX.yaml)
            sed 's/enforcementAction: deny/enforcementAction: dryrun/g;
                 s/enforcementAction: warn/enforcementAction: dryrun/g' \
                "$policy_file" > "$tmpfile"
            manifest="$tmpfile"
        fi

        if kubectl apply -f "$manifest" 2>&1; then
            log_ok "  Deployed: $policy_name"
            deployed=$((deployed + 1))
            deployed_names+=("$policy_name")
        else
            log_error "  Failed:   $policy_name"
            failed=$((failed + 1))
        fi

        [[ "$manifest" != "$policy_file" ]] && rm -f "$manifest"
    done

    echo ""
    log_section "Gatekeeper Deployment Summary"
    echo -e "  ${GREEN}Deployed:${NC} $deployed"
    echo -e "  ${RED}Failed:${NC}   $failed"
    echo -e "  ${YELLOW}Skipped (dry-run):${NC} $skipped"
    if [[ ${#deployed_names[@]} -gt 0 ]]; then
        echo ""
        log_info "Policies deployed:"
        for name in "${deployed_names[@]}"; do
            echo -e "    ${GREEN}+${NC} $name"
        done
    fi

    return $failed
}

wait_for_kyverno_policies() {
    log_section "Verifying Kyverno Policies"
    log_info "Waiting for ClusterPolicies to be ready (up to 120s)..."

    local timeout=120 elapsed=0 ready=0 total=0

    while [[ $elapsed -lt $timeout ]]; do
        total=$(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l | tr -d ' ')
        ready=$(kubectl get clusterpolicies --no-headers 2>/dev/null | grep -c "True" || echo 0)
        [[ "$total" -gt 0 && "$ready" -ge "$total" ]] && break
        log_info "  Ready: $ready/$total (${elapsed}s)"
        sleep 5; elapsed=$((elapsed + 5))
    done

    echo ""
    kubectl get clusterpolicies 2>/dev/null || log_warn "Could not retrieve ClusterPolicies."

    if [[ "$ready" -lt "$total" ]]; then
        log_warn "Not all policies ready within ${timeout}s ($ready/$total)."
        return 1
    fi
    log_ok "All $total ClusterPolicies are ready."
}

wait_for_gatekeeper_policies() {
    log_section "Verifying Gatekeeper Policies"
    log_info "Waiting for ConstraintTemplates (up to 120s)..."

    local timeout=120 elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local not_ready
        not_ready=$(kubectl get constrainttemplates --no-headers 2>/dev/null | grep -cv "True" || echo 0)
        [[ "$not_ready" -eq 0 ]] && break
        log_info "  Waiting for $not_ready ConstraintTemplates... (${elapsed}s)"
        sleep 5; elapsed=$((elapsed + 5))
    done

    echo ""
    kubectl get constrainttemplates 2>/dev/null || log_warn "Could not retrieve ConstraintTemplates."
    kubectl get constraints --all-namespaces 2>/dev/null || log_warn "Could not retrieve Constraints."
    log_ok "Gatekeeper verification complete."
}

main() {
    echo -e "${BLUE}"
    echo "============================================================"
    echo "  Ghost Protocol -- deploy-policies.sh"
    echo "============================================================"
    echo -e "${NC}"

    parse_args "$@"
    log_info "Engine: $ENGINE | Mode: $MODE | Dry-run: $DRY_RUN | Verify: $VERIFY"
    check_prerequisites

    case "$ENGINE" in
        kyverno)
            install_kyverno
            deploy_kyverno_policies
            $VERIFY && ! $DRY_RUN && wait_for_kyverno_policies ;;
        gatekeeper)
            install_gatekeeper
            deploy_gatekeeper_policies
            $VERIFY && ! $DRY_RUN && wait_for_gatekeeper_policies ;;
    esac

    echo ""; log_ok "deploy-policies.sh complete."
}

main "$@"
