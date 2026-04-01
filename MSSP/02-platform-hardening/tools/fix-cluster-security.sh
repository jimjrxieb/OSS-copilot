#!/usr/bin/env bash
# fix-cluster-security.sh — Apply security remediations from cluster audit findings
#
# Uses auto-detection to discover cluster services before applying NetworkPolicies.
# Designed as a single copy-paste script for post-audit remediation.
#
# Usage:
#   bash fix-cluster-security.sh                    # Apply all fixes
#   bash fix-cluster-security.sh --dry-run          # Preview only
#   bash fix-cluster-security.sh --skip-netpol      # Skip NetworkPolicy
#   bash fix-cluster-security.sh --skip-limits      # Skip LimitRange/ResourceQuota
#   bash fix-cluster-security.sh --skip-pss         # Skip PSS labels
#   bash fix-cluster-security.sh --skip-certmgr     # Skip cert-manager patches
#
# What it fixes:
#   - NetworkPolicy: default-deny + allow-dns + service-aware allow rules
#   - LimitRange + ResourceQuota: applied to application namespaces
#   - PSS labels: baseline on infra namespaces, restricted on app namespaces
#   - cert-manager: resource limits on deployments
#
# What it documents (no changes):
#   - RBAC wildcard ClusterRoles (CAPI, EKS-A, etcdadm — legitimate controllers)
#   - kube-system static pods (etcd, apiserver, scheduler — managed by kubelet)
#   - CNI pods (cilium — requires host network + privileges by design)

set -uo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Resolve template directory relative to script location ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEMPLATES_DIR="$(cd "$PACKAGE_DIR/02-hardening/remediation" && pwd)"

# --- Parse arguments ---
DRY_RUN=false
SKIP_NETPOL=false
SKIP_LIMITS=false
SKIP_PSS=false
SKIP_CERTMGR=false

for arg in "$@"; do
    case $arg in
        --dry-run)    DRY_RUN=true ;;
        --skip-netpol)  SKIP_NETPOL=true ;;
        --skip-limits)  SKIP_LIMITS=true ;;
        --skip-pss)     SKIP_PSS=true ;;
        --skip-certmgr) SKIP_CERTMGR=true ;;
        -h|--help)
            head -22 "$0" | tail -20
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $arg${NC}"
            echo "Usage: bash fix-cluster-security.sh [--dry-run] [--skip-netpol] [--skip-limits] [--skip-pss] [--skip-certmgr]"
            exit 1
            ;;
    esac
done

# --- Counters ---
NETPOL_APPLIED=0
NETPOL_SKIPPED=0
SERVICE_RULES_APPLIED=0
LIMITS_APPLIED=0
PSS_APPLIED=0
CERTMGR_APPLIED=0
ERRORS=0

# --- System namespaces (never patch these with LimitRange/ResourceQuota) ---
SYSTEM_NAMESPACES=(
    kube-system
    kube-public
    kube-node-lease
    gatekeeper-system
)

# --- Infrastructure namespaces (get PSS baseline, not restricted) ---
INFRA_NS_PATTERNS=(
    "capi-"
    "capd-"
    "eksa-"
    "etcdadm-"
    "cert-manager"
    "gatekeeper-system"
    "kube-system"
    "kube-public"
    "kube-node-lease"
)

# --- Privileged namespaces (need host access — skip PSS entirely) ---
PRIVILEGED_NAMESPACES=(
    falco
)

# --- Helpers ---
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
log_skip()  { echo -e "${CYAN}[SKIP]${NC}  $*"; }

run_kubectl() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} kubectl $*"
        return 0
    fi
    kubectl "$@"
}

is_system_ns() {
    local ns="$1"
    for sys_ns in "${SYSTEM_NAMESPACES[@]}"; do
        [[ "$ns" == "$sys_ns" ]] && return 0
    done
    return 1
}

is_infra_ns() {
    local ns="$1"
    for pattern in "${INFRA_NS_PATTERNS[@]}"; do
        [[ "$ns" == "$pattern"* ]] && return 0
        [[ "$ns" == "$pattern" ]] && return 0
    done
    return 1
}

# --- Preflight ---
echo ""
echo "=============================================="
echo "  fix-cluster-security.sh"
echo "  Cluster Security Remediation Script"
echo "=============================================="
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}>>> DRY-RUN MODE — no changes will be applied <<<${NC}"
    echo ""
fi

# Verify kubectl connectivity
if ! kubectl cluster-info &>/dev/null; then
    log_fail "Cannot connect to cluster. Check kubectl config."
    exit 1
fi
log_ok "kubectl connected to cluster"

# Verify templates exist
if [[ ! -d "$TEMPLATES_DIR" ]]; then
    log_fail "Templates not found at $TEMPLATES_DIR"
    exit 1
fi
log_ok "Templates found at $TEMPLATES_DIR"
echo ""

# Get all namespaces
ALL_NAMESPACES=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')

# ============================================================
# SECTION 0: Service Discovery
# ============================================================
# Before applying NetworkPolicies, discover cluster services so we can
# generate the correct allow rules. Without this, default-deny breaks
# cross-namespace communication (vault, prometheus, argocd, etc.).
# ============================================================
echo "----------------------------------------------"
echo "  Section 0: Service Discovery"
echo "----------------------------------------------"
echo ""

# Discovered service map — namespace:port pairs
# Each variable holds the namespace where the service was found (empty = not found)
VAULT_NS=""
VAULT_PORT=8200
PROMETHEUS_NS=""
PROMETHEUS_PORT=9090
GRAFANA_NS=""
GRAFANA_PORT=3000
ARGOCD_NS=""
EXTERNAL_SECRETS_NS=""
INGRESS_NS=""
INGRESS_TYPE=""

# --- Detect Vault ---
VAULT_SVC=$(kubectl get svc -A -l "app.kubernetes.io/name=vault" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
if [[ -z "$VAULT_SVC" ]]; then
    # Fallback: check for vault service by name
    VAULT_SVC=$(kubectl get svc -A --field-selector metadata.name=vault -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
fi
if [[ -n "$VAULT_SVC" ]]; then
    VAULT_NS="$VAULT_SVC"
    # Detect actual port
    VAULT_PORT=$(kubectl get svc vault -n "$VAULT_NS" -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || echo "8200")
    [[ -z "$VAULT_PORT" ]] && VAULT_PORT=8200
    log_ok "Vault detected in namespace: $VAULT_NS (port $VAULT_PORT)"
else
    log_info "Vault: not found"
fi

# --- Detect Prometheus ---
PROM_SVC=$(kubectl get svc -A -l "app.kubernetes.io/name=prometheus" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
if [[ -z "$PROM_SVC" ]]; then
    PROM_SVC=$(kubectl get svc -A -l "app=prometheus" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
fi
if [[ -n "$PROM_SVC" ]]; then
    PROMETHEUS_NS="$PROM_SVC"
    log_ok "Prometheus detected in namespace: $PROMETHEUS_NS"
else
    log_info "Prometheus: not found"
fi

# --- Detect Grafana ---
GRAF_SVC=$(kubectl get svc -A -l "app.kubernetes.io/name=grafana" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
if [[ -n "$GRAF_SVC" ]]; then
    GRAFANA_NS="$GRAF_SVC"
    GRAFANA_PORT=$(kubectl get svc -A -l "app.kubernetes.io/name=grafana" -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null || echo "3000")
    [[ -z "$GRAFANA_PORT" ]] && GRAFANA_PORT=3000
    log_ok "Grafana detected in namespace: $GRAFANA_NS (port $GRAFANA_PORT)"
else
    log_info "Grafana: not found"
fi

# --- Detect ArgoCD ---
ARGO_SVC=$(kubectl get svc -A -l "app.kubernetes.io/part-of=argocd" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
if [[ -z "$ARGO_SVC" ]]; then
    # Fallback: check for argocd namespace with argocd-server
    if kubectl get svc argocd-server -n argocd &>/dev/null; then
        ARGO_SVC="argocd"
    fi
fi
if [[ -n "$ARGO_SVC" ]]; then
    ARGOCD_NS="$ARGO_SVC"
    log_ok "ArgoCD detected in namespace: $ARGOCD_NS"
else
    log_info "ArgoCD: not found"
fi

# --- Detect External Secrets ---
ES_SVC=$(kubectl get svc -A -l "app.kubernetes.io/name=external-secrets" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
if [[ -z "$ES_SVC" ]]; then
    ES_SVC=$(kubectl get deploy -A -l "app.kubernetes.io/name=external-secrets" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
fi
if [[ -n "$ES_SVC" ]]; then
    EXTERNAL_SECRETS_NS="$ES_SVC"
    log_ok "External Secrets detected in namespace: $EXTERNAL_SECRETS_NS"
else
    log_info "External Secrets: not found"
fi

# --- Detect Ingress Controller (Traefik, Nginx, or Envoy) ---
for label in "app.kubernetes.io/name=traefik" "app.kubernetes.io/name=ingress-nginx" "app.kubernetes.io/name=envoy"; do
    INGRESS_CHECK=$(kubectl get svc -A -l "$label" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)
    if [[ -n "$INGRESS_CHECK" ]]; then
        INGRESS_NS="$INGRESS_CHECK"
        INGRESS_TYPE="${label##*=}"
        log_ok "Ingress controller detected: $INGRESS_TYPE in namespace: $INGRESS_NS"
        break
    fi
done
if [[ -z "$INGRESS_NS" ]]; then
    log_info "Ingress controller: not found (may be in kube-system)"
fi

echo ""

# ============================================================
# SECTION 1: NetworkPolicy
# ============================================================
if ! $SKIP_NETPOL; then
    echo "----------------------------------------------"
    echo "  Section 1: NetworkPolicy (default-deny + DNS)"
    echo "----------------------------------------------"
    echo ""

    # --- Phase 1A: Default-deny + DNS for all namespaces ---
    log_info "Phase 1A: Applying default-deny + allow-dns to namespaces without policies..."
    echo ""

    for ns in $ALL_NAMESPACES; do
        # Skip kube-system — CNI manages its own networking
        if [[ "$ns" == "kube-system" ]]; then
            log_skip "$ns — CNI manages networking"
            ((NETPOL_SKIPPED++))
            continue
        fi

        # Check if namespace already has default-deny-all
        if kubectl get networkpolicy default-deny-all -n "$ns" &>/dev/null; then
            # Already has default-deny — but ensure DNS egress exists too
            # (service-specific policies in Phase 1C don't include DNS)
            if ! kubectl get networkpolicy allow-dns-egress -n "$ns" &>/dev/null; then
                log_warn "$ns — has default-deny but MISSING allow-dns-egress, adding it"
            else
                log_skip "$ns — already has default-deny-all + allow-dns-egress"
                ((NETPOL_SKIPPED++))
                continue
            fi
        fi

        # Check if namespace has other NetworkPolicies but no default-deny
        existing=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
        if [[ "$existing" -gt 0 ]] && kubectl get networkpolicy default-deny-all -n "$ns" &>/dev/null; then
            ((NETPOL_SKIPPED++))
            continue
        fi

        # Apply default-deny-all + allow-dns-egress
        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply default-deny-all + allow-dns-egress -n $ns"
        else
            kubectl apply -n "$ns" -f - <<'DENY_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  annotations:
    jsa-infrasec.io/remediation: "netpol-default-deny"
    applied-by: "fix-cluster-security.sh"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
DENY_EOF

            kubectl apply -n "$ns" -f - <<'DNS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-allow-dns"
    applied-by: "fix-cluster-security.sh"
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
DNS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$ns — default-deny-all + allow-dns-egress applied"
            ((NETPOL_APPLIED++))
        else
            log_fail "$ns — failed to apply NetworkPolicy"
            ((ERRORS++))
        fi
    done

    echo ""

    # --- Phase 1B: Webhook namespaces (gatekeeper + cert-manager) ---
    log_info "Phase 1B: Webhook ingress + API server egress for admission controllers..."
    echo ""

    WEBHOOK_NAMESPACES=(gatekeeper-system cert-manager)

    for ns in "${WEBHOOK_NAMESPACES[@]}"; do
        if ! kubectl get ns "$ns" &>/dev/null; then
            continue
        fi

        log_info "$ns — adding webhook ingress + API server egress policies"

        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply allow-webhook-ingress + allow-apiserver-egress -n $ns"
        else
            kubectl apply -n "$ns" -f - <<'WEBHOOK_INGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-webhook-ingress
  annotations:
    jsa-infrasec.io/remediation: "netpol-webhook-ingress"
    applied-by: "fix-cluster-security.sh"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 8443
        - protocol: TCP
          port: 9443
        - protocol: TCP
          port: 10250
WEBHOOK_INGRESS_EOF

            kubectl apply -n "$ns" -f - <<'WEBHOOK_EGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-apiserver-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-apiserver-egress"
    applied-by: "fix-cluster-security.sh"
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # API server
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 6443
WEBHOOK_EGRESS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$ns — webhook ingress + API server egress applied"
            ((SERVICE_RULES_APPLIED++))
        else
            log_fail "$ns — failed to apply webhook policies"
            ((ERRORS++))
        fi
    done

    echo ""

    # --- Phase 1C: Service-aware allow rules (auto-detected) ---
    log_info "Phase 1C: Applying service-aware allow rules based on discovery..."
    echo ""

    # --- Vault: ingress from cluster + egress to K8s API ---
    if [[ -n "$VAULT_NS" ]]; then
        log_info "Vault ($VAULT_NS): ingress on $VAULT_PORT from cluster + K8s API egress"

        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply vault service policies -n $VAULT_NS"
        else
            kubectl apply -n "$VAULT_NS" -f - <<VAULT_EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-vault-ingress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-vault-ingress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "vault"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vault
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: ${VAULT_PORT}
        - protocol: TCP
          port: 8201
VAULT_EOF

            kubectl apply -n "$VAULT_NS" -f - <<'VAULT_EGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-vault-k8s-api-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-vault-egress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "vault"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vault
  policyTypes:
    - Egress
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 6443
VAULT_EGRESS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$VAULT_NS — vault ingress + K8s API egress applied"
            ((SERVICE_RULES_APPLIED++))
        else
            log_fail "$VAULT_NS — failed to apply vault policies"
            ((ERRORS++))
        fi
    fi

    # --- External Secrets: egress to Vault + K8s API ---
    if [[ -n "$EXTERNAL_SECRETS_NS" ]]; then
        log_info "External Secrets ($EXTERNAL_SECRETS_NS): egress to Vault + K8s API"

        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply external-secrets service policies -n $EXTERNAL_SECRETS_NS"
        else
            # Build vault egress rule only if vault was detected
            VAULT_EGRESS_RULE=""
            if [[ -n "$VAULT_NS" ]]; then
                VAULT_EGRESS_RULE="
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${VAULT_NS}
      ports:
        - protocol: TCP
          port: ${VAULT_PORT}"
            fi

            kubectl apply -n "$EXTERNAL_SECRETS_NS" -f - <<ES_EGRESS_EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-secrets-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-external-secrets-egress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "external-secrets"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: external-secrets
  policyTypes:
    - Egress
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 6443${VAULT_EGRESS_RULE}
ES_EGRESS_EOF

            # Webhook ingress for external-secrets (cert controller serves webhooks)
            kubectl apply -n "$EXTERNAL_SECRETS_NS" -f - <<'ES_INGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-secrets-webhook-ingress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-external-secrets-ingress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "external-secrets"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 10250
ES_INGRESS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$EXTERNAL_SECRETS_NS — external-secrets egress + webhook ingress applied"
            ((SERVICE_RULES_APPLIED++))
        else
            log_fail "$EXTERNAL_SECRETS_NS — failed to apply external-secrets policies"
            ((ERRORS++))
        fi
    fi

    # --- Prometheus: egress to scrape all namespaces + ingress from Grafana ---
    if [[ -n "$PROMETHEUS_NS" ]]; then
        log_info "Prometheus ($PROMETHEUS_NS): scraping egress + query ingress"

        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply prometheus service policies -n $PROMETHEUS_NS"
        else
            kubectl apply -n "$PROMETHEUS_NS" -f - <<'PROM_EGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-prometheus-egress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "prometheus"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
    - Egress
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 8443
        - protocol: TCP
          port: 8888
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 9093
        - protocol: TCP
          port: 9100
        - protocol: TCP
          port: 10250
        - protocol: TCP
          port: 10257
        - protocol: TCP
          port: 10259
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 6443
PROM_EGRESS_EOF

            kubectl apply -n "$PROMETHEUS_NS" -f - <<'PROM_INGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-query-ingress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-prometheus-ingress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "prometheus"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 9093
        - protocol: TCP
          port: 9094
        - protocol: TCP
          port: 3000
        - protocol: TCP
          port: 8080
PROM_INGRESS_EOF

            # Alertmanager needs egress for sending alerts (SMTP, webhooks)
            kubectl apply -n "$PROMETHEUS_NS" -f - <<'ALERT_EGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-alertmanager-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-alertmanager-egress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "alertmanager"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: alertmanager
  policyTypes:
    - Egress
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 587
ALERT_EGRESS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$PROMETHEUS_NS — prometheus scraping + query ingress applied"
            ((SERVICE_RULES_APPLIED++))
        else
            log_fail "$PROMETHEUS_NS — failed to apply prometheus policies"
            ((ERRORS++))
        fi

        # Allow metrics ingress on all namespaces so Prometheus can scrape them
        log_info "Allowing metrics ingress from Prometheus on all namespaces..."
        for ns in $ALL_NAMESPACES; do
            [[ "$ns" == "kube-system" ]] && continue
            [[ "$ns" == "$PROMETHEUS_NS" ]] && continue

            if $DRY_RUN; then
                echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply allow-metrics-scrape -n $ns"
            else
                kubectl apply -n "$ns" -f - <<METRICS_EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-metrics-scrape
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-metrics-scrape"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "prometheus"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${PROMETHEUS_NS}
      ports:
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 8443
        - protocol: TCP
          port: 8888
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 9100
        - protocol: TCP
          port: 10250
METRICS_EOF
            fi
        done
        log_ok "Metrics scrape ingress applied to all namespaces"
    fi

    # --- Grafana: egress to Prometheus ---
    if [[ -n "$GRAFANA_NS" && -n "$PROMETHEUS_NS" && "$GRAFANA_NS" == "$PROMETHEUS_NS" ]]; then
        # Same namespace — intra-namespace rules handled by allow-same-namespace if present
        log_info "Grafana and Prometheus in same namespace ($GRAFANA_NS) — no extra egress needed"
    elif [[ -n "$GRAFANA_NS" && -n "$PROMETHEUS_NS" ]]; then
        log_info "Grafana ($GRAFANA_NS): egress to Prometheus ($PROMETHEUS_NS)"
        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply grafana egress -n $GRAFANA_NS"
        else
            kubectl apply -n "$GRAFANA_NS" -f - <<GRAFANA_EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-datasource-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-grafana-egress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "grafana"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${PROMETHEUS_NS}
      ports:
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 9093
GRAFANA_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$GRAFANA_NS — grafana datasource egress applied"
            ((SERVICE_RULES_APPLIED++))
        fi
    fi

    # --- ArgoCD: egress to Git, registries, K8s API + inter-component ---
    if [[ -n "$ARGOCD_NS" ]]; then
        log_info "ArgoCD ($ARGOCD_NS): egress to Git/registries/K8s API + internal comms"

        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply argocd service policies -n $ARGOCD_NS"
        else
            kubectl apply -n "$ARGOCD_NS" -f - <<'ARGO_EGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-argocd-egress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-argocd-egress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "argocd"
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # DNS — required for resolving git repos, OIDC, registries
    # BUG FIX: missing DNS caused intermittent pod restarts when
    # DNS resolution failed and liveness probes caught it.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Git repos, container registries, OIDC providers
    - ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 22
    # K8s API for managing resources
    - ports:
        - protocol: TCP
          port: 6443
    # Redis (inter-component)
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 6379
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 8081
        - protocol: TCP
          port: 8082
        - protocol: TCP
          port: 8083
        - protocol: TCP
          port: 8084
ARGO_EGRESS_EOF

            kubectl apply -n "$ARGOCD_NS" -f - <<'ARGO_INGRESS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-argocd-ingress
  annotations:
    jsa-infrasec.io/remediation: "netpol-service-argocd-ingress"
    applied-by: "fix-cluster-security.sh"
    jsa-infrasec.io/detected-service: "argocd"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    # UI/API access from ingress controller + internal
    - ports:
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 8443
        - protocol: TCP
          port: 443
    # Inter-component (Redis, repo-server, dex)
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 6379
        - protocol: TCP
          port: 8081
        - protocol: TCP
          port: 8082
        - protocol: TCP
          port: 8083
        - protocol: TCP
          port: 8084
        - protocol: TCP
          port: 5556
ARGO_INGRESS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$ARGOCD_NS — argocd egress + ingress applied"
            ((SERVICE_RULES_APPLIED++))
        else
            log_fail "$ARGOCD_NS — failed to apply argocd policies"
            ((ERRORS++))
        fi
    fi

    # --- Phase 1D: Same-namespace communication for app namespaces ---
    log_info "Phase 1D: Allowing same-namespace communication for application namespaces..."
    echo ""

    for ns in $ALL_NAMESPACES; do
        [[ "$ns" == "kube-system" ]] && continue

        # Skip if this namespace already has same-namespace policy
        if kubectl get networkpolicy allow-same-namespace -n "$ns" &>/dev/null; then
            continue
        fi

        # Only apply to namespaces that got default-deny (have our annotation)
        if ! kubectl get networkpolicy default-deny-all -n "$ns" -o jsonpath='{.metadata.annotations.applied-by}' 2>/dev/null | grep -q "fix-cluster-security"; then
            continue
        fi

        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply allow-same-namespace -n $ns"
        else
            kubectl apply -n "$ns" -f - <<'SAME_NS_EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  annotations:
    jsa-infrasec.io/remediation: "netpol-same-namespace"
    applied-by: "fix-cluster-security.sh"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
SAME_NS_EOF
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$ns — allow-same-namespace applied"
            ((SERVICE_RULES_APPLIED++))
        fi
    done

    echo ""
else
    log_skip "Section 1: NetworkPolicy (--skip-netpol)"
    echo ""
fi

# ============================================================
# SECTION 2: LimitRange + ResourceQuota
# ============================================================
if ! $SKIP_LIMITS; then
    echo "----------------------------------------------"
    echo "  Section 2: LimitRange + ResourceQuota"
    echo "----------------------------------------------"
    echo ""

    RESOURCE_TEMPLATE="$TEMPLATES_DIR/resource-management.yaml"

    for ns in $ALL_NAMESPACES; do
        # Skip system namespaces
        if is_system_ns "$ns"; then
            log_skip "$ns — system namespace"
            continue
        fi

        # Skip infrastructure namespaces (CAPI, EKS-A, etc.)
        if is_infra_ns "$ns"; then
            log_skip "$ns — infrastructure namespace"
            continue
        fi

        # Check if LimitRange already exists
        existing_lr=$(kubectl get limitrange -n "$ns" -o name 2>/dev/null | wc -l)
        if [[ "$existing_lr" -gt 0 ]]; then
            log_skip "$ns — already has LimitRange"
            continue
        fi

        # Apply LimitRange + ResourceQuota from template
        if $DRY_RUN; then
            echo -e "${YELLOW}[DRY-RUN]${NC} kubectl apply -f resource-management.yaml -n $ns"
        else
            kubectl apply -f "$RESOURCE_TEMPLATE" -n "$ns" 2>&1
        fi

        if [[ $? -eq 0 ]]; then
            log_ok "$ns — LimitRange + ResourceQuota applied"
            ((LIMITS_APPLIED++))
        else
            log_fail "$ns — failed to apply resource management"
            ((ERRORS++))
        fi
    done
    echo ""
else
    log_skip "Section 2: LimitRange + ResourceQuota (--skip-limits)"
    echo ""
fi

# ============================================================
# SECTION 3: PSS Namespace Labels
# ============================================================
if ! $SKIP_PSS; then
    echo "----------------------------------------------"
    echo "  Section 3: Pod Security Standards Labels"
    echo "----------------------------------------------"
    echo ""

    is_privileged_ns() {
        local ns="$1"
        for p in "${PRIVILEGED_NAMESPACES[@]}"; do
            [[ "$ns" == "$p" ]] && return 0
        done
        return 1
    }

    for ns in $ALL_NAMESPACES; do
        # kube-system stays privileged
        if [[ "$ns" == "kube-system" ]]; then
            log_skip "$ns — stays privileged (system)"
            continue
        fi

        # Privileged namespaces (Falco, etc.) need host access — skip PSS
        if is_privileged_ns "$ns"; then
            log_skip "$ns — stays privileged (requires host access)"
            continue
        fi

        if is_infra_ns "$ns"; then
            # Infrastructure namespaces get baseline enforcement + restricted audit/warn
            if $DRY_RUN; then
                echo -e "${YELLOW}[DRY-RUN]${NC} kubectl label ns $ns pod-security.kubernetes.io/enforce=baseline (infra)"
            else
                kubectl label ns "$ns" \
                    pod-security.kubernetes.io/enforce=baseline \
                    pod-security.kubernetes.io/enforce-version=latest \
                    pod-security.kubernetes.io/audit=restricted \
                    pod-security.kubernetes.io/audit-version=latest \
                    pod-security.kubernetes.io/warn=restricted \
                    pod-security.kubernetes.io/warn-version=latest \
                    --overwrite 2>&1
            fi
            if [[ $? -eq 0 ]]; then
                log_ok "$ns — PSS baseline (infrastructure)"
                ((PSS_APPLIED++))
            else
                log_fail "$ns — failed to apply PSS labels"
                ((ERRORS++))
            fi
        else
            # Application namespaces get restricted enforcement
            if $DRY_RUN; then
                echo -e "${YELLOW}[DRY-RUN]${NC} kubectl label ns $ns pod-security.kubernetes.io/enforce=restricted (app)"
            else
                kubectl label ns "$ns" \
                    pod-security.kubernetes.io/enforce=restricted \
                    pod-security.kubernetes.io/enforce-version=latest \
                    pod-security.kubernetes.io/audit=restricted \
                    pod-security.kubernetes.io/audit-version=latest \
                    pod-security.kubernetes.io/warn=restricted \
                    pod-security.kubernetes.io/warn-version=latest \
                    --overwrite 2>&1
            fi
            if [[ $? -eq 0 ]]; then
                log_ok "$ns — PSS restricted (application)"
                ((PSS_APPLIED++))
            else
                log_fail "$ns — failed to apply PSS labels"
                ((ERRORS++))
            fi
        fi
    done
    echo ""
else
    log_skip "Section 3: PSS labels (--skip-pss)"
    echo ""
fi

# ============================================================
# SECTION 4: cert-manager Resource Limits
# ============================================================
if ! $SKIP_CERTMGR; then
    echo "----------------------------------------------"
    echo "  Section 4: cert-manager Resource Limits"
    echo "----------------------------------------------"
    echo ""

    # Check if cert-manager namespace exists
    if kubectl get ns cert-manager &>/dev/null; then
        CERTMGR_DEPLOYMENTS=$(kubectl get deployments -n cert-manager -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

        for deploy in $CERTMGR_DEPLOYMENTS; do
            if $DRY_RUN; then
                echo -e "${YELLOW}[DRY-RUN]${NC} kubectl set resources deployment/$deploy -n cert-manager --limits=cpu=500m,memory=512Mi --requests=cpu=100m,memory=128Mi"
            else
                kubectl set resources deployment/"$deploy" -n cert-manager \
                    --limits=cpu=500m,memory=512Mi \
                    --requests=cpu=100m,memory=128Mi 2>&1
            fi

            if [[ $? -eq 0 ]]; then
                log_ok "cert-manager/$deploy — resource limits applied"
                ((CERTMGR_APPLIED++))
            else
                log_fail "cert-manager/$deploy — failed to patch"
                ((ERRORS++))
            fi
        done
    else
        log_skip "cert-manager namespace not found"
    fi
    echo ""
else
    log_skip "Section 4: cert-manager patches (--skip-certmgr)"
    echo ""
fi

# ============================================================
# SECTION 5: RBAC Wildcard Audit Report (document only)
# ============================================================
echo "----------------------------------------------"
echo "  Section 5: RBAC Wildcard Audit (report only)"
echo "----------------------------------------------"
echo ""

log_info "The following ClusterRoles have wildcard permissions."
log_info "These are legitimate infrastructure controllers — DO NOT modify."
echo ""

# Find wildcard ClusterRoles
WILDCARD_ROLES=$(kubectl get clusterroles -o json 2>/dev/null | \
    jq -r '[.items[] | select(.rules[]? | (.verbs[]? == "*") or (.resources[]? == "*")) | .metadata.name] | unique[] | "  \(.)"' 2>/dev/null || true)

if [[ -n "$WILDCARD_ROLES" ]]; then
    echo -e "${YELLOW}Wildcard ClusterRoles:${NC}"
    echo "$WILDCARD_ROLES"
    echo ""
    log_info "These are typically: CAPI controllers, EKS-A controllers, etcdadm, Gatekeeper"
    log_info "Modifying them would break cluster lifecycle management."
else
    log_ok "No wildcard ClusterRoles found"
fi

echo ""
log_info "Generating Kyverno PolicyException YAML for acknowledged RBAC exceptions..."
echo ""

# Generate PolicyException for documentation
EXCEPTION_YAML="/tmp/jsa-cascade/rbac-policy-exceptions.yaml"
mkdir -p /tmp/jsa-cascade

cat > "$EXCEPTION_YAML" <<'EXCEPTION_EOF'
# RBAC Wildcard PolicyExceptions
# Generated by fix-cluster-security.sh
# These ClusterRoles have legitimate wildcard permissions (CAPI, EKS-A, etcdadm, Gatekeeper)
# Documenting as acknowledged exceptions — do NOT restrict, they manage cluster lifecycle.
---
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: capi-controllers-rbac-exception
  namespace: kyverno
spec:
  exceptions:
  - policyName: restrict-wildcard-verbs
    ruleNames: ["no-wildcard-verbs"]
  match:
    any:
    - resources:
        kinds: [ClusterRole]
        names:
        - "capi-*"
        - "eksa-*"
        - "etcdadm-*"
---
apiVersion: kyverno.io/v2beta1
kind: PolicyException
metadata:
  name: gatekeeper-rbac-exception
  namespace: kyverno
spec:
  exceptions:
  - policyName: restrict-wildcard-verbs
    ruleNames: ["no-wildcard-verbs"]
  match:
    any:
    - resources:
        kinds: [ClusterRole]
        names:
        - "gatekeeper-*"
EXCEPTION_EOF

log_ok "PolicyException YAML written to $EXCEPTION_YAML"
log_info "Review and apply with: kubectl apply -f $EXCEPTION_YAML"
echo ""

# ============================================================
# SUMMARY
# ============================================================
echo "=============================================="
echo "  SUMMARY"
echo "=============================================="
echo ""

if $DRY_RUN; then
    echo -e "${YELLOW}DRY-RUN — no changes were applied${NC}"
    echo ""
fi

echo -e "  NetworkPolicies (deny+DNS): ${GREEN}${NETPOL_APPLIED}${NC}  (skipped: ${NETPOL_SKIPPED})"
echo -e "  Service-aware rules:        ${GREEN}${SERVICE_RULES_APPLIED}${NC}"
echo -e "  LimitRange/Quota applied:   ${GREEN}${LIMITS_APPLIED}${NC}"
echo -e "  PSS labels applied:         ${GREEN}${PSS_APPLIED}${NC}"
echo -e "  cert-manager patches:       ${GREEN}${CERTMGR_APPLIED}${NC}"
echo -e "  Errors:                     ${RED}${ERRORS}${NC}"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    log_warn "$ERRORS error(s) occurred. Review output above."
    echo ""
fi

echo "Next steps:"
echo "  1. Re-run cluster audit to verify improvements:"
echo "     bash \$(dirname \$0)/run-cluster-audit.sh --output /tmp/k8s-audit-post-fix-\$(date +%Y%m%d).md"
echo "  2. Review RBAC PolicyExceptions: $EXCEPTION_YAML"
echo "  3. Verify cert-manager pods restarted with limits:"
echo "     kubectl get pods -n cert-manager -o jsonpath='{.items[*].spec.containers[*].resources}'"
echo ""

# Non-fixable items reminder
echo "----------------------------------------------"
echo "  Items NOT fixed (by design)"
echo "----------------------------------------------"
echo ""
echo "  Static pods (etcd, kube-apiserver, kube-controller-manager, kube-scheduler):"
echo "    → Managed by kubelet manifests on nodes, not kubectl"
echo ""
echo "  CNI (cilium):"
echo "    → Requires host network + privileges by design"
echo ""
echo "  CAPI controllers (capi-*, eksa-*, etcdadm-*):"
echo "    → Managed by Cluster API, manual patches get reverted"
echo ""
echo "  kube-proxy:"
echo "    → DaemonSet managed by kubeadm"
echo ""

exit $ERRORS
