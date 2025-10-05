#!/usr/bin/env python3
"""Smoke test for ghostls MVP"""

import json
import subprocess
import sys
import time

def send_message(proc, message):
    """Send LSP message to server"""
    content = json.dumps(message)
    header = f"Content-Length: {len(content)}\r\n\r\n"
    proc.stdin.write(header.encode() + content.encode())
    proc.stdin.flush()
    print(f"→ Sent: {message['method'] if 'method' in message else 'response'}")

def main():
    print("Building ghostls...")
    subprocess.run(["zig", "build"], check=True)

    print("\nStarting ghostls smoke test...")

    # Start server
    proc = subprocess.Popen(
        ["./zig-out/bin/ghostls"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False
    )

    try:
        # 1. Initialize
        send_message(proc, {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": None,
                "capabilities": {}
            }
        })

        # 2. Initialized notification
        time.sleep(0.1)
        send_message(proc, {
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": {}
        })

        # 3. Open document with syntax error
        time.sleep(0.1)
        test_code = """fn test() {
    let x = 42
    // Missing semicolon should trigger error
}"""

        send_message(proc, {
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": "file:///tmp/test.ghost",
                    "languageId": "ghostlang",
                    "version": 1,
                    "text": test_code
                }
            }
        })

        # 4. Wait for diagnostics
        time.sleep(0.5)

        # 5. Shutdown
        send_message(proc, {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "shutdown"
        })

        # 6. Exit
        time.sleep(0.1)
        send_message(proc, {
            "jsonrpc": "2.0",
            "method": "exit"
        })

        # Check stderr for diagnostic output
        proc.wait(timeout=2)
        stderr_output = proc.stderr.read().decode()

        print("\n--- Server Log ---")
        print(stderr_output)
        print("--- End Log ---\n")

        # Verify diagnostics were published
        if "publishDiagnostics" in stderr_output or "diagnostics" in stderr_output.lower():
            print("✓ Smoke test PASSED - diagnostics published")
            return 0
        else:
            print("✗ Smoke test FAILED - no diagnostics found")
            return 1

    except Exception as e:
        print(f"✗ Smoke test FAILED - {e}")
        proc.kill()
        return 1

if __name__ == "__main__":
    sys.exit(main())
