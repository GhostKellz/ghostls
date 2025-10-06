#!/usr/bin/env bash
# ghostls Uninstall Script
# Removes ghostls from system

set -euo pipefail

BINARY_NAME="ghostls"

# Common installation directories to check
INSTALL_DIRS=(
    "/usr/bin"
    "/usr/local/bin"
    "/usr/lib/lsp"
    "/usr/local/lib/lsp"
    "${HOME}/.local/bin"
)

echo "=== ghostls Uninstaller ==="
echo

FOUND=0

# Find and remove ghostls
for dir in "${INSTALL_DIRS[@]}"; do
    if [ -f "${dir}/${BINARY_NAME}" ]; then
        echo "Found ${BINARY_NAME} at ${dir}/${BINARY_NAME}"

        if [ -w "${dir}" ]; then
            rm -f "${dir}/${BINARY_NAME}"
            echo "✓ Removed ${dir}/${BINARY_NAME}"
        else
            echo "  (requires sudo)"
            sudo rm -f "${dir}/${BINARY_NAME}"
            echo "✓ Removed ${dir}/${BINARY_NAME}"
        fi

        FOUND=1
    fi
done

# Remove documentation (Arch Linux package)
DOC_DIRS=(
    "/usr/share/doc/${BINARY_NAME}"
    "/usr/share/licenses/${BINARY_NAME}"
)

for dir in "${DOC_DIRS[@]}"; do
    if [ -d "${dir}" ]; then
        echo "Removing documentation: ${dir}"
        if [ -w "$(dirname ${dir})" ]; then
            rm -rf "${dir}"
        else
            sudo rm -rf "${dir}"
        fi
        echo "✓ Removed ${dir}"
        FOUND=1
    fi
done

echo

if [ ${FOUND} -eq 1 ]; then
    echo "✅ ghostls uninstalled successfully"
else
    echo "⚠ ghostls not found in any standard directory"
    echo "   Checked:"
    for dir in "${INSTALL_DIRS[@]}"; do
        echo "   - ${dir}"
    done
fi

echo
