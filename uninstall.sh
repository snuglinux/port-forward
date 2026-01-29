#!/bin/bash

# Uninstallation script for Port Forward Manager

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
INSTALL_PREFIX="/usr/local"
CONFIG_DIR="/etc/port-forward"
LOCALE_DIR="/usr/share/port-forward/locale"

# Output functions
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges"
        exit 1
    fi
}

# Stop and disable service
stop_service() {
    print_info "Stopping port-forward service..."

    if systemctl is-active --quiet port-forward.service; then
        systemctl stop port-forward.service
        print_info "Service stopped"
    fi

    if systemctl is-enabled --quiet port-forward.service; then
        systemctl disable port-forward.service
        print_info "Service disabled"
    fi

    # Stop all instance services
    for service in /etc/systemd/system/port-forward@*.service; do
        [[ -f "$service" ]] || continue
        local instance=$(basename "$service" | cut -d@ -f2 | cut -d. -f1)

        if systemctl is-active --quiet "port-forward@$instance"; then
            systemctl stop "port-forward@$instance"
        fi

        if systemctl is-enabled --quiet "port-forward@$instance"; then
            systemctl disable "port-forward@$instance"
        fi
    done

    systemctl daemon-reload
}

# Remove installed files
remove_files() {
    print_info "Removing installed files..."

    # Remove binaries
    rm -f "$INSTALL_PREFIX/bin/port-forward.sh"
    rm -f "/usr/bin/port-forward"

    # Remove systemd services
    rm -f "/usr/lib/systemd/system/port-forward.service"

    # Remove capabilities from socat
    if command -v setcap >/dev/null 2>&1; then
        setcap -r "/usr/bin/socat" 2>/dev/null || true
    fi

    # Ask about configuration files
    echo ""
    read -p "Remove configuration files in $CONFIG_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        print_info "Configuration files removed"
    else
        print_info "Configuration files preserved in $CONFIG_DIR"
    fi

    # Ask about localization files
    read -p "Remove localization files in $LOCALE_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "/usr/share/port-forward"
        print_info "Localization files removed"
    else
        print_info "Localization files preserved"
    fi

    # Ask about log files
    read -p "Remove log files in /var/log/port-forward? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "/var/log/port-forward"
        print_info "Log files removed"
    else
        print_info "Log files preserved"
    fi

    # Remove runtime directory
    rm -rf "/run/port-forward"
}

# Remove service user (optional)
remove_service_user() {
    local username="portforward"

    read -p "Remove service user '$username'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if id "$username" &>/dev/null; then
            userdel "$username" 2>/dev/null && print_info "User $username removed" || print_warn "Failed to remove user $username"
        else
            print_info "User $username does not exist"
        fi
    fi
}

# Main uninstallation function
main_uninstall() {
    print_info "Starting Port Forward Manager uninstallation"

    # Confirm uninstallation
    echo ""
    echo "This will uninstall Port Forward Manager and:"
    echo "  • Stop and disable the service"
    echo "  • Remove installed files"
    echo "  • Remove configuration files (optional)"
    echo "  • Remove service user (optional)"
    echo ""

    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi

    # Stop service first
    stop_service

    # Remove files
    remove_files

    # Remove user (optional)
    remove_service_user

    print_info "Uninstallation completed successfully!"
}

# Start uninstallation
check_root
main_uninstall
exit 0
