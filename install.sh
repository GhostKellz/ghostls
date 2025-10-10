#!/usr/bin/env bash
# ghostls Installation Script
# Installs ghostls language server to system LSP directory
#
# Usage:
#   ./install.sh                           # Local install
#   curl -fsSL ... | bash                  # Remote install
#   INSTALL_DIR=/custom/path ./install.sh  # Custom directory

set -euo pipefail

VERSION="0.3.0"
REPO="https://github.com/ghostkellz/ghostls.git"
BINARY_NAME="ghostls"

# Determine install directory (LSP standard locations)
if [ -d "/usr/lib/lsp" ]; then
    DEFAULT_INSTALL_DIR="/usr/lib/lsp"
elif [ -d "/usr/local/lib/lsp" ]; then
    DEFAULT_INSTALL_DIR="/usr/local/lib/lsp"
else
    DEFAULT_INSTALL_DIR="/usr/local/bin"
fi

INSTALL_DIR="${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"

echo "=== ghostls ${VERSION} Installation ==="
echo

# Check if we need to clone (remote install)
if [ ! -f "build.zig" ]; then
    echo "Cloning ghostls repository..."
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT
    git clone "${REPO}" "${TEMP_DIR}" 2>/dev/null || {
        echo "❌ Failed to clone repository"
        exit 1
    }
    cd "${TEMP_DIR}"
    echo "✓ Repository cloned"
    echo
fi

# Check if zig is available
if ! command -v zig &> /dev/null; then
    echo "❌ Error: zig not found"
    echo "   Install zig from https://ziglang.org/"
    echo "   Arch: sudo pacman -S zig"
    exit 1
fi

echo "✓ Found zig: $(zig version)"
echo

# Build ghostls
echo "Building ghostls..."
if ! zig build -Doptimize=ReleaseSafe; then
    echo "❌ Build failed"
    exit 1
fi

if [ ! -f "zig-out/bin/${BINARY_NAME}" ]; then
    echo "❌ Binary not found: zig-out/bin/${BINARY_NAME}"
    exit 1
fi

echo "✓ Build successful"
echo

# Create install directory if needed
if [ ! -d "${INSTALL_DIR}" ]; then
    echo "Creating ${INSTALL_DIR}..."
    sudo mkdir -p "${INSTALL_DIR}"
fi

# Install
echo "Installing to ${INSTALL_DIR}/${BINARY_NAME}"

if [ -w "${INSTALL_DIR}" ]; then
    cp "zig-out/bin/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
else
    echo "   (requires sudo)"
    sudo cp "zig-out/bin/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
    sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
fi

# Add to PATH if not in standard location
if ! echo "${PATH}" | grep -q "${INSTALL_DIR}"; then
    echo
    echo "⚠ Note: ${INSTALL_DIR} not in PATH"
    echo "   Add to your shell profile:"
    echo "   export PATH=\"${INSTALL_DIR}:\$PATH\""
fi

# Verify installation
echo
if command -v "${BINARY_NAME}" &> /dev/null; then
    echo "✅ Installation successful!"
    echo
    echo "   Version: $(${BINARY_NAME} --version 2>&1)"
    echo "   Location: $(which ${BINARY_NAME})"
elif [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
    echo "✅ Installation successful!"
    echo
    echo "   Version: $(${INSTALL_DIR}/${BINARY_NAME} --version 2>&1)"
    echo "   Location: ${INSTALL_DIR}/${BINARY_NAME}"
else
    echo "❌ Installation failed"
    exit 1
fi

echo
echo "=== Next Steps ==="
echo
echo "1. Grim Editor:"
echo "   ghostls will auto-spawn when you open .gza files"
echo
echo "2. Neovim:"
echo "   Add to your nvim config:"
echo "   require('lspconfig').ghostls.setup{}"
echo
echo "3. Test manually:"
echo "   ${BINARY_NAME} --help"
echo
echo "Documentation: https://github.com/ghostkellz/ghostls"
echo
