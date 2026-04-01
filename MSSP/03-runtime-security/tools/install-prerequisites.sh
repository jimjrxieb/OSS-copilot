#!/usr/bin/env bash
# install-prerequisites.sh
# Install all prerequisites needed to deploy runtime security (Falco + jsa-infrasec).
# Run this on the operator's machine before running deploy.sh.
#
# What gets installed:
#   - kubectl          (Kubernetes CLI)
#   - helm 3.x         (Kubernetes package manager)
#   - Falco Helm repo  (falcosecurity/charts)
#   - Python 3 + PyYAML (for tune-falco.sh and generate-report.py)
#   - jq               (JSON processing for logs/alerts)
#   - yq               (YAML processing for configs)
#
# Usage:
#   bash install-prerequisites.sh
#   bash install-prerequisites.sh --check        (check only, don't install)
#   bash install-prerequisites.sh --skip-python   (skip Python/pip installs)
#   bash install-prerequisites.sh --skip-kubectl   (skip kubectl if already managed)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- Versions (pin to latest-1 for stability) ---
# Strategy: pin to second-to-latest release. Update monthly.
# We operate in staging — enterprise tools own prod.
# Last updated: 2026-04-01
JQ_VERSION="1.7.1"
YQ_VERSION="4.44.1"
HELM_VERSION="3.16.4"

CHECK_ONLY=false
SKIP_PYTHON=false
SKIP_KUBECTL=false
PASS=0; WARN=0; FAIL=0; INSTALLED=0

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Install prerequisites for 03-RUNTIME-SECURITY (Falco + jsa-infrasec)."
  echo ""
  echo "Options:"
  echo "  --check          Check what's installed/missing, don't install anything"
  echo "  --skip-python    Skip Python 3 and pip package installs"
  echo "  --skip-kubectl   Skip kubectl install (if managed externally)"
  echo "  --help, -h       Show this help"
  echo ""
  echo "Examples:"
  echo "  bash install-prerequisites.sh              # install everything"
  echo "  bash install-prerequisites.sh --check      # audit only"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)        CHECK_ONLY=true; shift ;;
    --skip-python)  SKIP_PYTHON=true; shift ;;
    --skip-kubectl) SKIP_KUBECTL=true; shift ;;
    --help|-h)      usage; exit 0 ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
  esac
done

# ── Detect OS and package manager ─────────────────────────────────────────────
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_LIKE="${ID_LIKE:-$ID}"
  elif [[ "$(uname)" == "Darwin" ]]; then
    OS_ID="macos"
    OS_LIKE="macos"
  else
    OS_ID="unknown"
    OS_LIKE="unknown"
  fi

  if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
  elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
  elif command -v brew &>/dev/null; then
    PKG_MGR="brew"
  elif command -v apk &>/dev/null; then
    PKG_MGR="apk"
  else
    PKG_MGR="unknown"
  fi
}

check() {
  local label="$1" result="$2" detail="${3:-}"
  case "$result" in
    PASS) echo -e "  ${GREEN}✓${NC}  $label${detail:+ — $detail}"; PASS=$((PASS+1)) ;;
    WARN) echo -e "  ${YELLOW}⚠${NC}  $label${detail:+ — $detail}"; WARN=$((WARN+1)) ;;
    FAIL) echo -e "  ${RED}✗${NC}  $label${detail:+ — $detail}"; FAIL=$((FAIL+1)) ;;
    NEW)  echo -e "  ${GREEN}+${NC}  $label${detail:+ — $detail}"; INSTALLED=$((INSTALLED+1)) ;;
  esac
}

# ── Install functions ─────────────────────────────────────────────────────────

install_kubectl() {
  echo -e "  Installing kubectl..."
  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
  esac

  local KUBE_VERSION
  KUBE_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)

  if [[ "$(uname)" == "Darwin" ]]; then
    curl -sLO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/darwin/${ARCH}/kubectl"
  else
    curl -sLO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubectl"
  fi

  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/kubectl
  check "kubectl" NEW "$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
}

install_helm() {
  echo -e "  Installing helm ${HELM_VERSION}..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION="v${HELM_VERSION}" bash
  check "helm" NEW "${HELM_VERSION}"
}

install_jq() {
  echo -e "  Installing jq..."
  case "$PKG_MGR" in
    apt)  sudo apt-get update -qq && sudo apt-get install -y -qq jq ;;
    dnf)  sudo dnf install -y -q jq ;;
    yum)  sudo yum install -y -q jq ;;
    brew) brew install jq ;;
    apk)  sudo apk add --quiet jq ;;
    *)
      # Binary install fallback
      local ARCH
      ARCH=$(uname -m)
      case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        arm64)   ARCH="arm64" ;;
      esac
      local JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${ARCH}"
      if [[ "$(uname)" == "Darwin" ]]; then
        JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-${ARCH}"
      fi
      curl -sLo jq "$JQ_URL"
      chmod +x jq
      sudo mv jq /usr/local/bin/jq
      ;;
  esac
  check "jq" NEW "$(jq --version 2>/dev/null)"
}

install_yq() {
  echo -e "  Installing yq..."
  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
  esac

  local YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}"
  if [[ "$(uname)" == "Darwin" ]]; then
    YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_darwin_${ARCH}"
  fi
  curl -sLo yq "$YQ_URL"
  chmod +x yq
  sudo mv yq /usr/local/bin/yq
  check "yq" NEW "$(yq --version 2>/dev/null)"
}

install_python_deps() {
  echo -e "  Installing Python packages (pyyaml, requests)..."
  pip3 install --quiet --user "pyyaml>=6.0,<7.0" "requests>=2.31,<3.0" 2>/dev/null \
    || pip install --quiet --user "pyyaml>=6.0,<7.0" "requests>=2.31,<3.0" 2>/dev/null \
    || { check "pip packages" WARN "pip install failed — install manually: pip3 install pyyaml requests"; return; }
  check "pip packages" NEW "pyyaml, requests"
}

# ── Main ──────────────────────────────────────────────────────────────────────

detect_os

echo ""
echo -e "${BLUE}=== Runtime Security Prerequisites ===${NC}"
echo -e "  OS: ${OS_ID} (pkg: ${PKG_MGR})"
echo ""

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo -e "${BLUE}Mode: CHECK ONLY (no installs)${NC}"
  echo ""
fi

# ── 1. kubectl ────────────────────────────────────────────────────────────────
echo -e "${BLUE}Kubernetes CLI${NC}"

if [[ "$SKIP_KUBECTL" == "true" ]]; then
  check "kubectl" WARN "skipped (--skip-kubectl)"
elif command -v kubectl &>/dev/null; then
  KUBECTL_VER=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)
  check "kubectl" PASS "$KUBECTL_VER"
elif [[ "$CHECK_ONLY" == "true" ]]; then
  check "kubectl" FAIL "not installed"
else
  install_kubectl
fi

# Cluster connectivity (check only, never install)
if command -v kubectl &>/dev/null; then
  if kubectl cluster-info &>/dev/null; then
    CTX=$(kubectl config current-context 2>/dev/null || echo "unknown")
    check "cluster access" PASS "$CTX"
  else
    check "cluster access" WARN "kubectl installed but no cluster reachable — configure kubeconfig before deploy"
  fi
fi
echo ""

# ── 2. Helm ───────────────────────────────────────────────────────────────────
echo -e "${BLUE}Helm${NC}"

if command -v helm &>/dev/null; then
  HELM_VER=$(helm version --short 2>/dev/null)
  # Check for Helm 3
  if [[ "$HELM_VER" == v3* ]]; then
    check "helm" PASS "$HELM_VER"
  else
    check "helm" WARN "$HELM_VER — helm 3.x required, you have helm 2.x"
  fi
elif [[ "$CHECK_ONLY" == "true" ]]; then
  check "helm" FAIL "not installed"
else
  install_helm
fi

# Falco Helm repo
if command -v helm &>/dev/null; then
  if helm repo list 2>/dev/null | grep -q falcosecurity; then
    check "falco helm repo" PASS "falcosecurity/charts"
  elif [[ "$CHECK_ONLY" == "true" ]]; then
    check "falco helm repo" FAIL "not added"
  else
    echo -e "  Adding Falco helm repo..."
    helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
    helm repo update falcosecurity 2>/dev/null || true
    check "falco helm repo" NEW "falcosecurity/charts"
  fi
fi
echo ""

# ── 3. jq ─────────────────────────────────────────────────────────────────────
echo -e "${BLUE}JSON/YAML tools${NC}"

if command -v jq &>/dev/null; then
  check "jq" PASS "$(jq --version 2>/dev/null)"
elif [[ "$CHECK_ONLY" == "true" ]]; then
  check "jq" FAIL "not installed — needed for log parsing and alert replay"
else
  install_jq
fi

# ── 4. yq ─────────────────────────────────────────────────────────────────────
if command -v yq &>/dev/null; then
  check "yq" PASS "$(yq --version 2>/dev/null)"
elif [[ "$CHECK_ONLY" == "true" ]]; then
  check "yq" WARN "not installed — optional, useful for editing Helm values"
else
  install_yq
fi
echo ""

# ── 5. Python 3 ──────────────────────────────────────────────────────────────
echo -e "${BLUE}Python${NC}"

if [[ "$SKIP_PYTHON" == "true" ]]; then
  check "python3" WARN "skipped (--skip-python)"
elif command -v python3 &>/dev/null; then
  PY_VER=$(python3 --version 2>/dev/null)
  check "python3" PASS "$PY_VER"

  # Check for required packages
  if python3 -c "import yaml" &>/dev/null; then
    check "pyyaml" PASS "installed"
  elif [[ "$CHECK_ONLY" == "true" ]]; then
    check "pyyaml" WARN "not installed — needed for tune-falco.sh YAML validation"
  else
    install_python_deps
  fi

  if python3 -c "import requests" &>/dev/null; then
    check "requests" PASS "installed"
  elif [[ "$CHECK_ONLY" == "true" ]]; then
    check "requests" WARN "not installed — needed for generate-report.py"
  else
    if ! python3 -c "import yaml" &>/dev/null; then
      : # already handled above
    else
      install_python_deps
    fi
  fi
elif [[ "$CHECK_ONLY" == "true" ]]; then
  check "python3" WARN "not installed — needed for tune-falco.sh and generate-report.py"
else
  echo -e "  ${YELLOW}⚠${NC}  Python 3 not found. Install via your package manager:"
  case "$PKG_MGR" in
    apt)  echo "     sudo apt-get install python3 python3-pip" ;;
    dnf)  echo "     sudo dnf install python3 python3-pip" ;;
    yum)  echo "     sudo yum install python3 python3-pip" ;;
    brew) echo "     brew install python3" ;;
    apk)  echo "     sudo apk add python3 py3-pip" ;;
    *)    echo "     Install Python 3.8+ from https://www.python.org/downloads/" ;;
  esac
  WARN=$((WARN+1))
fi
echo ""

# ── 6. Optional: Falco event generator (for testing) ─────────────────────────
echo -e "${BLUE}Optional tools${NC}"

if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
  # Check if event-generator image is available
  check "falco event-generator" WARN "run on-demand: kubectl run falco-event-generator --image=falcosecurity/event-generator --rm -it -- run"
else
  check "falco event-generator" WARN "needs cluster access — used for testing Falco rules"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "============================================================"
if [[ "$CHECK_ONLY" == "true" ]]; then
  echo -e "  ${GREEN}PASS${NC}: $PASS   ${YELLOW}WARN${NC}: $WARN   ${RED}MISSING${NC}: $FAIL"
else
  echo -e "  ${GREEN}PASS${NC}: $PASS   ${GREEN}INSTALLED${NC}: $INSTALLED   ${YELLOW}WARN${NC}: $WARN   ${RED}FAIL${NC}: $FAIL"
fi
echo "============================================================"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}Fix FAIL items above before running deploy.sh${NC}"
  exit 1
elif [[ "$CHECK_ONLY" == "true" && "$WARN" -gt 0 ]]; then
  echo -e "${YELLOW}Run without --check to install missing prerequisites${NC}"
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "${YELLOW}Review WARN items above — some may need manual install${NC}"
else
  echo -e "${GREEN}All prerequisites installed. Ready to deploy:${NC}"
  echo ""
  echo "  bash tools/deploy.sh"
  echo "  bash tools/deploy.sh --values 03-templates/deployment-configs/aws-eks.yaml"
fi
echo ""
