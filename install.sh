#!/bin/bash

# Installation script for Port Forward Manager
# Supports multiple Linux distributions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PACKAGE_NAME="port-forward"
VERSION="1.0.0"
INSTALL_PREFIX="/usr"
CONFIG_DIR="/etc/port-forward"
LOCALE_DIR="/usr/share/port-forward/locale"

# Output functions
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "$ID"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/fedora-release ]]; then
        echo "fedora"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Check and install dependencies
install_dependencies() {
    local distro="$1"

    print_step "Checking dependencies..."

    local packages="socat jq"
    local install_cmd=""

    case "$distro" in
        ubuntu|debian)
            install_cmd="apt-get install -y"
            ;;
        arch|manjaro|snug)
            install_cmd="pacman -S --noconfirm"
            ;;
        fedora)
            install_cmd="dnf install -y"
            ;;
        rhel|centos)
            install_cmd="yum install -y"
            ;;
        *)
            print_warn "Unknown distribution. Please install manually: $packages"
            return 1
            ;;
    esac

    # Check what's already installed
    local missing=()
    for pkg in $packages; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_info "Installing missing packages: ${missing[*]}"
        if ! $install_cmd "${missing[@]}"; then
            print_error "Failed to install dependencies"
            return 1
        fi
    else
        print_info "All dependencies are already installed"
    fi

    return 0
}


# Grant capabilities to socat for privileged ports
setup_capabilities() {
    local socat_path="$1"

    if [[ -f "$socat_path" ]]; then
        print_step "Setting capabilities for socat"

        # Check if setcap is available
        if command -v setcap >/dev/null 2>&1; then
            if setcap 'cap_net_bind_service=+ep' "$socat_path"; then
                print_info "Granted CAP_NET_BIND_SERVICE to socat"
            else
                print_warn "Failed to set capabilities for socat"
                print_warn "Ports below 1024 will require root privileges"
            fi
        else
            print_warn "setcap not found, capabilities cannot be set"
        fi
    else
        print_error "socat not found at $socat_path"
        return 1
    fi

    return 0
}

# Install main files
install_files() {
    print_step "Installing files..."

    # Create directories
    mkdir -p "$INSTALL_PREFIX/bin"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOCALE_DIR"
    mkdir -p "/var/log/port-forward"
    mkdir -p "/run/port-forward"

    # Install main script
    cp src/port-forward.sh "$INSTALL_PREFIX/bin/port-forward.sh"
    chmod 755 "$INSTALL_PREFIX/bin/port-forward.sh"

    # Create symlink for easier access
    ln -sf "$INSTALL_PREFIX/bin/port-forward.sh" "/usr/bin/port-forward"

    # Install configuration files
    cp src/port-forward.conf "$CONFIG_DIR/port-forward.conf.example"
    cp src/ports.conf.example "$CONFIG_DIR/ports.conf.example"

    # Install localization files
    cp src/locales/en.json "$LOCALE_DIR/"
    cp src/locales/uk.json "$LOCALE_DIR/"

    # Install systemd services
    cp systemd/port-forward.service /usr/lib/systemd/system/

    # Create default config files if they don't exist
    if [[ ! -f "$CONFIG_DIR/port-forward.conf" ]]; then
        cp "$CONFIG_DIR/port-forward.conf.example" "$CONFIG_DIR/port-forward.conf"
    fi

    if [[ ! -f "$CONFIG_DIR/ports.conf" ]]; then
        cp "$CONFIG_DIR/ports.conf.example" "$CONFIG_DIR/ports.conf"
    fi

    # Set permissions
    chmod 644 "$CONFIG_DIR"/*.conf "$CONFIG_DIR"/*.example
    chmod 755 "/var/log/port-forward" "/run/port-forward"

    # Create user/dirs via systemd (if available)
    if command -v systemd-sysusers >/dev/null 2>&1; then
        systemd-sysusers 2>/dev/null || true
    fi
    if command -v systemd-tmpfiles >/dev/null 2>&1; then
        systemd-tmpfiles --create 2>/dev/null || true
    fi

    print_info "Files installed successfully"
}

# Enable and start service
setup_service() {
    print_step "Setting up systemd service..."

    systemctl daemon-reload

    # Enable but don't start automatically
    if systemctl enable port-forward.service; then
        print_info "Service enabled to start at boot"
    else
        print_warn "Failed to enable service"
    fi

    # Ask if user wants to start the service now
    read -p "Start port-forward service now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if systemctl start port-forward.service; then
            print_info "Service started successfully"
        else
            print_error "Failed to start service"
            systemctl status port-forward.service
        fi
    fi
}

# Show post-install instructions
show_instructions() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "Port Forward Manager v${VERSION} installed successfully!"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Configuration files:"
    echo "  • Main config:      $CONFIG_DIR/port-forward.conf"
    echo "  • Ports config:     $CONFIG_DIR/ports.conf"
    echo ""
    echo "Quick start:"
    echo "  1. Edit port configuration:"
    echo "     sudo nano $CONFIG_DIR/ports.conf"
    echo ""
    echo "  2. Add your port forwards (example):"
    echo "     2222 192.168.122.10:22"
    echo "     8080 192.168.122.20:80"
    echo ""
    echo "  3. Start the service:"
    echo "     sudo systemctl start port-forward"
    echo ""
    echo "  4. Check status:"
    echo "     sudo systemctl status port-forward"
    echo "     sudo port-forward status"
    echo ""
    echo "  5. View logs:"
    echo "     sudo journalctl -u port-forward -f"
    echo ""
    echo "Documentation: https://github.com/yourusername/port-forward"
    echo "════════════════════════════════════════════════════════════════"
}

# Main installation function
main_install() {
    print_step "Starting Port Forward Manager installation v${VERSION}"

    # Detect distribution
    local distro=$(detect_distro)
    print_info "Detected distribution: $distro"

    # Install dependencies
    if ! install_dependencies "$distro"; then
        print_error "Dependency installation failed"
        exit 1
    fi

    # Create service user

    # Setup capabilities
    setup_capabilities "/usr/bin/socat"

    # Install files
    install_files

    # Setup systemd service
    setup_service

    # Show instructions
    show_instructions
}

# Cleanup on failure
cleanup() {
    print_error "Installation failed!"
    print_info "Cleaning up..."

    # Remove installed files
    rm -f "/usr/bin/port-forward.sh"
    rm -f "/usr/bin/port-forward"
    rm -f "/usr/lib/systemd/system/port-forward.service"

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    exit 1
}

# Set trap for cleanup
trap cleanup ERR

# Start installation
check_root
main_install

print_info "Installation completed successfully!"
exit 0
