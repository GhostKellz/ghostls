# GhostLS - Ghostlang Language Server Protocol

**GhostLS** - A native Zig implementation of a Language Server Protocol (LSP) server for Ghostlang, powered by Grove's tree-sitter grammar.

## Overview

GhostLS provides rich IDE features for Ghostlang in any LSP-compatible editor (VSCode, Neovim, Helix, Zed, etc.). Built entirely in Zig for performance and zero-dependency deployment.

**Repository**: `ghostls/` (to be created)
**Status**: 📋 Design phase
**Grove Version**: v0.1.1+
**Protocol**: LSP 3.17
**Target Editors**: VSCode, Neovim, Helix, Zed, Emacs, Sublime

---

## Architecture

```
┌─────────────────────────────────────────────┐
│           Editor (VSCode/Neovim)            │
│  ┌───────────────────────────────────────┐  │
│  │      LSP Client                       │  │
│  └─────────────────┬─────────────────────┘  │
└────────────────────┼────────────────────────┘
                     │ JSON-RPC
                     ▼
        ┌────────────────────────────┐
        │       GhostLS Server       │
        │  ┌──────────────────────┐  │
        │  │  Message Handler     │  │
        │  └─────────┬────────────┘  │
        │            │                │
        │  ┌─────────▼────────────┐  │
        │  │  Document Manager    │  │
        │  │  - Text Sync         │  │
        │  │  - Version Tracking  │  │
        │  └─────────┬────────────┘  │
        │            │                │
        │  ┌─────────▼────────────┐  │
        │  │  Analysis Engine     │  │
        │  │  - Syntax Parsing    │  │
        │  │  - Semantic Analysis │  │
        │  │  - Diagnostics       │  │
        │  └─────────┬────────────┘  │
        │            │                │
        │  ┌─────────▼────────────┐  │
        │  │  Grove Integration   │  │
        │  │  - Tree-sitter       │  │
        │  │  - Queries           │  │
        │  │  - Incremental Parse │  │
        │  └──────────────────────┘  │
        └────────────────────────────┘
```

---

## LSP Features

### 1. Text Synchronization

**Capabilities**: Full document sync with incremental updates

```zig
const std = @import("std");
const grove = @import("grove");

pub const DocumentManager = struct {
    documents: std.StringHashMap(Document),
    allocator: std.mem.Allocator,

    pub const Document = struct {
        uri: []const u8,
        version: i32,
        text: []const u8,
        tree: ?*grove.Tree,
        parser: *grove.Parser,

        pub fn update(self: *Document, new_text: []const u8, new_version: i32) !void {
            // Free old text
            self.allocator.free(self.text);
            self.text = try self.allocator.dupe(u8, new_text);
            self.version = new_version;

            // Incremental parse with old tree
            const new_tree = try self.parser.parseIncremental(new_text, self.tree);

            if (self.tree) |old_tree| {
                old_tree.deinit();
            }
            self.tree = new_tree;
        }

        pub fn applyChanges(
            self: *Document,
            changes: []const TextDocumentContentChangeEvent,
            new_version: i32,
        ) !void {
            for (changes) |change| {
                if (change.range) |range| {
                    // Incremental change
                    const start_byte = positionToOffset(self.text, range.start);
                    const old_end_byte = positionToOffset(self.text, range.end);

                    // Edit tree
                    const edit = grove.c.TSInputEdit{
                        .start_byte = @intCast(start_byte),
                        .old_end_byte = @intCast(old_end_byte),
                        .new_end_byte = @intCast(start_byte + change.text.len),
                        .start_point = .{
                            .row = @intCast(range.start.line),
                            .column = @intCast(range.start.character),
                        },
                        .old_end_point = .{
                            .row = @intCast(range.end.line),
                            .column = @intCast(range.end.character),
                        },
                        .new_end_point = .{
                            .row = @intCast(range.start.line),
                            .column = @intCast(range.start.character + change.text.len),
                        },
                    };

                    if (self.tree) |tree| {
                        tree.edit(&edit);
                    }

                    // Apply text change
                    var new_text = std.ArrayList(u8).init(self.allocator);
                    try new_text.appendSlice(self.text[0..start_byte]);
                    try new_text.appendSlice(change.text);
                    try new_text.appendSlice(self.text[old_end_byte..]);

                    self.allocator.free(self.text);
                    self.text = try new_text.toOwnedSlice();
                } else {
                    // Full document change
                    try self.update(change.text, new_version);
                }
            }

            // Re-parse with edits applied
            const new_tree = try self.parser.parseIncremental(self.text, self.tree);
            if (self.tree) |old| old.deinit();
            self.tree = new_tree;
            self.version = new_version;
        }
    };

    pub fn open(self: *DocumentManager, uri: []const u8, text: []const u8, version: i32) !void {
        const ghostlang = try grove.Languages.Bundled.ghostlang.get();
        const parser = try grove.Parser.init(ghostlang);

        const tree = try parser.parse(text);

        const doc = Document{
            .uri = try self.allocator.dupe(u8, uri),
            .version = version,
            .text = try self.allocator.dupe(u8, text),
            .tree = tree,
            .parser = parser,
        };

        try self.documents.put(uri, doc);
    }

    pub fn close(self: *DocumentManager, uri: []const u8) void {
        if (self.documents.fetchRemove(uri)) |kv| {
            if (kv.value.tree) |tree| tree.deinit();
            self.allocator.free(kv.value.uri);
            self.allocator.free(kv.value.text);
        }
    }
};

fn positionToOffset(text: []const u8, pos: Position) usize {
    var line: u32 = 0;
    var offset: usize = 0;

    for (text, 0..) |c, i| {
        if (line == pos.line) {
            return i + pos.character;
        }
        if (c == '\n') line += 1;
    }

    return text.len;
}

const Position = struct {
    line: u32,
    character: u32,
};

const TextDocumentContentChangeEvent = struct {
    range: ?Range,
    text: []const u8,
};

const Range = struct {
    start: Position,
    end: Position,
};
```

### 2. Diagnostics (Syntax Errors)

**Capabilities**: Real-time syntax error detection

```zig
pub const DiagnosticEngine = struct {
    allocator: std.mem.Allocator,
    language: *const grove.c.TSLanguage,

    pub fn diagnose(self: *DiagnosticEngine, doc: *Document) ![]Diagnostic {
        const tree = doc.tree orelse return &.{};
        const root = tree.rootNode();

        var diagnostics = std.ArrayList(Diagnostic).init(self.allocator);

        // Find ERROR nodes
        try self.findErrors(root, doc.text, &diagnostics);

        // Check for missing semicolons
        try self.checkSemicolons(root, doc.text, &diagnostics);

        // Check for undefined variables (using locals.scm)
        try self.checkUndefinedVars(tree, doc.text, &diagnostics);

        return diagnostics.toOwnedSlice();
    }

    fn findErrors(
        self: *DiagnosticEngine,
        node: grove.Node,
        text: []const u8,
        diagnostics: *std.ArrayList(Diagnostic),
    ) !void {
        if (node.isError() or std.mem.eql(u8, node.type(), "ERROR")) {
            const range = nodeToRange(node);
            const node_text = node.text(text);

            try diagnostics.append(.{
                .range = range,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Syntax error: unexpected '{s}'",
                    .{node_text},
                ),
                .source = "ghostls",
            });
        }

        if (node.isMissing()) {
            const range = nodeToRange(node);
            try diagnostics.append(.{
                .range = range,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Expected {s}",
                    .{node.type()},
                ),
                .source = "ghostls",
            });
        }

        // Recurse
        var cursor = node.walk();
        if (cursor.gotoFirstChild()) {
            while (true) {
                try self.findErrors(cursor.currentNode(), text, diagnostics);
                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    fn checkUndefinedVars(
        self: *DiagnosticEngine,
        tree: *grove.Tree,
        text: []const u8,
        diagnostics: *std.ArrayList(Diagnostic),
    ) !void {
        const query_source = @embedFile("vendor/tree-sitter-ghostlang/queries/locals.scm");
        const query = try grove.Query.init(self.language, query_source);
        defer query.deinit();

        var cursor = grove.QueryCursor.init();
        defer cursor.deinit();

        const root = tree.rootNode();

        // Build symbol table
        var defined = std.StringHashMap(void).init(self.allocator);
        defer defined.deinit();

        const matches = cursor.matches(query, root, text);
        while (matches.next()) |match| {
            for (match.captures) |capture| {
                const name = query.captureNameForId(capture.index);
                if (std.mem.indexOf(u8, name, "definition") != null) {
                    const symbol = capture.node.text(text);
                    try defined.put(symbol, {});
                }
            }
        }

        // Check references
        cursor.reset();
        const ref_matches = cursor.matches(query, root, text);
        while (ref_matches.next()) |match| {
            for (match.captures) |capture| {
                const name = query.captureNameForId(capture.index);
                if (std.mem.eql(u8, name, "local.reference")) {
                    const symbol = capture.node.text(text);
                    if (!defined.contains(symbol) and !isBuiltin(symbol)) {
                        try diagnostics.append(.{
                            .range = nodeToRange(capture.node),
                            .severity = .Warning,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Undefined variable: '{s}'",
                                .{symbol},
                            ),
                            .source = "ghostls",
                        });
                    }
                }
            }
        }
    }
};

const Diagnostic = struct {
    range: Range,
    severity: DiagnosticSeverity,
    message: []const u8,
    source: []const u8,
};

const DiagnosticSeverity = enum(u32) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
};

fn isBuiltin(name: []const u8) bool {
    const builtins = [_][]const u8{
        "arraySet", "arrayPop", "objectKeys", "pairs", "ipairs",
        "log", "print", "type", "len",
        // ... all 44+ helpers
    };

    for (builtins) |builtin| {
        if (std.mem.eql(u8, name, builtin)) return true;
    }
    return false;
}
```

### 3. Go to Definition

**Capabilities**: Jump to function/variable definitions

```zig
pub const DefinitionProvider = struct {
    allocator: std.mem.Allocator,
    language: *const grove.c.TSLanguage,

    pub fn findDefinition(
        self: *DefinitionProvider,
        doc: *Document,
        position: Position,
    ) !?Location {
        const tree = doc.tree orelse return null;
        const root = tree.rootNode();

        // Find node at cursor position
        const offset = positionToOffset(doc.text, position);
        const node = root.descendantForByteRange(offset, offset) orelse return null;

        // Check if it's an identifier
        if (!std.mem.eql(u8, node.type(), "identifier")) return null;

        const symbol = node.text(doc.text);

        // Use locals.scm to find definition
        const query_source = @embedFile("vendor/tree-sitter-ghostlang/queries/locals.scm");
        const query = try grove.Query.init(self.language, query_source);
        defer query.deinit();

        var cursor = grove.QueryCursor.init();
        defer cursor.deinit();

        const matches = cursor.matches(query, root, doc.text);
        while (matches.next()) |match| {
            for (match.captures) |capture| {
                const capture_name = query.captureNameForId(capture.index);

                if (std.mem.indexOf(u8, capture_name, "definition") != null) {
                    const def_text = capture.node.text(doc.text);
                    if (std.mem.eql(u8, def_text, symbol)) {
                        return Location{
                            .uri = doc.uri,
                            .range = nodeToRange(capture.node),
                        };
                    }
                }
            }
        }

        return null;
    }
};

const Location = struct {
    uri: []const u8,
    range: Range,
};
```

### 4. Find References

**Capabilities**: Find all references to a symbol

```zig
pub const ReferencesProvider = struct {
    allocator: std.mem.Allocator,
    language: *const grove.c.TSLanguage,

    pub fn findReferences(
        self: *ReferencesProvider,
        doc: *Document,
        position: Position,
        include_declaration: bool,
    ) ![]Location {
        const tree = doc.tree orelse return &.{};
        const root = tree.rootNode();

        const offset = positionToOffset(doc.text, position);
        const node = root.descendantForByteRange(offset, offset) orelse return &.{};

        if (!std.mem.eql(u8, node.type(), "identifier")) return &.{};

        const symbol = node.text(doc.text);

        const query_source = @embedFile("vendor/tree-sitter-ghostlang/queries/locals.scm");
        const query = try grove.Query.init(self.language, query_source);
        defer query.deinit();

        var cursor = grove.QueryCursor.init();
        defer cursor.deinit();

        var locations = std.ArrayList(Location).init(self.allocator);

        const matches = cursor.matches(query, root, doc.text);
        while (matches.next()) |match| {
            for (match.captures) |capture| {
                const capture_name = query.captureNameForId(capture.index);
                const ref_text = capture.node.text(doc.text);

                if (std.mem.eql(u8, ref_text, symbol)) {
                    const is_definition = std.mem.indexOf(u8, capture_name, "definition") != null;

                    if (is_definition and !include_declaration) continue;

                    try locations.append(.{
                        .uri = doc.uri,
                        .range = nodeToRange(capture.node),
                    });
                }
            }
        }

        return locations.toOwnedSlice();
    }
};
```

### 5. Auto-completion

**Capabilities**: Context-aware completion suggestions

```zig
pub const CompletionProvider = struct {
    allocator: std.mem.Allocator,
    language: *const grove.c.TSLanguage,

    pub fn complete(
        self: *CompletionProvider,
        doc: *Document,
        position: Position,
    ) ![]CompletionItem {
        const tree = doc.tree orelse return &.{};
        const root = tree.rootNode();

        var items = std.ArrayList(CompletionItem).init(self.allocator);

        // Add built-in helpers
        try items.appendSlice(&BUILTIN_COMPLETIONS);

        // Add keywords
        try items.appendSlice(&KEYWORD_COMPLETIONS);

        // Add local symbols from locals.scm
        const query_source = @embedFile("vendor/tree-sitter-ghostlang/queries/locals.scm");
        const query = try grove.Query.init(self.language, query_source);
        defer query.deinit();

        var cursor = grove.QueryCursor.init();
        defer cursor.deinit();

        const matches = cursor.matches(query, root, doc.text);
        while (matches.next()) |match| {
            for (match.captures) |capture| {
                const capture_name = query.captureNameForId(capture.index);

                if (std.mem.indexOf(u8, capture_name, "definition") != null) {
                    const symbol = capture.node.text(doc.text);

                    try items.append(.{
                        .label = symbol,
                        .kind = if (std.mem.indexOf(u8, capture_name, "function") != null)
                            .Function
                        else
                            .Variable,
                        .detail = capture_name,
                    });
                }
            }
        }

        return items.toOwnedSlice();
    }
};

const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind,
    detail: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    insertText: ?[]const u8 = null,
};

const CompletionItemKind = enum(u32) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
};

const BUILTIN_COMPLETIONS = [_]CompletionItem{
    .{
        .label = "arraySet",
        .kind = .Function,
        .detail = "arraySet(array, index, value) -> array",
        .documentation = "Set array element at index. Appends if index equals length.",
        .insertText = "arraySet($1, $2, $3)",
    },
    .{
        .label = "arrayPop",
        .kind = .Function,
        .detail = "arrayPop(array) -> value",
        .documentation = "Remove and return last array element.",
        .insertText = "arrayPop($1)",
    },
    .{
        .label = "objectKeys",
        .kind = .Function,
        .detail = "objectKeys(object) -> array",
        .documentation = "Returns array of object keys.",
        .insertText = "objectKeys($1)",
    },
    // ... all 44+ helpers
};

const KEYWORD_COMPLETIONS = [_]CompletionItem{
    .{ .label = "function", .kind = .Keyword, .insertText = "function $1($2) {\n  $3\n}" },
    .{ .label = "local", .kind = .Keyword },
    .{ .label = "for", .kind = .Keyword, .insertText = "for $1 in $2 do\n  $3\nend" },
    .{ .label = "while", .kind = .Keyword, .insertText = "while $1 do\n  $2\nend" },
    .{ .label = "if", .kind = .Keyword, .insertText = "if $1 then\n  $2\nend" },
    .{ .label = "repeat", .kind = .Keyword, .insertText = "repeat\n  $1\nuntil $2" },
};
```

### 6. Hover Information

**Capabilities**: Show type/documentation on hover

```zig
pub const HoverProvider = struct {
    allocator: std.mem.Allocator,
    language: *const grove.c.TSLanguage,

    pub fn hover(
        self: *HoverProvider,
        doc: *Document,
        position: Position,
    ) !?Hover {
        const tree = doc.tree orelse return null;
        const root = tree.rootNode();

        const offset = positionToOffset(doc.text, position);
        const node = root.descendantForByteRange(offset, offset) orelse return null;

        const node_type = node.type();

        // Function calls - show signature
        if (std.mem.eql(u8, node_type, "call_expression")) {
            const func_node = node.childByFieldName("function") orelse return null;
            const func_name = func_node.text(doc.text);

            if (getBuiltinDoc(func_name)) |doc_text| {
                return Hover{
                    .contents = .{
                        .kind = .Markdown,
                        .value = doc_text,
                    },
                    .range = nodeToRange(func_node),
                };
            }
        }

        // Identifiers - show definition
        if (std.mem.eql(u8, node_type, "identifier")) {
            const symbol = node.text(doc.text);

            // Find definition
            const query_source = @embedFile("vendor/tree-sitter-ghostlang/queries/locals.scm");
            const query = try grove.Query.init(self.language, query_source);
            defer query.deinit();

            var cursor = grove.QueryCursor.init();
            defer cursor.deinit();

            const matches = cursor.matches(query, root, doc.text);
            while (matches.next()) |match| {
                for (match.captures) |capture| {
                    const capture_name = query.captureNameForId(capture.index);

                    if (std.mem.indexOf(u8, capture_name, "definition.function") != null) {
                        const def_text = capture.node.text(doc.text);
                        if (std.mem.eql(u8, def_text, symbol)) {
                            // Extract function signature
                            const parent = capture.node.parent() orelse continue;
                            const params_node = parent.childByFieldName("parameters");
                            const params = if (params_node) |p| p.text(doc.text) else "()";

                            const markdown = try std.fmt.allocPrint(
                                self.allocator,
                                "```ghostlang\nfunction {s}{s}\n```",
                                .{ symbol, params },
                            );

                            return Hover{
                                .contents = .{
                                    .kind = .Markdown,
                                    .value = markdown,
                                },
                                .range = nodeToRange(node),
                            };
                        }
                    }
                }
            }
        }

        return null;
    }
};

const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

const MarkupContent = struct {
    kind: MarkupKind,
    value: []const u8,
};

const MarkupKind = enum {
    PlainText,
    Markdown,
};

fn getBuiltinDoc(name: []const u8) ?[]const u8 {
    const docs = std.ComptimeStringMap([]const u8, .{
        .{ "arraySet", "```ghostlang\narraySet(array, index, value) -> array\n```\n\nSet element at index. Appends if index equals length." },
        .{ "arrayPop", "```ghostlang\narrayPop(array) -> value\n```\n\nRemove and return last element." },
        .{ "objectKeys", "```ghostlang\nobjectKeys(object) -> array\n```\n\nReturns array of object keys." },
        .{ "pairs", "```ghostlang\npairs(table) -> iterator\n```\n\nReturns iterator for key-value traversal." },
        .{ "ipairs", "```ghostlang\nipairs(array) -> iterator\n```\n\nReturns iterator for 1-based array traversal." },
        // ... all 44+ helpers
    });

    return docs.get(name);
}
```

### 7. Document Symbols (Outline)

**Capabilities**: Show document outline/structure

```zig
pub const DocumentSymbolProvider = struct {
    allocator: std.mem.Allocator,
    language: *const grove.c.TSLanguage,

    pub fn symbols(self: *DocumentSymbolProvider, doc: *Document) ![]DocumentSymbol {
        const tree = doc.tree orelse return &.{};
        const root = tree.rootNode();

        const query_source = @embedFile("vendor/tree-sitter-ghostlang/queries/locals.scm");
        const query = try grove.Query.init(self.language, query_source);
        defer query.deinit();

        var cursor = grove.QueryCursor.init();
        defer cursor.deinit();

        var symbols = std.ArrayList(DocumentSymbol).init(self.allocator);

        const matches = cursor.matches(query, root, doc.text);
        while (matches.next()) |match| {
            for (match.captures) |capture| {
                const capture_name = query.captureNameForId(capture.index);

                if (std.mem.indexOf(u8, capture_name, "definition") != null) {
                    const symbol_name = capture.node.text(doc.text);
                    const parent = capture.node.parent() orelse continue;

                    const kind: SymbolKind = if (std.mem.indexOf(u8, capture_name, "function") != null)
                        .Function
                    else
                        .Variable;

                    try symbols.append(.{
                        .name = symbol_name,
                        .kind = kind,
                        .range = nodeToRange(parent),
                        .selectionRange = nodeToRange(capture.node),
                    });
                }
            }
        }

        return symbols.toOwnedSlice();
    }
};

const DocumentSymbol = struct {
    name: []const u8,
    kind: SymbolKind,
    range: Range,
    selectionRange: Range,
    children: []DocumentSymbol = &.{},
};

const SymbolKind = enum(u32) {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
};
```

### 8. Formatting

**Capabilities**: Code formatting

```zig
pub const FormattingProvider = struct {
    allocator: std.mem.Allocator,

    pub fn format(self: *FormattingProvider, doc: *Document, options: FormattingOptions) ![]TextEdit {
        const tree = doc.tree orelse return &.{};
        const root = tree.rootNode();

        var formatted = std.ArrayList(u8).init(self.allocator);

        try self.formatNode(root, doc.text, &formatted, 0, options);

        const new_text = try formatted.toOwnedSlice();

        return &[_]TextEdit{.{
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{
                    .line = @intCast(std.mem.count(u8, doc.text, "\n")),
                    .character = 0,
                },
            },
            .newText = new_text,
        }};
    }

    fn formatNode(
        self: *FormattingProvider,
        node: grove.Node,
        source: []const u8,
        output: *std.ArrayList(u8),
        indent_level: u32,
        options: FormattingOptions,
    ) !void {
        const node_type = node.type();

        // Add indentation
        const indent = if (options.insertSpaces)
            try self.allocator.alloc(u8, indent_level * options.tabSize)
        else
            try self.allocator.alloc(u8, indent_level);
        defer self.allocator.free(indent);

        @memset(indent, if (options.insertSpaces) ' ' else '\t');

        // Format based on node type
        if (std.mem.eql(u8, node_type, "function_declaration")) {
            try output.appendSlice(indent);
            try output.appendSlice("function ");

            const name_node = node.childByFieldName("name").?;
            try output.appendSlice(name_node.text(source));

            const params_node = node.childByFieldName("parameters").?;
            try output.appendSlice(params_node.text(source));

            try output.appendSlice(" {\n");

            const body_node = node.childByFieldName("body").?;
            try self.formatNode(body_node, source, output, indent_level + 1, options);

            try output.appendSlice(indent);
            try output.appendSlice("}\n");
        } else {
            // Default: preserve original text
            try output.appendSlice(node.text(source));
        }
    }
};

const FormattingOptions = struct {
    tabSize: u32 = 4,
    insertSpaces: bool = true,
};

const TextEdit = struct {
    range: Range,
    newText: []const u8,
};
```

---

## Server Implementation

### Main Server Loop

```zig
const std = @import("std");
const grove = @import("grove");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try GhostLSServer.init(allocator);
    defer server.deinit();

    try server.run();
}

pub const GhostLSServer = struct {
    allocator: std.mem.Allocator,
    documents: DocumentManager,
    diagnostics: DiagnosticEngine,
    definitions: DefinitionProvider,
    references: ReferencesProvider,
    completions: CompletionProvider,
    hover: HoverProvider,
    symbols: DocumentSymbolProvider,
    formatting: FormattingProvider,

    pub fn init(allocator: std.mem.Allocator) !GhostLSServer {
        const ghostlang = try grove.Languages.Bundled.ghostlang.get();

        return .{
            .allocator = allocator,
            .documents = DocumentManager{
                .documents = std.StringHashMap(Document).init(allocator),
                .allocator = allocator,
            },
            .diagnostics = DiagnosticEngine{
                .allocator = allocator,
                .language = ghostlang.raw(),
            },
            .definitions = DefinitionProvider{
                .allocator = allocator,
                .language = ghostlang.raw(),
            },
            .references = ReferencesProvider{
                .allocator = allocator,
                .language = ghostlang.raw(),
            },
            .completions = CompletionProvider{
                .allocator = allocator,
                .language = ghostlang.raw(),
            },
            .hover = HoverProvider{
                .allocator = allocator,
                .language = ghostlang.raw(),
            },
            .symbols = DocumentSymbolProvider{
                .allocator = allocator,
                .language = ghostlang.raw(),
            },
            .formatting = FormattingProvider{
                .allocator = allocator,
            },
        };
    }

    pub fn run(self: *GhostLSServer) !void {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdOut().writer();

        while (true) {
            // Read JSON-RPC message
            const message = try self.readMessage(stdin);
            defer self.allocator.free(message);

            // Parse and handle
            const response = try self.handleMessage(message);
            defer if (response) |r| self.allocator.free(r);

            // Send response
            if (response) |r| {
                try self.writeMessage(stdout, r);
            }
        }
    }

    fn handleMessage(self: *GhostLSServer, message: []const u8) !?[]const u8 {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            message,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;
        const method = obj.get("method").?.string;

        if (std.mem.eql(u8, method, "initialize")) {
            return try self.handleInitialize(obj);
        } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            try self.handleDidOpen(obj);
            return null;
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            try self.handleDidChange(obj);
            return null;
        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            return try self.handleDefinition(obj);
        } else if (std.mem.eql(u8, method, "textDocument/completion")) {
            return try self.handleCompletion(obj);
        }
        // ... handle other methods

        return null;
    }

    fn readMessage(self: *GhostLSServer, reader: anytype) ![]const u8 {
        // Read Content-Length header
        var headers = std.ArrayList(u8).init(self.allocator);
        defer headers.deinit();

        while (true) {
            const line = try reader.readUntilDelimiterAlloc(
                self.allocator,
                '\n',
                8192,
            );
            defer self.allocator.free(line);

            if (line.len <= 1) break; // Empty line

            try headers.appendSlice(line);
            try headers.append('\n');
        }

        // Parse Content-Length
        const content_length = blk: {
            const header_text = headers.items;
            const prefix = "Content-Length: ";
            const start = std.mem.indexOf(u8, header_text, prefix) orelse return error.InvalidHeader;
            const end = std.mem.indexOfPos(u8, header_text, start, "\r\n") orelse return error.InvalidHeader;
            break :blk try std.fmt.parseInt(usize, header_text[start + prefix.len .. end], 10);
        };

        // Read message body
        const message = try self.allocator.alloc(u8, content_length);
        try reader.readNoEof(message);

        return message;
    }

    fn writeMessage(self: *GhostLSServer, writer: anytype, message: []const u8) !void {
        try writer.print("Content-Length: {d}\r\n\r\n{s}", .{ message.len, message });
    }
};
```

---

## Editor Integration

### VSCode Extension

**package.json**:
```json
{
  "name": "ghostlang",
  "displayName": "Ghostlang",
  "version": "0.1.0",
  "engines": { "vscode": "^1.75.0" },
  "categories": ["Programming Languages"],
  "activationEvents": ["onLanguage:ghostlang"],
  "main": "./out/extension.js",
  "contributes": {
    "languages": [{
      "id": "ghostlang",
      "extensions": [".ghost", ".gza"],
      "configuration": "./language-configuration.json"
    }],
    "grammars": [{
      "language": "ghostlang",
      "scopeName": "source.ghostlang",
      "path": "./syntaxes/ghostlang.tmLanguage.json"
    }],
    "configuration": {
      "title": "GhostLS",
      "properties": {
        "ghostls.enable": {
          "type": "boolean",
          "default": true,
          "description": "Enable GhostLS language server"
        },
        "ghostls.path": {
          "type": "string",
          "default": "ghostls",
          "description": "Path to ghostls executable"
        }
      }
    }
  }
}
```

**src/extension.ts**:
```typescript
import * as vscode from 'vscode';
import { LanguageClient, ServerOptions, LanguageClientOptions } from 'vscode-languageclient/node';

let client: LanguageClient;

export function activate(context: vscode.ExtensionContext) {
    const config = vscode.workspace.getConfiguration('ghostls');
    const ghostlsPath = config.get<string>('path') || 'ghostls';

    const serverOptions: ServerOptions = {
        command: ghostlsPath,
        args: []
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'ghostlang' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.{ghost,gza}')
        }
    };

    client = new LanguageClient(
        'ghostls',
        'GhostLS Language Server',
        serverOptions,
        clientOptions
    );

    client.start();
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
```

### Neovim Configuration

**init.lua**:
```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- Register ghostls
if not configs.ghostls then
    configs.ghostls = {
        default_config = {
            cmd = { 'ghostls' },
            filetypes = { 'ghostlang' },
            root_dir = function(fname)
                return lspconfig.util.find_git_ancestor(fname) or vim.fn.getcwd()
            end,
            settings = {},
        },
    }
end

-- Setup ghostls
lspconfig.ghostls.setup{
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
    on_attach = function(client, bufnr)
        -- Keybindings
        local opts = { noremap=true, silent=true, buffer=bufnr }
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
        vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
        vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
        vim.keymap.set('n', '<leader>f', vim.lsp.buf.format, opts)
    end
}

-- Filetype detection
vim.filetype.add({
    extension = {
        ghost = 'ghostlang',
        gza = 'ghostlang',
    }
})
```

---

## Build Configuration

### build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const grove = b.dependency("grove", .{
        .target = target,
        .optimize = optimize,
        .ghostlang = true,
    });

    const exe = b.addExecutable(.{
        .name = "ghostls",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("grove", grove.module("grove"));

    b.installArtifact(exe);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("grove", grove.module("grove"));

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
```

---

## Roadmap

- [x] Design LSP architecture
- [ ] Implement text synchronization
- [ ] Implement diagnostics
- [ ] Implement go-to-definition
- [ ] Implement find references
- [ ] Implement completion
- [ ] Implement hover
- [ ] Implement document symbols
- [ ] Implement formatting
- [ ] VSCode extension
- [ ] Neovim plugin
- [ ] Helix integration
- [ ] CI/CD for releases
- [ ] Language server protocol tests

---

**GhostLS: Native Zig LSP for Ghostlang powered by Grove** 🚀
