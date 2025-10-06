# Changelog

All notable changes to ghostls will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-05

### Added - v0.1.0 Release

#### CLI & Installation
- **`--version` flag** - Display version information
- **`--help` flag** - Show comprehensive help message
- **Installation script** (`install.sh`) - Easy deployment to `/usr/local/bin`
- **Professional CLI interface** with usage examples and documentation links

#### Logging & LSP Compliance
- ✅ **stdout CLEAN** - Only JSON-RPC messages (LSP spec compliant)
- ✅ **stderr for logging** - All debug output goes to stderr (`[ghostls]` prefix)
- **Verified Grim compatibility** - Tested with Grim's ServerManager

#### Core LSP Protocol
- **Initialize/Shutdown** - Full LSP handshake implementation
- **Document Sync** - Open, change, and close document tracking
- **Server Capabilities** - Proper capability advertisement to clients

#### Language Features
- **Diagnostics** - Real-time syntax error detection via Grove/Tree-sitter
- **Hover** - Show type and documentation on hover
- **Go to Definition** - Navigate to symbol definitions within files
- **Document Symbols** - Outline view for functions, variables, and structures
- **Completions** - Smart autocomplete with:
  - 15 Ghostlang keywords (`var`, `function`, `if`, `while`, `for`, etc.)
  - 44 built-in functions (editor APIs, string/array/object utilities)
  - Trigger characters: `.` and `:`

#### Grim Editor Integration
- **textDocument/didSave** support for file save notifications
- Server capabilities now advertise `save: { includeText: true }`
- Comprehensive Grim integration documentation (`docs/GRIM_INTEGRATION.md`)
- Example Grim configuration in `.gza` format (`integrations/grim/init.gza`)
- Detailed Grim LSP client implementation guide with code examples
- Integration test suite (`tests/grim_integration_test.sh`)
- Full compatibility with Grim's existing LSP client (`lsp/client.zig`)
- Support for Ghostlang-based configuration (not Lua like Neovim)
- `.gza` file type support for Grim plugin development

#### Editor Integration
- **Neovim** - Full nvim-lspconfig setup documentation
- **Grim** - Ready for integration (LSP server side complete)
- **File Types** - Support for `.ghost` and `.gza` file extensions

#### Infrastructure
- **Grove Integration** - Tree-sitter parsing via Grove library
- **Ghostlang 0.1.0** - Updated to latest Ghostlang runtime
- **Transport Layer** - Robust LSP JSON-RPC over stdio
- **Error Handling** - Graceful error recovery and reporting
- **Logging** - Debug logging to stderr for troubleshooting

#### Documentation
- Complete README with architecture diagrams
- Editor-specific setup guides (Neovim, Grim)
- Integration examples and troubleshooting
- TODO roadmap for future releases

### Technical Details

- **Language**: Zig 0.16.0-dev (latest)
- **Parser**: Grove (Tree-sitter wrapper)
- **Runtime**: Ghostlang 0.1.0
- **Protocol**: LSP 3.17 compliant
- **Dependencies**: grove, ghostlang, zlog

### Fixed
- **LSP stdout pollution** - Verified clean JSON-RPC only output (Grim compatibility fix)
- **InitializeResult serialization** - Now properly returns server capabilities in JSON
- **Zig 0.16 compatibility** - Updated to new `std.json.Stringify`, `std.Io.Writer`, and `ArrayList` APIs
- **Memory management** - Proper allocation/deallocation in completions and diagnostics
- **CLI argument parsing** - Zig 0.16 `std.fs.File.write()` API updates

### Known Limitations (To be addressed in future releases)
- Completions are currently static (not context-aware)
- No workspace symbol search yet
- No semantic tokens support yet
- No references provider yet
- Single-file navigation only (no cross-file definitions)
- No incremental document sync (full sync only)

## [0.0.1-alpha] - 2025-10-04

### Added
- Initial project scaffolding
- Basic LSP transport layer
- Document manager stub
- Grove tree-sitter integration
- Project architecture and build system

---

## Roadmap

### v0.2.0 - Enhanced Features
- Context-aware completions (scope-based suggestions)
- Workspace symbol search
- Semantic tokens for advanced syntax highlighting
- Cross-file go-to-definition
- Find references support

### v0.3.0 - Advanced Features
- Code actions (quick fixes, refactoring)
- Rename symbol across workspace
- Incremental document sync
- Signature help for functions
- Inlay hints for types

### v1.0.0 - Production Ready
- Full LSP 3.17 compliance
- Performance optimizations
- Comprehensive test coverage
- VS Code extension
- Plugin system for custom language features

---

[Unreleased]: https://github.com/ghostkellz/ghostls/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ghostkellz/ghostls/releases/tag/v0.1.0

Added install and uninstall script for local testing.
