.PHONY: all install uninstall clean build-deb build-arch test lint help

# Variables
PACKAGE_NAME := port-forward
VERSION := 2.0.0
ARCH := $(shell uname -m)
BUILD_DIR := build
DIST_DIR := dist

# Default target
all: install

# Local installation
install:
    @echo "Installing Port Forward Manager locally..."
    chmod +x install.sh
    sudo ./install.sh

# Local uninstallation
uninstall:
    @echo "Uninstalling Port Forward Manager..."
    chmod +x uninstall.sh
    sudo ./uninstall.sh

# Clean build artifacts
clean:
    @echo "Cleaning build directories..."
    rm -rf $(BUILD_DIR) $(DIST_DIR) *.deb *.rpm *.tar.gz *.zst

# Create build directory
$(BUILD_DIR):
    mkdir -p $(BUILD_DIR)

# Build DEB package (Debian/Ubuntu)
build-deb: $(BUILD_DIR)
    @echo "Building DEB package..."
    mkdir -p $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)

    # Copy all source files
    cp -r src systemd install.sh uninstall.sh README.md LICENSE \
       $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)/

    # Create DEBIAN directory
    mkdir -p $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)/DEBIAN

    # Create control file
    cat > $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)/DEBIAN/control <<- EOF
    Package: $(PACKAGE_NAME)
    Version: $(VERSION)
    Architecture: $(ARCH)
    Maintainer: Your Name <your@email.com>
    Description: Universal port forwarding manager using socat
     Port Forward Manager provides a simple way to forward TCP/UDP ports
     using socat with systemd integration, logging, and multi-language support.
    Depends: socat, jq, bash
    Recommends: systemd
    Section: net
    Priority: optional
    Homepage: https://github.com/yourusername/port-forward
    EOF

    # Create postinst script
    cat > $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)/DEBIAN/postinst <<- 'EOF'
    #!/bin/bash
    # DEB package post-installation script

    set -e

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    # Create service user if it doesn't exist
    if ! id portforward &>/dev/null; then
       useradd -r -s /bin/false -M -d /nonexistent -c "Port Forward Service" portforward
    fi

    # Set capabilities for socat
    if command -v setcap >/dev/null 2>&1; then
       setcap 'cap_net_bind_service=+ep' /usr/bin/socat 2>/dev/null || true
    fi

    # Set permissions
    chown portforward:portforward /var/log/port-forward 2>/dev/null || true
    chown portforward:portforward /run/port-forward 2>/dev/null || true

    exit 0
    EOF

    chmod 755 $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)/DEBIAN/postinst

    # Build package
    dpkg-deb --build $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION)

    # Move to dist directory
    mkdir -p $(DIST_DIR)
    mv $(BUILD_DIR)/$(PACKAGE_NAME)-$(VERSION).deb $(DIST_DIR)/$(PACKAGE_NAME)_$(VERSION)_$(ARCH).deb

    @echo "Package built: $(DIST_DIR)/$(PACKAGE_NAME)_$(VERSION)_$(ARCH).deb"

# Build Arch Linux package
build-arch: $(BUILD_DIR)
    @echo "Building Arch Linux package..."
    mkdir -p $(BUILD_DIR)/arch

    # Copy source files
    cp -r src systemd install.sh uninstall.sh README.md LICENSE PKGBUILD $(BUILD_DIR)/arch/

    # Build package
    cd $(BUILD_DIR)/arch && makepkg -s --noconfirm

    # Move to dist directory
    mkdir -p $(DIST_DIR)
    mv $(BUILD_DIR)/arch/*.pkg.tar.zst $(DIST_DIR)/

    @echo "Package built: $(DIST_DIR)/*.pkg.tar.zst"

# Run tests
test:
    @echo "Running tests..."
    # Unit tests for script functions
    bash -n src/port-forward.sh
    bash -n install.sh
    bash -n uninstall.sh
    @echo "Syntax check passed"

    # Run shellcheck
    shellcheck src/port-forward.sh install.sh uninstall.sh || true

# Lint scripts
lint:
    @echo "Linting scripts..."
    shellcheck src/port-forward.sh install.sh uninstall.sh

# Create source tarball
dist:
    @echo "Creating source tarball..."
    mkdir -p $(DIST_DIR)
    tar -czf $(DIST_DIR)/$(PACKAGE_NAME)-$(VERSION).tar.gz \
        --transform "s,^,$(PACKAGE_NAME)-$(VERSION)/," \
        src systemd install.sh uninstall.sh README.md LICENSE Makefile PKGBUILD
    @echo "Source tarball: $(DIST_DIR)/$(PACKAGE_NAME)-$(VERSION).tar.gz"

# Docker build
docker-build:
    @echo "Building with Docker..."
    docker build -t port-forward-builder .
    docker run --rm -v $(PWD):/build port-forward-builder

# Show help
help:
    @echo "Port Forward Manager Build System"
    @echo ""
    @echo "Available targets:"
    @echo "  install      - Install locally"
    @echo "  uninstall    - Uninstall locally"
    @echo "  build-deb    - Build DEB package"
    @echo "  build-arch   - Build Arch Linux package"
    @echo "  dist         - Create source tarball"
    @echo "  test         - Run tests"
    @echo "  lint         - Lint scripts"
    @echo "  clean        - Clean build files"
    @echo "  docker-build - Build using Docker"
    @echo "  help         - Show this help"
