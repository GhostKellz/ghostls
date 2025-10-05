#!/usr/bin/env bash
# Simple smoke test for ghostls
set -e

echo "Building ghostls..."
zig build

echo "Testing ghostls LSP server..."

# Create test file
cat > /tmp/test.ghost << 'EOF'
fn test() {
    let x = 42
    // Missing semicolon above
}
EOF

# Test messages
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"processId":null}}'
INITIALIZED='{"jsonrpc":"2.0","method":"initialized","params":{}}'
DIDOPEN="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/test.ghost\",\"languageId\":\"ghostlang\",\"version\":1,\"text\":\"$(cat /tmp/test.ghost | sed 's/"/\\"/g' | tr '\n' ' ')\"}}}"
SHUTDOWN='{"jsonrpc":"2.0","id":2,"method":"shutdown"}'
EXIT='{"jsonrpc":"2.0","method":"exit"}'

# Send messages and capture output
{
    printf "Content-Length: ${#INIT}\r\n\r\n${INIT}"
    sleep 0.2
    printf "Content-Length: ${#INITIALIZED}\r\n\r\n${INITIALIZED}"
    sleep 0.2
    printf "Content-Length: ${#DIDOPEN}\r\n\r\n${DIDOPEN}"
    sleep 0.5
    printf "Content-Length: ${#SHUTDOWN}\r\n\r\n${SHUTDOWN}"
    sleep 0.1
    printf "Content-Length: ${#EXIT}\r\n\r\n${EXIT}"
} | ./zig-out/bin/ghostls 2>&1 | tee /tmp/ghostls_output.log

# Check results
echo ""
echo "=== Test Results ==="
if grep -q "Found.*diagnostics" /tmp/ghostls_output.log && grep -q "Published diagnostics" /tmp/ghostls_output.log; then
    echo "✓ PASS: Diagnostics published successfully"
    exit 0
else
    echo "✗ FAIL: No diagnostics found"
    exit 1
fi
