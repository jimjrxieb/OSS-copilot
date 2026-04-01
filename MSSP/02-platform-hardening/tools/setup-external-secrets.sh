#!/usr/bin/env bash
# =============================================================================
# Ghost Protocol -- setup-external-secrets.sh
# Install External Secrets Operator and configure a secret backend
#
# Usage:
#   bash tools/setup-external-secrets.sh --backend aws --aws-region us-east-1
#   bash tools/setup-external-secrets.sh --backend vault --vault-addr https://vault.example.com
#   bash tools/setup-external-secrets.sh --backend azure
#   bash tools/setup-external-secrets.sh --backend fake   # lab/demo mode
#   bash tools/setup-external-secrets.sh --dry-run
#
# Supported backends: aws, vault, azure, fake (lab/demo)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="${PACKAGE_DIR}/03-templates/external-secrets"

# Pinned versions
ESO_CHART_VERSION="0.12.1"

# Defaults
BACKEND="aws"
AWS_REGION="us-east-1"
VAULT_ADDR=""
NAMESPACE="external-secrets"
DRY_RUN=false
TEST_SECRET=true

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_section() { echo -e "\n${BLUE}=== $* ===${NC}"; }

die() { log_error "$*"; exit 1; }

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --backend     aws|vault|azure|fake  Secret backend (default: aws)"
    echo "  --aws-region  REGION           AWS region (default: us-east-1)"
    echo "  --vault-addr  URL              Vault server URL"
    echo "  --namespace   NS               ESO namespace (default: external-secrets)"
    echo "  --no-test                      Skip test secret verification"
    echo "  --dry-run                      Print what would be done, do not apply"
    echo "  -h, --help                     Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            BACKEND="${2:-}"
            [[ "$BACKEND" =~ ^(aws|vault|azure|fake)$ ]] \
                || die "Invalid backend: $BACKEND. Must be aws, vault, azure, or fake."
            shift 2 ;;
        --aws-region)  AWS_REGION="${2:-}"; shift 2 ;;
        --vault-addr)  VAULT_ADDR="${2:-}"; shift 2 ;;
        --namespace)   NAMESPACE="${2:-}"; shift 2 ;;
        --no-test)     TEST_SECRET=false; shift ;;
        --dry-run)     DRY_RUN=true; shift ;;
        -h|--help)     usage ;;
        *)             die "Unknown option: $1" ;;
    esac
done

# Validate backend-specific args
if [ "$BACKEND" = "vault" ] && [ -z "$VAULT_ADDR" ]; then
    die "--vault-addr is required when using vault backend"
fi

# ── Pre-flight checks ─────────────────────────────────────────────────────
log_section "Pre-flight checks"

command -v kubectl >/dev/null 2>&1 || die "kubectl not found."
command -v helm >/dev/null 2>&1 || die "helm not found."
kubectl cluster-info >/dev/null 2>&1 || die "Cannot connect to Kubernetes cluster."
log_ok "Cluster reachable"

# ── Step 1: Install ESO via Helm ──────────────────────────────────────────
log_section "Installing External Secrets Operator (chart ${ESO_CHART_VERSION})"

if kubectl get deploy -n "${NAMESPACE}" external-secrets >/dev/null 2>&1; then
    log_ok "ESO already installed in namespace ${NAMESPACE}"
else
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would install external-secrets chart ${ESO_CHART_VERSION}"
    else
        helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
        helm repo update external-secrets
        helm upgrade --install external-secrets external-secrets/external-secrets \
            --version "${ESO_CHART_VERSION}" \
            --namespace "${NAMESPACE}" \
            --create-namespace \
            --set installCRDs=true \
            --wait --timeout 120s
        log_ok "ESO installed"
    fi
fi

# ── Step 2: Verify ESO is healthy ────────────────────────────────────────
if [ "$DRY_RUN" = false ]; then
    log_section "Verifying ESO health"

    ESO_READY=$(kubectl get deploy -n "${NAMESPACE}" external-secrets -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "${ESO_READY}" -ge 1 ] 2>/dev/null; then
        log_ok "ESO is running (${ESO_READY} ready replicas)"
    else
        log_warn "ESO not ready yet — check: kubectl get pods -n ${NAMESPACE}"
    fi

    # Verify CRDs installed
    for crd in externalsecrets.external-secrets.io secretstores.external-secrets.io clustersecretstores.external-secrets.io; do
        if kubectl get crd "$crd" >/dev/null 2>&1; then
            log_ok "CRD: $crd"
        else
            log_warn "CRD missing: $crd"
        fi
    done
fi

# ── Step 3: Deploy ClusterSecretStore ─────────────────────────────────────
log_section "Configuring ${BACKEND} backend"

case "$BACKEND" in
    aws)
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create ClusterSecretStore for AWS Secrets Manager (${AWS_REGION})"
        else
            cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    control: SC-12
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${AWS_REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: ${NAMESPACE}
EOF
            log_ok "ClusterSecretStore 'aws-secrets-manager' created"
            log_info "Ensure IRSA is configured for the external-secrets ServiceAccount"
        fi
        ;;

    vault)
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create ClusterSecretStore for Vault (${VAULT_ADDR})"
        else
            cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    control: SC-12
spec:
  provider:
    vault:
      server: "${VAULT_ADDR}"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: external-secrets
            namespace: ${NAMESPACE}
EOF
            log_ok "ClusterSecretStore 'vault' created"
            log_info "Ensure Vault K8s auth method is configured with role 'external-secrets'"
        fi
        ;;

    azure)
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create ClusterSecretStore for Azure Key Vault"
        else
            log_warn "Azure Key Vault requires manual configuration:"
            log_info "  1. Set AZURE_TENANT_ID and VAULT_URL in 03-templates/external-secrets/clustersecretstore.yaml"
            log_info "  2. kubectl apply -f 03-templates/external-secrets/clustersecretstore.yaml"
            log_info "  3. Ensure Workload Identity is configured for the external-secrets ServiceAccount"
        fi
        ;;

    fake)
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create ClusterSecretStore with Fake provider (lab/demo)"
        else
            cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: fake-backend
  labels:
    app.kubernetes.io/managed-by: gp-copilot
    environment: lab
spec:
  provider:
    fake:
      data:
        - key: "demo/db-password"
          value: "gp-lab-demo-password-2026"
        - key: "demo/api-key"
          value: "gp-lab-demo-apikey-abc123"
        - key: "demo/tls-cert"
          value: "-----BEGIN CERTIFICATE-----\nMIIBfake..."
EOF
            log_ok "ClusterSecretStore 'fake-backend' created (lab/demo mode)"
            log_info "Fake secrets available: demo/db-password, demo/api-key, demo/tls-cert"

            # Create a test ExternalSecret to prove the flow works
            if [ "$TEST_SECRET" = true ]; then
                log_info "Creating test ExternalSecret in default namespace..."
                cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: demo-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: fake-backend
    kind: ClusterSecretStore
  target:
    name: demo-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: demo/db-password
    - secretKey: API_KEY
      remoteRef:
        key: demo/api-key
EOF
                sleep 3
                SYNC_STATUS=$(kubectl get externalsecret demo-secrets -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
                if [ "$SYNC_STATUS" = "True" ]; then
                    log_ok "Test ExternalSecret synced — K8s Secret 'demo-secrets' created"
                    log_info "Verify: kubectl get secret demo-secrets -n default"
                else
                    log_warn "Test ExternalSecret status: ${SYNC_STATUS}"
                fi
            fi
        fi
        ;;
esac

# ── Step 4: Verify backend connectivity ───────────────────────────────────
if [ "$DRY_RUN" = false ] && [ "$BACKEND" != "azure" ]; then
    log_section "Verifying backend connectivity"

    STORE_NAME=""
    case "$BACKEND" in
        aws)   STORE_NAME="aws-secrets-manager" ;;
        vault) STORE_NAME="vault" ;;
        fake)  STORE_NAME="fake-backend" ;;
    esac

    # Wait briefly for status to populate
    sleep 3

    STORE_STATUS=$(kubectl get clustersecretstore "${STORE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$STORE_STATUS" = "True" ]; then
        log_ok "ClusterSecretStore '${STORE_NAME}' is Ready"
    else
        log_warn "ClusterSecretStore '${STORE_NAME}' status: ${STORE_STATUS}"
        log_info "Check auth configuration: kubectl describe clustersecretstore ${STORE_NAME}"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
log_section "Summary"
echo ""
echo "  Backend:             ${BACKEND}"
echo "  ESO namespace:       ${NAMESPACE}"
echo "  Chart version:       ${ESO_CHART_VERSION}"
echo ""
echo "  Next steps:"
echo "    1. Create an ExternalSecret:  kubectl apply -f 03-templates/external-secrets/externalsecret.yaml"
echo "    2. Verify sync:               kubectl get externalsecret -A"
echo "    3. Enforce ESO-only secrets:  kubectl apply -f 01-policies/kyverno/require-external-secrets.yaml"
echo ""
echo "  Templates: ${TEMPLATE_DIR}/"
echo ""
echo "Done."
