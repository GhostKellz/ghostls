# Ghostlang Language Server (ghostls)

<div align="center">
  <img src="assets/icons/ghostls.png" alt="Ghostlang LSP Icon" width="128" height="128">

**Native Zig Language Server for the Ghostlang Ecosystem**

![zig](https://img.shields.io/badge/Built%20with-Zig-yellow?logo=zig)
![tree-sitter](https://img.shields.io/badge/Parser-TreeSitter-7B68EE?logo=treesitter)
![lsp](https://img.shields.io/badge/Protocol-Language%20Server%20Protocol-blue)
![ghostlang](https://img.shields.io/badge/Language-Ghostlang-7FFFD4)
![grove](https://img.shields.io/badge/Integration-Grove-green)
![grim](https://img.shields.io/badge/Editor-Grim%20IDE-gray)

</div>

---

## 🌐 Overview

**ghostls** is the official **Language Server** for **Ghostlang**, built in **Zig** for speed, predictability, and tight integration with the Ghost ecosystem.

It provides rich editor features — syntax highlighting, document symbols, navigation, completions — powered by **Grove** (Tree-sitter engine) and designed to plug seamlessly into **Grim**, **VSCode**, and **Neovim**.

---

## ✨ Core Features

| Category | Description |
|-----------|-------------|
| 🧠 **Tree-sitter Syntax Intelligence** | Powered by Grove for fast, accurate parsing |
| 🧩 **LSP Protocol** | Fully compliant with the Language Server Protocol (LSP v3.17) |
| 💡 **Editor Support** | Works with Grim, VSCode, and Neovim |
| ⚙️ **Incremental Parsing** | Keeps the AST in sync on every keystroke |
| 🧰 **Extensible via Ghostlang Runtime** | Future runtime integration for semantics and type inference |

---

## 🧱 Architecture

      ┌───────────────────────────────┐
      │           Grim IDE            │
      │    (Frontend / Editor UI)     │
      └───────────────┬───────────────┘
                      │  LSP JSON-RPC
                      ▼
      ┌───────────────────────────────┐
      │        ghostls          │
      │  ├── LSP core (protocol.zig)  │
      │  ├── Syntax (via Grove)       │
      │  ├── Diagnostics engine       │
      │  ├── Document manager         │
      │  └── Feature providers        │
      └───────────────┬───────────────┘
                      │
                      ▼
      ┌───────────────────────────────┐
      │        Ghostlang runtime      │
      │  (future: type system, eval)  │
      └───────────────────────────────┘

---

## 🚀 Quick Start

### Install

#### Curl Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/ghostls/main/install.sh | bash
```

#### Arch Linux (AUR)
```bash
# Using yay or paru
yay -S ghostls

# Or manually with makepkg
git clone https://github.com/ghostkellz/ghostls.git
cd ghostls
makepkg -si
```

#### Manual Install
```bash
# Clone repository
git clone https://github.com/ghostkellz/ghostls.git
cd ghostls

# Run installer
./install.sh

# Verify installation
ghostls --version  # Should show: ghostls 0.1.0
```

### Build from Source
```bash
zig build -Doptimize=ReleaseSafe
```

### Test
```bash
./scripts/simple_test.sh  # Run basic LSP protocol test
./tests/grim_integration_test.sh  # Test Grim integration
```

## 📝 Editor Integration

### Neovim

See [integrations/nvim/README.md](integrations/nvim/README.md) for full setup instructions.

**Quick setup with nvim-lspconfig:**

```lua
require('lspconfig').ghostls.setup{
  cmd = { 'ghostls' },
  filetypes = { 'ghostlang', 'ghost', 'gza' },
}
```

### Grim Editor

**Status**: ✅ ghostls v0.1.0 ready for Grim integration!

ghostls is fully tested and LSP-compliant. Grim can now:
- Auto-spawn ghostls for `.gza` files
- Send LSP requests (hover, definition, completion)
- Receive clean JSON-RPC responses (stdout verified clean)

See [integrations/grim/README.md](integrations/grim/README.md) for complete implementation guide.

**Quick config example** (`.gza` format):

```ghostlang
-- ~/.config/grim/init.gza
local lsp = require("grim.lsp")

lsp.setup("ghostls", {
    cmd = { "ghostls" },
    filetypes = { "ghostlang", "gza" },
})

register_keymap("n", "gd", ":LspGotoDefinition<CR>")
register_keymap("n", "K", ":LspHover<CR>")
```

📖 **Full integration guide**: [docs/GRIM_INTEGRATION.md](docs/GRIM_INTEGRATION.md)

### VS Code

VS Code extension coming in future releases.

## 📦 Using ghostls as a Zig dependency

To integrate ghostls into another Zig project (such as an IDE, editor plugin, or tool):

### 1. Fetch the dependency
```bash
zig fetch --save https://github.com/ghostkellz/ghostls/archive/refs/heads/main.tar.gz
```

This will automatically add ghostls to your `build.zig.zon` with the correct hash.

### 2. Import in `build.zig`
```zig
const ghostls = b.dependency("ghostls", .{
    .target = target,
    .optimize = optimize,
});

// Link the library or executable as needed
exe.root_module.addImport("ghostls", ghostls.module("ghostls"));
```
