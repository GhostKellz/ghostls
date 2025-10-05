#!/usr/bin/env bash
# Smoke test for ghostls MVP
set -e

echo "Starting ghostls smoke test..."

# Build first
echo "Building ghostls..."
zig build

# Test file with syntax error
TEST_FILE=$(mktemp --suffix=.ghost)
cat > "$TEST_FILE" << 'EOF'
fn test() {
    let x = 42
    // Missing semicolon above should trigger error
}
EOF

# Start server and test
echo "Testing LSP server..."
{
    # Initialize
    echo 'Content-Length: 103\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"processId":null}}'

    # Initialized notification
    echo 'Content-Length: 52\r\n\r\n{"jsonrpc":"2.0","method":"initialized","params":{}}'

    # Open document
    FILE_URI="file://$TEST_FILE"
    FILE_CONTENT=$(cat "$TEST_FILE" | jq -Rs .)
    cat << EOF
Content-Length: $((${#FILE_URI} + ${#FILE_CONTENT} + 150))\r\n\r\n{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$FILE_URI","languageId":"ghostlang","version":1,"text":$FILE_CONTENT}}}
EOF

    # Give server time to process
    sleep 0.5

    # Shutdown
    echo 'Content-Length: 45\r\n\r\n{"jsonrpc":"2.0","id":2,"method":"shutdown"}'

    # Exit
    echo 'Content-Length: 35\r\n\r\n{"jsonrpc":"2.0","method":"exit"}'
} | ./zig-out/bin/ghostls 2>&1 | tee /tmp/ghostls_test.log

# Cleanup
rm "$TEST_FILE"

# Check results
if grep -q "publishDiagnostics" /tmp/ghostls_test.log; then
    echo "✓ Smoke test PASSED - diagnostics published"
    exit 0
else
    echo "✗ Smoke test FAILED - no diagnostics found"
    exit 1
fi
