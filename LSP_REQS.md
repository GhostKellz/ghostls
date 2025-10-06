# LSP Requirements for Ghostls ↔ Grim Integration

This document outlines the requirements for **Ghostls** (LSP server for Ghostlang) to provide LSP services to **Grim** editor, similar to how Ghostls provides a Lua configuration interface for Neovim.

---

## 🎯 Overview

**Goal**: Enable Grim to use Ghostls as its primary LSP server for `.gza` and `.ghost` files, with configuration written in **Ghostlang** (not Lua).

**Architecture**:
```
┌─────────────────┐         LSP Protocol          ┌──────────────────┐
│  Grim Editor    │◄─────────────────────────────►│   Ghostls Server │
│  (Zig + TUI)    │  stdio/JSON-RPC messages      │  (Rust/Zig)      │
├─────────────────┤                                ├──────────────────┤
│ • LSP Client    │                                │ • Grove Parser   │
│ • Buffer Mgmt   │                                │ • Diagnostics    │
│ • UI Rendering  │                                │ • Completions    │
│ • Plugin Host   │                                │ • Hover/Goto     │
└─────────────────┘                                └──────────────────┘
         │                                                  │
         │ Ghostlang Configuration                         │
         ▼                                                  ▼
  ~/.config/grim/init.gza                       Ghostlang Runtime
```

---

## 📋 Core LSP Features Required

### 1. Server Lifecycle

Ghostls must support standard LSP initialization and shutdown:

#### Methods to Implement:
- ✅ `initialize` - Server capabilities negotiation
- ✅ `initialized` - Post-initialization notification
- ✅ `shutdown` - Clean server shutdown
- ✅ `exit` - Terminate server process

#### Server Capabilities to Advertise:
```json
{
  "capabilities": {
    "textDocumentSync": {
      "openClose": true,
      "change": 2,  // Incremental
      "save": { "includeText": true }
    },
    "hoverProvider": true,
    "completionProvider": {
      "triggerCharacters": [".", ":", "@"],
      "resolveProvider": true
    },
    "definitionProvider": true,
    "referencesProvider": true,
    "documentSymbolProvider": true,
    "workspaceSymbolProvider": true,
    "documentFormattingProvider": true,
    "documentRangeFormattingProvider": true,
    "diagnosticProvider": {
      "interFileDependencies": true,
      "workspaceDiagnostics": true
    },
    "codeActionProvider": true,
    "renameProvider": { "prepareProvider": true },
    "foldingRangeProvider": true,
    "semanticTokensProvider": {
      "legend": {
        "tokenTypes": ["keyword", "string", "number", "comment", "function", "variable", "type", "operator"],
        "tokenModifiers": ["declaration", "readonly", "deprecated"]
      },
      "full": true,
      "range": true
    }
  }
}
```

---

### 2. Text Document Synchronization

#### Methods Required:
- ✅ `textDocument/didOpen` - Track opened buffers
- ✅ `textDocument/didChange` - Incremental edits
- ✅ `textDocument/didSave` - Save notifications
- ✅ `textDocument/didClose` - Close notifications

#### Grim Implementation Requirements:
```zig
// lsp/client.zig extensions needed
pub fn sendDidOpen(self: *Client, uri: []const u8, language_id: []const u8, text: []const u8) Error!void {
    const notification = .{
        .jsonrpc = "2.0",
        .method = "textDocument/didOpen",
        .params = .{
            .textDocument = .{
                .uri = uri,
                .languageId = language_id,
                .version = 1,
                .text = text,
            },
        },
    };
    const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
    defer self.allocator.free(body);
    try self.writeMessage(body);
}

pub fn sendDidChange(self: *Client, uri: []const u8, version: u32, changes: []const TextEdit) Error!void {
    // Send incremental edits to server
}

pub fn sendDidSave(self: *Client, uri: []const u8, text: ?[]const u8) Error!void {
    // Notify server of save
}
```

---

### 3. Diagnostics (Real-time Error Checking)

#### Ghostls Requirements:
- Parse `.gza`/`.ghost` files using Grove tree-sitter grammar
- Emit `textDocument/publishDiagnostics` notifications for:
  - Syntax errors
  - Type mismatches (if type system exists)
  - Undefined variables/functions
  - Deprecated API usage

#### Diagnostic Format:
```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///path/to/config.gza",
    "diagnostics": [
      {
        "range": {
          "start": { "line": 10, "character": 5 },
          "end": { "line": 10, "character": 20 }
        },
        "severity": 1,  // Error
        "source": "ghostls",
        "message": "Undefined function 'register_keympa' (did you mean 'register_keymap'?)"
      }
    ]
  }
}
```

#### Grim UI Integration:
- Display inline diagnostics with squiggly underlines
- Show diagnostic count in status line: `[E:2 W:5]`
- `:GrimDiagnostics` command to show quickfix list

---

### 4. Code Completion

#### Request: `textDocument/completion`
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "textDocument/completion",
  "params": {
    "textDocument": { "uri": "file:///init.gza" },
    "position": { "line": 15, "character": 10 },
    "context": {
      "triggerKind": 2,
      "triggerCharacter": "."
    }
  }
}
```

#### Response Format:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "items": [
      {
        "label": "register_keymap",
        "kind": 3,  // Function
        "detail": "fn(mode: str, keys: str, command: str, opts?: table) -> bool",
        "documentation": "Register a keyboard mapping in the specified mode",
        "insertText": "register_keymap(${1:mode}, ${2:keys}, ${3:command})",
        "insertTextFormat": 2  // Snippet
      },
      {
        "label": "register_command",
        "kind": 3,
        "detail": "fn(name: str, handler: function) -> bool",
        "documentation": "Register a custom editor command"
      }
    ]
  }
}
```

#### Completion Sources:
1. **Grim API functions** (from host bindings)
   - `get_current_buffer()`, `set_cursor()`, `buffer_insert()`, etc.
2. **User-defined functions** (from current file + imports)
3. **Ghostlang stdlib** (`array_push`, `str_split`, `file_read`, etc.)
4. **Keywords** (`function`, `local`, `if`, `for`, `return`, etc.)

#### Grim Client Implementation:
```zig
pub fn requestCompletion(
    self: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
) Error!u32 {
    const id = self.next_id;
    self.next_id += 1;

    const request = .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/completion",
        .params = .{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        },
    };

    const body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(body);
    try self.writeMessage(body);

    return id;
}
```

---

### 5. Hover Documentation

#### Request: `textDocument/hover`
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "textDocument/hover",
  "params": {
    "textDocument": { "uri": "file:///init.gza" },
    "position": { "line": 20, "character": 15 }
  }
}
```

#### Response Format:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "contents": {
      "kind": "markdown",
      "value": "```ghostlang\nfn register_keymap(mode: str, keys: str, command: str, opts?: table) -> bool\n```\n\n**Register a keyboard mapping**\n\n**Parameters:**\n- `mode`: Editor mode (`\"n\"`, `\"i\"`, `\"v\"`, `\"c\"`)\n- `keys`: Key sequence (e.g., `\"<leader>w\"`)\n- `command`: Command to execute\n- `opts`: Optional configuration table\n\n**Returns:** `true` if successful\n\n**Example:**\n```ghostlang\nregister_keymap(\"n\", \"<leader>w\", \":write<CR>\", { desc = \"Save file\" })\n```"
    },
    "range": {
      "start": { "line": 20, "character": 10 },
      "end": { "line": 20, "character": 25 }
    }
  }
}
```

---

### 6. Go to Definition

#### Request: `textDocument/definition`
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "textDocument/definition",
  "params": {
    "textDocument": { "uri": "file:///init.gza" },
    "position": { "line": 25, "character": 5 }
  }
}
```

#### Response:
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "uri": "file:///plugins/utils.gza",
    "range": {
      "start": { "line": 10, "character": 0 },
      "end": { "line": 10, "character": 15 }
    }
  }
}
```

---

### 7. Document Symbols (Outline)

#### Request: `textDocument/documentSymbol`
Provides file outline for navigation.

#### Response:
```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": [
    {
      "name": "config",
      "kind": 13,  // Variable
      "range": { "start": { "line": 5, "character": 0 }, "end": { "line": 15, "character": 1 } },
      "selectionRange": { "start": { "line": 5, "character": 6 }, "end": { "line": 5, "character": 12 } }
    },
    {
      "name": "format_current_buffer",
      "kind": 12,  // Function
      "range": { "start": { "line": 20, "character": 0 }, "end": { "line": 40, "character": 3 } },
      "selectionRange": { "start": { "line": 20, "character": 9 }, "end": { "line": 20, "character": 30 } }
    }
  ]
}
```

---

### 8. Workspace Symbols (Project-wide Search)

#### Request: `workspace/symbol`
```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "workspace/symbol",
  "params": { "query": "keymap" }
}
```

Search across all `.gza` files in workspace for symbols matching query.

---

### 9. Formatting

#### Request: `textDocument/formatting`
```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "textDocument/formatting",
  "params": {
    "textDocument": { "uri": "file:///init.gza" },
    "options": {
      "tabSize": 4,
      "insertSpaces": true
    }
  }
}
```

#### Response:
```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": [
    {
      "range": {
        "start": { "line": 0, "character": 0 },
        "end": { "line": 999, "character": 999 }
      },
      "newText": "-- Formatted code here\nfunction foo()\n    return 42\nend\n"
    }
  ]
}
```

---

## 🔧 Grim Configuration in Ghostlang

Instead of Lua (like Neovim), Grim config is **pure Ghostlang**.

### Example: `~/.config/grim/init.gza`

```ghostlang
-- Grim Editor Configuration (Ghostlang syntax)

-- Editor settings
set_option("line_numbers", true)
set_option("relative_line_numbers", false)
set_option("tab_width", 4)
set_option("theme", "gruvbox-dark")

-- LSP Configuration
local lsp = require("grim.lsp")

-- Configure Ghostls for .gza files
lsp.setup("ghostls", {
    cmd = { "ghostls", "--stdio" },
    filetypes = { "ghostlang", "gza" },
    root_patterns = { ".git", "grim.toml" },
    settings = {
        ghostls = {
            diagnostics = { enable = true },
            completion = { enable = true, snippets = true },
            hover = { enable = true },
        }
    }
})

-- Configure ZLS for .zig files
lsp.setup("zls", {
    cmd = { "zls" },
    filetypes = { "zig" },
    root_patterns = { "build.zig", ".git" }
})

-- Configure rust-analyzer for .rs files
lsp.setup("rust_analyzer", {
    cmd = { "rust-analyzer" },
    filetypes = { "rust" },
    root_patterns = { "Cargo.toml", ".git" }
})

-- Keybindings for LSP
local keymap = register_keymap
keymap("n", "gd", ":LspGotoDefinition<CR>", { desc = "Go to definition" })
keymap("n", "K", ":LspHover<CR>", { desc = "Show hover docs" })
keymap("n", "<leader>ca", ":LspCodeAction<CR>", { desc = "Code actions" })
keymap("n", "<leader>rn", ":LspRename<CR>", { desc = "Rename symbol" })
keymap("n", "[d", ":LspPrevDiagnostic<CR>", { desc = "Previous diagnostic" })
keymap("n", "]d", ":LspNextDiagnostic<CR>", { desc = "Next diagnostic" })

-- Auto-format on save
register_event_handler("buffer_save", function(buffer_id)
    if lsp.has_formatter(buffer_id) then
        lsp.format(buffer_id)
    end
end)
```

---

## 🏗️ Grim LSP Client Implementation Checklist

### Required Files

#### 1. `lsp/client.zig` - Base LSP Client (✅ Partially Complete)
Current state: Basic initialize + diagnostics
- [x] `initialize` request
- [x] `poll()` for incoming messages
- [x] Diagnostics notifications
- [ ] **Add**: `textDocument/completion`
- [ ] **Add**: `textDocument/hover`
- [ ] **Add**: `textDocument/definition`
- [ ] **Add**: Response routing (map request IDs to callbacks)

#### 2. `lsp/server_manager.zig` - Server Lifecycle (❌ Missing)
```zig
pub const ServerManager = struct {
    allocator: std.mem.Allocator,
    servers: std.StringHashMap(*ServerProcess),

    pub fn spawn(self: *ServerManager, config: ServerConfig) !*ServerProcess;
    pub fn shutdown(self: *ServerManager, server_name: []const u8) !void;
    pub fn restart(self: *ServerManager, server_name: []const u8) !void;
};
```

#### 3. `lsp/protocol.zig` - LSP Types (❌ Missing)
```zig
pub const Position = struct { line: u32, character: u32 };
pub const Range = struct { start: Position, end: Position };
pub const TextDocumentIdentifier = struct { uri: []const u8 };
pub const CompletionItem = struct { label: []const u8, kind: u8, detail: ?[]const u8, ... };
pub const Diagnostic = struct { range: Range, severity: u8, message: []const u8, ... };
```

#### 4. `lsp/ghostlang_config.gza` - Ghostlang LSP Config (❌ Missing)
User-facing configuration interface.

---

## 🧪 Testing Requirements

### 1. Ghostls Server Tests
```bash
# Test Ghostls can start and respond to initialize
ghostls --stdio < tests/fixtures/initialize.json

# Test diagnostics emission
cat tests/fixtures/bad_syntax.gza | ghostls --check

# Test completion at specific position
ghostls --complete tests/fixtures/config.gza:15:10
```

### 2. Grim Integration Tests
```bash
# Headless LSP test
zig build test --filter "lsp completion"
zig build test --filter "lsp hover"
zig build test --filter "lsp goto definition"

# E2E test with mock Ghostls server
./tests/e2e/lsp_smoke_test.sh
```

### 3. CI Validation
```yaml
# .github/workflows/grim-ghostls.yml
name: Grim + Ghostls Integration
on: [push, pull_request]
jobs:
  lsp-integration:
    runs-on: [self-hosted, zig, ghostlang]
    steps:
      - uses: actions/checkout@v4
      - name: Build Ghostls
        run: cargo build --release --manifest-path ../ghostls/Cargo.toml
      - name: Run Grim LSP tests
        run: zig build test --filter "lsp"
      - name: Smoke test with real Ghostls
        run: ./tests/smoke_lsp.sh
```

---

## 📦 Deliverables for Ghostls

### Milestone 1: Core LSP Server (MVP)
- [ ] Initialize/shutdown lifecycle
- [ ] `textDocument/didOpen|didChange|didSave|didClose`
- [ ] `textDocument/publishDiagnostics` (syntax errors only)

### Milestone 2: Code Intelligence
- [ ] `textDocument/completion` (keywords + stdlib)
- [ ] `textDocument/hover` (function signatures)
- [ ] `textDocument/definition` (local definitions)

### Milestone 3: Advanced Features
- [ ] `textDocument/documentSymbol` (outline view)
- [ ] `textDocument/formatting` (auto-format)
- [ ] `textDocument/codeAction` (quick fixes)
- [ ] `workspace/symbol` (project-wide search)

### Milestone 4: Grim API Integration
- [ ] Parse Grim API definitions from Zig source
- [ ] Provide completions for `get_current_buffer()`, `register_keymap()`, etc.
- [ ] Generate hover docs from Zig doc comments
- [ ] Validate Grim API usage in `.gza` files

---

## 🚀 Next Steps

1. **For Ghostls team**: Implement LSP server following this spec
2. **For Grim team**: Complete `lsp/client.zig` with missing request methods
3. **For Grim team**: Create `lsp/server_manager.zig` for spawning Ghostls
4. **Integration**: Test end-to-end with real `.gza` config files
5. **Documentation**: Write "Getting Started with Grim + Ghostls" guide

---

## 📚 References

- [LSP Specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [Neovim LSP Client (Lua)](https://github.com/neovim/neovim/tree/master/runtime/lua/vim/lsp) - Reference implementation
- [Ghostlang Repository](https://github.com/ghostkellz/ghostlang)
- [Grove Tree-sitter Integration](https://github.com/ghostkellz/grove)
- [Grim Editor](https://github.com/ghostkellz/grim)

---

**Status**: Draft v1.0
**Authors**: Grim + Ghostls Teams
**Last Updated**: 2025-10-05
