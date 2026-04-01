#!/usr/bin/env bash
# install-scanners.sh — Install all scanner dependencies for GP-Consulting engagements.
#
# Supports: Linux (Debian/Ubuntu, RHEL/CentOS/Amazon Linux, Alpine), macOS
# Detects:  OS, architecture (amd64/arm64), package manager
#
# Usage:
#   bash install-scanners.sh              # Install everything
#   bash install-scanners.sh --check      # Check what's installed/missing
#   bash install-scanners.sh --app-sec    # Only 01-APP-SEC tools
#   bash install-scanners.sh --cluster    # Only 02-CLUSTER-HARDENING tools
#
# Tools installed:
#   01-APP-SEC:            gitleaks, semgrep, bandit, trivy, grype, hadolint, checkov
#   02-CLUSTER-HARDENING:  kubescape, kube-bench, polaris, conftest, helm
#   Shared:                kubectl (checked, not installed — requires manual setup)

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Versions (pin to latest-1 for stability) ---
# Strategy: pin to second-to-latest release. Update monthly.
# Latest-1 gives 2-4 weeks of community testing before we adopt.
# We operate in staging — enterprise tools own prod.
#
# To update: check releases, bump version, test in staging, commit.
# Last updated: 2026-04-01
GITLEAKS_VERSION="8.18.4"
TRIVY_VERSION="0.58.2"
GRYPE_VERSION="0.84.0"
HADOLINT_VERSION="2.12.0"
KUBESCAPE_VERSION="3.0.18"
KUBE_BENCH_VERSION="0.8.0"
POLARIS_VERSION="9.5.0"
CONFTEST_VERSION="0.56.0"
HELM_VERSION="3.16.4"
SEMGREP_VERSION="1.52.0"
BANDIT_VERSION="1.8.6"
CHECKOV_VERSION="3.2.471"

# --- Parse args ---
CHECK_ONLY=false
INSTALL_APP_SEC=true
INSTALL_CLUSTER=true

for arg in "$@"; do
    case "$arg" in
        --check)     CHECK_ONLY=true ;;
        --app-sec)   INSTALL_CLUSTER=false ;;
        --cluster)   INSTALL_APP_SEC=false ;;
        -h|--help)
            head -14 "$0" | tail -12
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            echo "Usage: bash install-scanners.sh [--check] [--app-sec] [--cluster]"
            exit 1
            ;;
    esac
done

# --- Detect OS and architecture ---
detect_platform() {
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"

    case "$OS" in
        linux*)  OS="linux" ;;
        darwin*) OS="darwin" ;;
        *)       echo -e "${RED}Unsupported OS: $OS${NC}"; exit 1 ;;
    esac

    case "$ARCH" in
        x86_64|amd64)   ARCH="amd64" ;;
        aarch64|arm64)  ARCH="arm64" ;;
        *)              echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac

    # Detect package manager
    PKG_MGR="none"
    if command -v apt-get &>/dev/null; then
        PKG_MGR="apt"
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
    elif command -v apk &>/dev/null; then
        PKG_MGR="apk"
    elif command -v brew &>/dev/null; then
        PKG_MGR="brew"
    fi
}

# --- Helpers ---
log_ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
log_miss()  { echo -e "  ${RED}✗${NC} $1"; }
log_skip()  { echo -e "  ${YELLOW}⊘${NC} $1"; }
log_info()  { echo -e "${BLUE}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}$1${NC}"; }

INSTALL_DIR="/usr/local/bin"
TEMP_DIR=""

setup_temp() {
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT
}

need_sudo() {
    if [[ ! -w "$INSTALL_DIR" ]]; then
        echo "sudo"
    fi
}

install_binary() {
    local src="$1"
    local name="$2"
    local sudo_cmd
    sudo_cmd="$(need_sudo)"
    $sudo_cmd install -m 755 "$src" "$INSTALL_DIR/$name"
}

# --- Check what's installed ---
check_tool() {
    local name="$1"
    local cmd="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        local ver
        ver="$($cmd --version 2>&1 | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "?")"
        log_ok "$name ($ver)"
        return 0
    else
        log_miss "$name — not installed"
        return 1
    fi
}

run_check() {
    echo ""
    log_info "=== Scanner Dependency Check ==="
    echo ""

    local installed=0 missing=0

    echo "  Prerequisites:"
    if check_tool "python3" "python3"; then installed=$((installed+1)); else missing=$((missing+1)); fi
    if check_tool "pip" "pip3"; then installed=$((installed+1)); else missing=$((missing+1)); fi
    if check_tool "git" "git"; then installed=$((installed+1)); else missing=$((missing+1)); fi
    if check_tool "kubectl" "kubectl"; then installed=$((installed+1)); else missing=$((missing+1)); fi
    if check_tool "curl" "curl"; then installed=$((installed+1)); else missing=$((missing+1)); fi
    echo ""

    if $INSTALL_APP_SEC; then
        echo "  01-APP-SEC scanners:"
        if check_tool "gitleaks" "gitleaks"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "semgrep" "semgrep"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "bandit" "bandit"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "trivy" "trivy"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "grype" "grype"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "hadolint" "hadolint"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "checkov" "checkov"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        echo ""
    fi

    if $INSTALL_CLUSTER; then
        echo "  02-CLUSTER-HARDENING tools:"
        if check_tool "kubescape" "kubescape"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "kube-bench" "kube-bench"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "polaris" "polaris"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "conftest" "conftest"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        if check_tool "helm" "helm"; then installed=$((installed+1)); else missing=$((missing+1)); fi
        echo ""
    fi

    echo -e "  ${GREEN}Installed: $installed${NC}  ${RED}Missing: $missing${NC}"
    echo ""

    if [[ $missing -eq 0 ]]; then
        echo -e "  ${GREEN}All tools installed. Ready to run engagements.${NC}"
    else
        echo -e "  ${YELLOW}Run without --check to install missing tools.${NC}"
    fi
    echo ""
}

# =====================================================================
# INSTALLERS — one function per tool
# =====================================================================

install_gitleaks() {
    if command -v gitleaks &>/dev/null; then log_ok "gitleaks (already installed)"; return; fi
    log_info "  Installing gitleaks ${GITLEAKS_VERSION}..."

    local url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${OS}_${ARCH}.tar.gz"
    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" gitleaks
    install_binary "$TEMP_DIR/gitleaks" "gitleaks"
    log_ok "gitleaks ${GITLEAKS_VERSION}"
}

install_semgrep() {
    if command -v semgrep &>/dev/null; then log_ok "semgrep (already installed)"; return; fi
    log_info "  Installing semgrep..."

    pip3 install --quiet "semgrep==${SEMGREP_VERSION}"
    log_ok "semgrep ${SEMGREP_VERSION}"
}

install_bandit() {
    if command -v bandit &>/dev/null; then log_ok "bandit (already installed)"; return; fi
    log_info "  Installing bandit..."

    pip3 install --quiet "bandit==${BANDIT_VERSION}"
    log_ok "bandit ${BANDIT_VERSION}"
}

install_trivy() {
    if command -v trivy &>/dev/null; then log_ok "trivy (already installed)"; return; fi
    log_info "  Installing trivy ${TRIVY_VERSION}..."

    local url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_${OS^}-${ARCH}.tar.gz"
    # Trivy uses "Linux" not "linux" in release names
    if [[ "$OS" == "linux" ]]; then
        url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
        [[ "$ARCH" == "arm64" ]] && url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"
    elif [[ "$OS" == "darwin" ]]; then
        url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_macOS-64bit.tar.gz"
        [[ "$ARCH" == "arm64" ]] && url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_macOS-ARM64.tar.gz"
    fi

    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" trivy
    install_binary "$TEMP_DIR/trivy" "trivy"
    log_ok "trivy ${TRIVY_VERSION}"
}

install_grype() {
    if command -v grype &>/dev/null; then log_ok "grype (already installed)"; return; fi
    log_info "  Installing grype ${GRYPE_VERSION}..."

    local os_name="${OS}"
    [[ "$OS" == "darwin" ]] && os_name="darwin"
    local url="https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_${os_name}_${ARCH}.tar.gz"

    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" grype
    install_binary "$TEMP_DIR/grype" "grype"
    log_ok "grype ${GRYPE_VERSION}"
}

install_hadolint() {
    if command -v hadolint &>/dev/null; then log_ok "hadolint (already installed)"; return; fi
    log_info "  Installing hadolint ${HADOLINT_VERSION}..."

    local bin_name="hadolint-Linux-x86_64"
    [[ "$OS" == "darwin" ]] && bin_name="hadolint-Darwin-x86_64"
    [[ "$ARCH" == "arm64" && "$OS" == "linux" ]] && bin_name="hadolint-Linux-arm64"
    [[ "$ARCH" == "arm64" && "$OS" == "darwin" ]] && bin_name="hadolint-Darwin-arm64"

    local url="https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/${bin_name}"
    curl -fsSL -o "$TEMP_DIR/hadolint" "$url"
    install_binary "$TEMP_DIR/hadolint" "hadolint"
    log_ok "hadolint ${HADOLINT_VERSION}"
}

install_checkov() {
    if command -v checkov &>/dev/null; then log_ok "checkov (already installed)"; return; fi
    log_info "  Installing checkov..."

    pip3 install --quiet "checkov==${CHECKOV_VERSION}"
    log_ok "checkov ${CHECKOV_VERSION}"
}

install_kubescape() {
    if command -v kubescape &>/dev/null; then log_ok "kubescape (already installed)"; return; fi
    log_info "  Installing kubescape ${KUBESCAPE_VERSION}..."

    local url="https://github.com/kubescape/kubescape/releases/download/v${KUBESCAPE_VERSION}/kubescape-ubuntu-latest"
    [[ "$OS" == "darwin" ]] && url="https://github.com/kubescape/kubescape/releases/download/v${KUBESCAPE_VERSION}/kubescape-macos-latest"
    [[ "$ARCH" == "arm64" && "$OS" == "linux" ]] && url="https://github.com/kubescape/kubescape/releases/download/v${KUBESCAPE_VERSION}/kubescape-ubuntu-latest-arm64"

    curl -fsSL -o "$TEMP_DIR/kubescape" "$url"
    install_binary "$TEMP_DIR/kubescape" "kubescape"
    log_ok "kubescape ${KUBESCAPE_VERSION}"
}

install_kube_bench() {
    if command -v kube-bench &>/dev/null; then log_ok "kube-bench (already installed)"; return; fi
    log_info "  Installing kube-bench ${KUBE_BENCH_VERSION}..."

    local url="https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_${OS}_${ARCH}.tar.gz"
    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" kube-bench
    install_binary "$TEMP_DIR/kube-bench" "kube-bench"
    log_ok "kube-bench ${KUBE_BENCH_VERSION}"
}

install_polaris() {
    if command -v polaris &>/dev/null; then log_ok "polaris (already installed)"; return; fi
    log_info "  Installing polaris ${POLARIS_VERSION}..."

    local url="https://github.com/FairwindsOps/polaris/releases/download/${POLARIS_VERSION}/polaris_${OS}_${ARCH}.tar.gz"
    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" polaris
    install_binary "$TEMP_DIR/polaris" "polaris"
    log_ok "polaris ${POLARIS_VERSION}"
}

install_conftest() {
    if command -v conftest &>/dev/null; then log_ok "conftest (already installed)"; return; fi
    log_info "  Installing conftest ${CONFTEST_VERSION}..."

    local os_name="Linux"
    [[ "$OS" == "darwin" ]] && os_name="Darwin"
    local arch_name="x86_64"
    [[ "$ARCH" == "arm64" ]] && arch_name="arm64"

    local url="https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_${os_name}_${arch_name}.tar.gz"
    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" conftest
    install_binary "$TEMP_DIR/conftest" "conftest"
    log_ok "conftest ${CONFTEST_VERSION}"
}

install_helm() {
    if command -v helm &>/dev/null; then log_ok "helm (already installed)"; return; fi
    log_info "  Installing helm ${HELM_VERSION}..."

    local url="https://get.helm.sh/helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
    curl -fsSL "$url" | tar xz -C "$TEMP_DIR" "${OS}-${ARCH}/helm"
    install_binary "$TEMP_DIR/${OS}-${ARCH}/helm" "helm"
    log_ok "helm ${HELM_VERSION}"
}

# =====================================================================
# MAIN
# =====================================================================

detect_platform

echo ""
echo -e "${BLUE}=== GP-Consulting Scanner Installer ===${NC}"
echo "  OS:   $OS ($ARCH)"
echo "  Pkg:  $PKG_MGR"
echo ""

if $CHECK_ONLY; then
    run_check
    exit 0
fi

# --- Prerequisite checks ---
PREREQ_MISSING=false

if ! command -v python3 &>/dev/null; then
    log_miss "python3 is required for pip-based tools (semgrep, bandit, checkov)"
    PREREQ_MISSING=true
fi

if ! command -v pip3 &>/dev/null; then
    log_miss "pip3 is required for Python tools"
    PREREQ_MISSING=true
fi

if ! command -v curl &>/dev/null; then
    log_miss "curl is required to download binaries"
    PREREQ_MISSING=true
fi

if ! command -v kubectl &>/dev/null; then
    log_warn "  kubectl not found — cluster tools need it. Install separately."
fi

if $PREREQ_MISSING; then
    echo ""
    echo -e "${RED}Install missing prerequisites first:${NC}"
    case "$PKG_MGR" in
        apt) echo "  sudo apt update && sudo apt install -y python3 python3-pip curl" ;;
        yum) echo "  sudo yum install -y python3 python3-pip curl" ;;
        dnf) echo "  sudo dnf install -y python3 python3-pip curl" ;;
        apk) echo "  apk add python3 py3-pip curl" ;;
        brew) echo "  brew install python3 curl" ;;
        *)   echo "  Install python3, pip3, and curl for your OS." ;;
    esac
    exit 1
fi

setup_temp

# --- Install 01-APP-SEC tools ---
if $INSTALL_APP_SEC; then
    echo -e "${CYAN}01-APP-SEC scanners:${NC}"
    install_gitleaks
    install_semgrep
    install_bandit
    install_trivy
    install_grype
    install_hadolint
    install_checkov
    echo ""
fi

# --- Install 02-CLUSTER-HARDENING tools ---
if $INSTALL_CLUSTER; then
    echo -e "${CYAN}02-CLUSTER-HARDENING tools:${NC}"
    install_kubescape
    install_kube_bench
    install_polaris
    install_conftest
    install_helm
    echo ""
fi

# --- Summary ---
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
run_check
