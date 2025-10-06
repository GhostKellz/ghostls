# Grim ↔ Ghostls Integration Guide

Complete guide for integrating **ghostls** (Ghostlang LSP server) with **Grim** editor.

---

## Quick Start

### 1. Build ghostls

```bash
cd ghostls
zig build -Drelease-safe
sudo cp zig-out/bin/ghostls /usr/local/bin/
```

### 2. Configure Grim

Copy the example configuration:

```bash
mkdir -p ~/.config/grim
cp integrations/grim/init.gza ~/.config/grim/init.gza
```

### 3. Launch Grim

```bash
grim myfile.gza
```

Ghostls will auto-spawn when you open a `.gza` file!

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Grim Editor                          │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │   UI/TUI     │   │  LSP Client  │   │  Plugin Host   │  │
│  │  Rendering   │◄──┤  (client.zig)│◄──┤  (init.gza)    │  │
│  └──────────────┘   └──────┬───────┘   └────────────────┘  │
└──────────────────────────────┼──────────────────────────────┘
                               │ JSON-RPC over stdio
                          ┌────▼────────────────────┐
                          │   Ghostls LSP Server    │
                          ├─────────────────────────┤
                          │ • Grove (Tree-sitter)   │
                          │ • Diagnostics Engine    │
                          │ • Completion Provider   │
                          │ • Hover Provider        │
                          │ • Definition Provider   │
                          │ • Symbol Provider       │
                          └─────────────────────────┘
```

---

## Ghostls Capabilities

### ✅ Currently Supported (RC1)

| Feature | Method | Description |
|---------|--------|-------------|
| **Lifecycle** | `initialize`, `shutdown` | Server startup/shutdown |
| **Document Sync** | `didOpen`, `didChange`, `didSave`, `didClose` | Track file changes |
| **Diagnostics** | `publishDiagnostics` | Real-time syntax errors |
| **Hover** | `textDocument/hover` | Show docs on hover |
| **Completions** | `textDocument/completion` | 59 keywords + builtins |
| **Go to Definition** | `textDocument/definition` | Navigate to symbols |
| **Document Symbols** | `textDocument/documentSymbol` | Outline view |

### 🚧 Coming Soon (Post-RC1)

- Workspace symbols (`workspace/symbol`)
- Formatting (`textDocument/formatting`)
- Code actions (`textDocument/codeAction`)
- Semantic tokens (advanced highlighting)
- References (`textDocument/references`)
- Rename (`textDocument/rename`)

---

## Grim LSP Client Implementation

### Current State

Grim's `lsp/client.zig` already has:
- ✅ JSON-RPC transport (Content-Length framing)
- ✅ `sendInitialize()` handshake
- ✅ `poll()` for reading messages
- ✅ Diagnostics handling

### Required Additions

See [integrations/grim/README.md](../integrations/grim/README.md#what-grim-needs-to-add-%E2%9A%A0%EF%B8%8F) for complete code examples.

**Summary of methods to add:**

1. **`sendDidSave(uri, text?)`** - Notify server of file save
2. **`requestCompletion(uri, line, char)`** - Request completions
3. **`requestHover(uri, line, char)`** - Request hover docs
4. **`requestDefinition(uri, line, char)`** - Request definition location

---

## Configuration Example

**File: `~/.config/grim/init.gza`**

```ghostlang
-- LSP setup
local lsp = require("grim.lsp")

lsp.setup("ghostls", {
    cmd = { "ghostls" },
    filetypes = { "ghostlang", "gza" },
    root_patterns = { ".git", "build.zig" },

    settings = {
        ghostls = {
            diagnostics = { enable = true },
            completion = { enable = true, snippets = true },
        }
    },

    on_attach = function(client_id, buffer_id)
        -- Keybindings
        register_keymap("n", "gd", ":LspGotoDefinition<CR>")
        register_keymap("n", "K", ":LspHover<CR>")
        register_keymap("n", "<leader>ca", ":LspCodeAction<CR>")
    end,
})
```

See [integrations/grim/init.gza](../integrations/grim/init.gza) for full example.

---

## Testing

### Manual Test

```bash
# Terminal 1: Start ghostls manually
ghostls

# Terminal 2: Send test request
echo 'Content-Length: 103\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{},"processId":null}}' | ghostls
```

### Expected Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "capabilities": {
      "positionEncoding": "utf-16",
      "textDocumentSync": {
        "openClose": true,
        "change": 1,
        "save": {"includeText": true}
      },
      "hoverProvider": true,
      "completionProvider": {"triggerCharacters": [".", ":"]},
      "definitionProvider": true,
      "documentSymbolProvider": true
    },
    "serverInfo": {"name": "ghostls", "version": "0.0.1-alpha"}
  }
}
```

### Integration Test

```bash
cd ghostls
./tests/grim_integration_test.sh
```

---

## Troubleshooting

### Ghostls Not Starting

**Check if ghostls is in PATH:**
```bash
which ghostls
ghostls --version  # (once implemented)
```

**Manually spawn from Grim:**
```zig
const process = try std.process.Child.init(&.{"ghostls"}, allocator);
process.stdin_behavior = .Pipe;
process.stdout_behavior = .Pipe;
try process.spawn();
```

### No Completions Appearing

**Check LSP is initialized:**
```ghostlang
-- In init.gza
register_command("LspInfo", function()
    local status = lsp.get_status("ghostls")
    print("Ghostls status: " .. tostring(status.initialized))
end)
```

**Enable debug logging:**
```bash
GHOSTLS_LOG=debug grim myfile.gza 2> /tmp/ghostls.log
```

### Diagnostics Not Showing

**Verify didOpen was sent:**
Check Grim calls `client.sendDidOpen(uri, "ghostlang", text)` after opening `.gza` files.

**Check Grove grammar:**
```bash
# Grove should be bundled with ghostls
zig build && ./zig-out/bin/ghostls # Should not error about missing tree-sitter
```

---

## Performance Tips

### 1. Incremental Sync (Future)

Currently ghostls uses **full sync** (sends entire document on each change). Future versions will support **incremental sync** for better performance with large files.

### 2. Debounce Diagnostics

In Grim, debounce diagnostic requests:

```ghostlang
local diagnostic_timer = nil

register_event_handler("buffer_changed", function(buffer_id)
    if diagnostic_timer then
        cancel_timer(diagnostic_timer)
    end

    diagnostic_timer = set_timer(500, function() -- 500ms debounce
        lsp.request_diagnostics(buffer_id)
    end)
end)
```

### 3. Limit Completion Scope

For large files, limit completion context:

```ghostlang
set_option("completion", {
    max_items = 50,
    timeout_ms = 100,
})
```

---

## Grim API Integration

### Future: Grim-Specific Completions

Ghostls will parse Grim's Zig source to provide completions for editor APIs:

```gza
-- User types: get_cur
-- Ghostls suggests:
get_current_buffer()    -- From grim/src/buffer.zig
get_cursor_position()   -- From grim/src/cursor.zig
```

Implementation planned in `src/lsp/grim_adapter.zig`.

---

## Resources

- **Grim Repository**: https://github.com/ghostkellz/grim
- **Ghostls Repository**: https://github.com/ghostkellz/ghostls
- **LSP Specification**: https://microsoft.github.io/language-server-protocol/
- **Grove (Tree-sitter)**: https://github.com/ghostkellz/grove
- **Ghostlang**: https://github.com/ghostkellz/ghostlang

---

## Contributing

### For Ghostls Development

1. Add new LSP features in `src/lsp/`
2. Update capabilities in `server.zig:handleInitialize()`
3. Test with `./scripts/simple_test.sh`
4. Update this guide

### For Grim Development

1. Implement missing LSP client methods (see README)
2. Add request/response routing
3. Test with real ghostls server
4. Submit PR to Grim repo

---

**Status**: Ghostls RC1 ready for Grim integration
**Last Updated**: 2025-10-05
