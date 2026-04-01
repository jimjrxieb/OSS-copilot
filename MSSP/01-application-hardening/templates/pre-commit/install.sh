#!/usr/bin/env bash
# Pre-commit hooks installation script
# Automatically installs pre-commit and configures hooks

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default config
CONFIG="full"
AUTO_UPDATE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage
usage() {
    cat <<EOF
Pre-commit hooks installation script

Usage: $0 [OPTIONS]

Options:
    -c, --config TYPE       Config type: full|minimal|python|javascript|go
                           (default: full)
    -u, --auto-update      Auto-update hooks to latest versions
    -h, --help             Show this help message

Examples:
    $0                     # Install full config
    $0 --config minimal    # Install minimal config
    $0 --auto-update       # Install and auto-update
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG="$2"
            shift 2
            ;;
        -u|--auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

echo "🚀 Pre-commit hooks installation"
echo ""

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
    echo -e "${YELLOW}pre-commit not found. Installing...${NC}"

    if command -v pip &> /dev/null; then
        pip install pre-commit
    elif command -v brew &> /dev/null; then
        brew install pre-commit
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y pre-commit
    else
        echo -e "${RED}Could not install pre-commit. Please install manually:${NC}"
        echo "  pip install pre-commit"
        echo "  brew install pre-commit"
        echo "  sudo apt install pre-commit"
        exit 1
    fi

    echo -e "${GREEN}✓ pre-commit installed${NC}"
fi

# Determine config file
case $CONFIG in
    full)
        CONFIG_FILE="$SCRIPT_DIR/.pre-commit-config.yaml"
        ;;
    minimal)
        CONFIG_FILE="$SCRIPT_DIR/minimal.yaml"
        ;;
    python)
        CONFIG_FILE="$SCRIPT_DIR/python.yaml"
        ;;
    javascript)
        CONFIG_FILE="$SCRIPT_DIR/javascript.yaml"
        ;;
    go)
        CONFIG_FILE="$SCRIPT_DIR/go.yaml"
        ;;
    *)
        echo -e "${RED}Unknown config type: $CONFIG${NC}"
        echo "Available: full, minimal, python, javascript, go"
        exit 1
        ;;
esac

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Copy config to repo root
echo "📋 Copying $CONFIG config..."
cp "$CONFIG_FILE" .pre-commit-config.yaml
echo -e "${GREEN}✓ Config copied${NC}"

# Auto-update if requested
if [ "$AUTO_UPDATE" = true ]; then
    echo "🔄 Updating hooks to latest versions..."
    pre-commit autoupdate
    echo -e "${GREEN}✓ Hooks updated${NC}"
fi

# Install hooks
echo "🔧 Installing pre-commit hooks..."
pre-commit install --install-hooks
echo -e "${GREEN}✓ Hooks installed${NC}"

# Run on all files as a test
echo ""
echo "🧪 Running hooks on all files (this may take a minute)..."
if pre-commit run --all-files; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
else
    echo -e "${YELLOW}⚠ Some checks failed. Review the output above.${NC}"
    echo "Fix the issues and run: git add . && git commit"
fi

echo ""
echo -e "${GREEN}✅ Pre-commit hooks installed successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Make a commit to test the hooks:"
echo "     git commit -m 'Test pre-commit hooks'"
echo ""
echo "  2. Skip hooks temporarily (not recommended):"
echo "     git commit --no-verify -m 'Emergency fix'"
echo ""
echo "  3. Run hooks manually:"
echo "     pre-commit run --all-files"
echo ""
