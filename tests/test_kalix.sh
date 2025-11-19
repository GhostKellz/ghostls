#!/usr/bin/env bash
set -e

echo "Building ghostls..."
zig build

echo "Testing kalix LSP integration..."

# Create test kalix file
cat > /tmp/test.kalix << 'EOF'
contract Treasury {
    state balance: u64;

    fn deposit(amount: u64) payable {
        state.balance = state.balance + amount;
    }

    fn getBalance() view -> u64 {
        return state.balance;
    }
}
EOF

# Test messages
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"processId":null}}'
INITIALIZED='{"jsonrpc":"2.0","method":"initialized","params":{}}'
DIDOPEN="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tmp/test.kalix\",\"languageId\":\"kalix\",\"version\":1,\"text\":\"$(cat /tmp/test.kalix | sed 's/"/\\"/g' | tr '\n' ' ')\"}}}"
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
} | ./zig-out/bin/ghostls 2>&1 | tee /tmp/ghostls_kalix_output.log

# Check results
echo ""
echo "=== Kalix Test Results ==="
if grep -q "Found.*diagnostics" /tmp/ghostls_kalix_output.log; then
    echo "✓ PASS: Kalix diagnostics working"
    if grep -q '"source":"kalix"' /tmp/ghostls_kalix_output.log; then
        echo "✓ PASS: Kalix diagnostics source identified"
    fi
    exit 0
else
    echo "✗ FAIL: No diagnostics found for kalix file"
    exit 1
fi
