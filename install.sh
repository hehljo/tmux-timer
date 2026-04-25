#!/bin/bash
# install.sh - Installs timer.sh as /usr/local/bin/timer
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
INSTALL_NAME="timer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/timer.sh"

echo -e "${CYAN}=== tmux-timer installer ===${NC}"
echo ""

# Source check
if [ ! -f "$SOURCE" ]; then
    echo -e "${RED}Error: timer.sh not found at $SOURCE${NC}"
    exit 1
fi

# Dependency checks
MISSING=()
command -v at >/dev/null 2>&1 || MISSING+=("at")
command -v tmux >/dev/null 2>&1 || MISSING+=("tmux")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warning: missing dependencies: ${MISSING[*]}${NC}"
    echo "Install on Debian/Ubuntu:"
    echo "  sudo apt install ${MISSING[*]}"
    echo ""
fi

# atd service check (non-fatal warning)
if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet atd 2>/dev/null; then
        echo -e "${YELLOW}Warning: atd service is not running.${NC}"
        echo "Enable with: sudo systemctl enable --now atd"
        echo ""
    fi
fi

# Permission check
if [ ! -w "$INSTALL_DIR" ]; then
    echo -e "${RED}Error: $INSTALL_DIR is not writable.${NC}"
    echo "Re-run with sudo:"
    echo "  sudo ./install.sh"
    exit 1
fi

# Install
TARGET="$INSTALL_DIR/$INSTALL_NAME"
install -m 0755 "$SOURCE" "$TARGET"

echo -e "${GREEN}✓ Installed:${NC} $TARGET"
echo ""
echo "Run with:"
echo -e "  ${CYAN}timer${NC}"
echo ""
echo "Uninstall:"
echo -e "  ${CYAN}sudo rm $TARGET${NC}"
