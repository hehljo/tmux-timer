#!/bin/bash
# install.sh - Installs timer.sh as /usr/local/bin/timer
# Also installs missing dependencies (at, tmux) and enables atd.
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

INSTALL_DEPS=true
for arg in "$@"; do
    case "$arg" in
        --no-deps) INSTALL_DEPS=false ;;
        -h|--help)
            echo "Usage: sudo ./install.sh [--no-deps]"
            echo "  --no-deps   Do not install missing dependencies, only deploy timer."
            exit 0
            ;;
    esac
done

echo -e "${CYAN}=== tmux-timer installer ===${NC}"
echo ""

if [ ! -f "$SOURCE" ]; then
    echo -e "${RED}Error: timer.sh not found at $SOURCE${NC}"
    exit 1
fi

# --- helpers ---------------------------------------------------------------

need_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: $1 requires root.${NC}"
        echo "Re-run with: sudo ./install.sh"
        exit 1
    fi
}

detect_pm() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    fi
    if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
    if command -v dnf       >/dev/null 2>&1; then echo dnf; return; fi
    if command -v yum       >/dev/null 2>&1; then echo yum; return; fi
    if command -v pacman    >/dev/null 2>&1; then echo pacman; return; fi
    if command -v zypper    >/dev/null 2>&1; then echo zypper; return; fi
    if command -v apk       >/dev/null 2>&1; then echo apk; return; fi
    if command -v brew      >/dev/null 2>&1; then echo brew; return; fi
    echo "unknown"
}

# Map generic package name → distro-specific package name
pkg_name() {
    local pm="$1" generic="$2"
    case "$pm:$generic" in
        # at
        apk:at)        echo "at" ;;
        *:at)          echo "at" ;;
        # tmux is "tmux" everywhere we care about
        *:tmux)        echo "tmux" ;;
        *)             echo "$generic" ;;
    esac
}

install_pkgs() {
    local pm="$1"; shift
    local pkgs=("$@")
    [ ${#pkgs[@]} -eq 0 ] && return 0
    echo -e "${CYAN}Installing via $pm:${NC} ${pkgs[*]}"
    case "$pm" in
        apt)    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" ;;
        dnf)    dnf install -y "${pkgs[@]}" ;;
        yum)    yum install -y "${pkgs[@]}" ;;
        pacman) pacman -Sy --noconfirm --needed "${pkgs[@]}" ;;
        zypper) zypper --non-interactive install "${pkgs[@]}" ;;
        apk)    apk add --no-cache "${pkgs[@]}" ;;
        brew)
            if [ "$EUID" -eq 0 ]; then
                echo -e "${RED}Error: Homebrew refuses to run as root.${NC}"
                echo "Run installer without sudo, or install deps manually:"
                echo "  brew install ${pkgs[*]}"
                exit 1
            fi
            brew install "${pkgs[@]}"
            ;;
        *)
            echo -e "${RED}Error: unknown package manager — install manually: ${pkgs[*]}${NC}"
            return 1
            ;;
    esac
}

enable_atd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}No systemctl found — start atd manually for your init system.${NC}"
        return
    fi
    # Service name is "atd" on most distros, "atd" or "at" on some others.
    local svc=""
    for candidate in atd at; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${candidate}\.service"; then
            svc="$candidate"; break
        fi
    done
    if [ -z "$svc" ]; then
        echo -e "${YELLOW}Could not find atd service unit — skipping enable.${NC}"
        return
    fi
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${CYAN}Enabling and starting $svc...${NC}"
        systemctl enable --now "$svc"
    else
        echo -e "${GREEN}✓ $svc already running${NC}"
    fi
}

# --- dependency phase ------------------------------------------------------

MISSING=()
command -v at   >/dev/null 2>&1 || MISSING+=("at")
command -v tmux >/dev/null 2>&1 || MISSING+=("tmux")

if [ ${#MISSING[@]} -gt 0 ]; then
    if [ "$INSTALL_DEPS" = false ]; then
        echo -e "${YELLOW}Missing dependencies (skipping due to --no-deps):${NC} ${MISSING[*]}"
    else
        PM=$(detect_pm)
        if [ "$PM" = "unknown" ]; then
            echo -e "${RED}Could not detect package manager.${NC}"
            echo "Install manually: ${MISSING[*]}"
            exit 1
        fi
        if [ "$PM" != "brew" ]; then
            need_root "installing packages with $PM"
        fi
        PKGS=()
        for m in "${MISSING[@]}"; do PKGS+=("$(pkg_name "$PM" "$m")"); done
        install_pkgs "$PM" "${PKGS[@]}"
    fi
else
    echo -e "${GREEN}✓ Dependencies already present${NC}"
fi

# atd service
if [ "$INSTALL_DEPS" = true ]; then
    if [ "$EUID" -eq 0 ]; then
        enable_atd
    else
        echo -e "${YELLOW}Skipping atd service enable (not root).${NC}"
        echo "Run: sudo systemctl enable --now atd"
    fi
fi

echo ""

# --- deploy phase ----------------------------------------------------------

if [ ! -w "$INSTALL_DIR" ]; then
    echo -e "${RED}Error: $INSTALL_DIR is not writable.${NC}"
    echo "Re-run with sudo: sudo ./install.sh"
    exit 1
fi

TARGET="$INSTALL_DIR/$INSTALL_NAME"
install -m 0755 "$SOURCE" "$TARGET"

echo -e "${GREEN}✓ Installed:${NC} $TARGET"
echo ""
echo "Run with:"
echo -e "  ${CYAN}timer${NC}"
echo ""
echo "Uninstall:"
echo -e "  ${CYAN}sudo rm $TARGET${NC}"
