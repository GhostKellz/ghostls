const std = @import("std");
const protocol = @import("protocol.zig");
const grove = @import("grove");
const ffi_loader = @import("ffi_loader.zig");
const DocumentManager = @import("document_manager.zig").DocumentManager;

pub const CompletionProvider = struct {
    allocator: std.mem.Allocator,
    ffi_loader: *ffi_loader.FFILoader,

    pub fn init(allocator: std.mem.Allocator, ffi: *ffi_loader.FFILoader) CompletionProvider {
        return .{
            .allocator = allocator,
            .ffi_loader = ffi,
        };
    }

    /// Get completion items at the given position
    pub fn complete(
        self: *CompletionProvider,
        tree: *grove.Tree,
        text: []const u8,
        position: protocol.Position,
        supports_shell_ffi: bool,
    ) ![]CompletionItem {
        var items: std.ArrayList(CompletionItem) = .empty;
        errdefer items.deinit(self.allocator);

        // Analyze context at cursor position
        const context = try self.analyzeContext(tree, text, position);

        // Filter completions based on context
        switch (context.kind) {
            .AfterDot => {
                // Check if we're after "shell." or "git." namespace
                if (context.namespace) |ns| {
                    if (supports_shell_ffi) {
                        try self.addFFICompletions(ns, &items);
                    }
                } else {
                    // Regular object methods
                    try addObjectMethodCompletions(self.allocator, &items);
                }
            },
            .AfterColon => {
                // After ':' - show type members (future)
                try addBuiltinCompletions(self.allocator, &items);
                if (supports_shell_ffi) {
                    try self.addShellGlobals(&items);
                }
            },
            .InFunctionBody => {
                // Inside function - show local vars, params, builtins
                try addLocalScopeCompletions(self.allocator, &items, context.scope_vars);
                try addBuiltinCompletions(self.allocator, &items);
                if (supports_shell_ffi) {
                    try self.addShellGlobals(&items);
                }
            },
            .TopLevel => {
                // Top-level - show keywords and global functions
                try addKeywordCompletions(self.allocator, &items);
                try addBuiltinCompletions(self.allocator, &items);
                if (supports_shell_ffi) {
                    try self.addShellGlobals(&items);
                }
            },
            .Default => {
                // Default - show everything (fallback to v0.1.0 behavior)
                try addKeywordCompletions(self.allocator, &items);
                try addBuiltinCompletions(self.allocator, &items);
                if (supports_shell_ffi) {
                    try self.addShellGlobals(&items);
                }
            },
        }

        return try items.toOwnedSlice(self.allocator);
    }

    const CompletionContext = struct {
        kind: ContextKind,
        scope_vars: []const []const u8 = &.{},
        namespace: ?[]const u8 = null, // For "shell." or "git." completions

        const ContextKind = enum {
            AfterDot,
            AfterColon,
            InFunctionBody,
            TopLevel,
            Default,
        };
    };

    fn analyzeContext(
        self: *CompletionProvider,
        tree: *grove.Tree,
        text: []const u8,
        position: protocol.Position,
    ) !CompletionContext {
        // Convert LSP position (0-indexed) to byte offset
        const offset = try self.positionToOffset(text, position);

        // Check for trigger characters in the text before cursor
        if (offset > 0 and offset <= text.len) {
            const char_before = text[offset - 1];
            if (char_before == '.') {
                // Check if we're after "shell" or "git" namespace
                const namespace = try self.detectNamespace(text, offset);
                return .{ .kind = .AfterDot, .namespace = namespace };
            }
            if (char_before == ':') {
                return .{ .kind = .AfterColon };
            }
        }

        // Find node at cursor position using tree-sitter
        const root = tree.rootNode() orelse {
            return .{ .kind = .Default };
        };
        const grove_point = grove.Point{ .row = position.line, .column = position.character };
        const node = root.descendantForPointRange(grove_point, grove_point) orelse {
            return .{ .kind = .Default };
        };

        // Check if we're inside a function body
        var current = node;
        while (current.parent()) |parent| {
            const node_type = current.kind();
            if (std.mem.eql(u8, node_type, "function_declaration") or
                std.mem.eql(u8, node_type, "function_definition"))
            {
                // We're inside a function - collect local variables
                const scope_vars = try self.collectLocalVariables(current, text);
                return .{ .kind = .InFunctionBody, .scope_vars = scope_vars };
            }
            current = parent;
        }

        // Default to top-level context
        return .{ .kind = .TopLevel };
    }

    fn positionToOffset(self: *CompletionProvider, text: []const u8, position: protocol.Position) !usize {
        _ = self;
        var line: u32 = 0;
        var offset: usize = 0;

        while (offset < text.len) : (offset += 1) {
            if (line == position.line) {
                // Found the line, now add character offset
                const result = offset + position.character;
                return @min(result, text.len);
            }
            if (text[offset] == '\n') {
                line += 1;
            }
        }

        return offset;
    }

    fn collectLocalVariables(
        self: *CompletionProvider,
        function_node: grove.Node,
        text: []const u8,
    ) ![]const []const u8 {
        var vars: std.ArrayList([]const u8) = .empty;
        errdefer vars.deinit(self.allocator);

        // Traverse function body to find variable declarations
        var cursor = try function_node.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Look for variable declarations
                if (std.mem.eql(u8, node_type, "variable_declaration") or
                    std.mem.eql(u8, node_type, "local_declaration"))
                {
                    // Extract variable name
                    if (node.childByFieldName("name")) |name_node| {
                        const start = name_node.startByte();
                        const end = name_node.endByte();
                        if (end <= text.len) {
                            const var_name = text[start..end];
                            try vars.append(self.allocator, try self.allocator.dupe(u8, var_name));
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }

        return try vars.toOwnedSlice(self.allocator);
    }

    /// Detect if cursor is after a namespace identifier like "shell" or "git"
    fn detectNamespace(self: *CompletionProvider, text: []const u8, offset: usize) !?[]const u8 {
        _ = self;
        // Look backward from the dot to find the identifier
        if (offset < 2) return null;

        var i = offset - 2; // Skip the dot
        var end = offset - 1;

        // Skip whitespace
        while (i > 0 and (text[i] == ' ' or text[i] == '\t')) : (i -= 1) {}
        end = i + 1;

        // Find start of identifier
        while (i > 0 and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) : (i -= 1) {}
        if (i > 0 and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) {
            i = 0;
        } else {
            i += 1;
        }

        const identifier = text[i..end];

        // Return const string literals for known namespaces (safer for lifetime)
        if (std.mem.eql(u8, identifier, "shell")) {
            return "shell";
        } else if (std.mem.eql(u8, identifier, "git")) {
            return "git";
        } else if (std.mem.eql(u8, identifier, "web3")) {
            return "web3";
        }

        return null;
    }

    /// Add FFI completions for a specific namespace (shell, git, or web3)
    fn addFFICompletions(
        self: *CompletionProvider,
        namespace: []const u8,
        items: *std.ArrayList(CompletionItem),
    ) !void {
        const funcs = self.ffi_loader.getFunctions(namespace) orelse return;

        var func_iter = funcs.iterator();
        while (func_iter.next()) |entry| {
            const func = entry.value_ptr.*;

            const detail = try self.allocator.dupe(u8, func.signature);
            const documentation = try self.allocator.dupe(u8, func.description);

            try items.append(self.allocator, .{
                .label = try self.allocator.dupe(u8, func.name),
                .kind = .Function,
                .detail = detail,
                .documentation = documentation,
                .insertText = null,
            });
        }
    }

    /// Add shell global variables (SHELL_VERSION, HOME, PATH, etc.)
    fn addShellGlobals(self: *CompletionProvider, items: *std.ArrayList(CompletionItem)) !void {
        // Add shell namespace globals
        if (self.ffi_loader.getGlobals("shell")) |globals| {
            var global_iter = globals.iterator();
            while (global_iter.next()) |entry| {
                const global = entry.value_ptr.*;

                const detail_str = try std.fmt.allocPrint(
                    self.allocator,
                    "global: {s}{s}",
                    .{ global.type, if (global.readonly) " (readonly)" else "" },
                );

                try items.append(self.allocator, .{
                    .label = try self.allocator.dupe(u8, global.name),
                    .kind = .Variable,
                    .detail = detail_str,
                    .documentation = try self.allocator.dupe(u8, global.description),
                    .insertText = null,
                });
            }
        }
    }

    fn addLocalScopeCompletions(
        allocator: std.mem.Allocator,
        items: *std.ArrayList(CompletionItem),
        local_vars: []const []const u8,
    ) !void {
        for (local_vars) |var_name| {
            try items.append(allocator, .{
                .label = try allocator.dupe(u8, var_name),
                .kind = .Variable,
                .detail = try allocator.dupe(u8, "local variable"),
                .documentation = null,
                .insertText = null,
            });
        }
    }

    fn addObjectMethodCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
        // Object/array methods that appear after '.'
        const methods = [_]struct { label: []const u8, detail: []const u8, doc: []const u8 }{
            .{ .label = "push", .detail = "method(value: any)", .doc = "Add element to array" },
            .{ .label = "pop", .detail = "method(): any", .doc = "Remove and return last element" },
            .{ .label = "length", .detail = "property: number", .doc = "Array/string length" },
            .{ .label = "get", .detail = "method(key: string): any", .doc = "Get property value" },
            .{ .label = "set", .detail = "method(key: string, value: any)", .doc = "Set property value" },
            .{ .label = "keys", .detail = "method(): Array", .doc = "Get object keys" },
            .{ .label = "values", .detail = "method(): Array", .doc = "Get object values" },
            .{ .label = "indexOf", .detail = "method(search: any): number", .doc = "Find element index" },
            .{ .label = "slice", .detail = "method(start: number, end: number): Array", .doc = "Extract array slice" },
            .{ .label = "join", .detail = "method(separator: string): string", .doc = "Join elements" },
        };

        for (methods) |method| {
            try items.append(allocator, .{
                .label = try allocator.dupe(u8, method.label),
                .kind = .Method,
                .detail = try allocator.dupe(u8, method.detail),
                .documentation = try allocator.dupe(u8, method.doc),
                .insertText = null,
            });
        }
    }

    pub fn freeCompletions(self: *CompletionProvider, items: []CompletionItem) void {
        for (items) |item| {
            self.allocator.free(item.label);
            if (item.detail) |detail| self.allocator.free(detail);
            if (item.documentation) |doc| self.allocator.free(doc);
            if (item.insertText) |text| self.allocator.free(text);
        }
        self.allocator.free(items);
    }

    fn addKeywordCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
        const keywords = [_]struct { label: []const u8, detail: []const u8 }{
            .{ .label = "var", .detail = "Variable declaration" },
            .{ .label = "local", .detail = "Local variable declaration" },
            .{ .label = "function", .detail = "Function declaration" },
            .{ .label = "if", .detail = "If statement" },
            .{ .label = "else", .detail = "Else clause" },
            .{ .label = "while", .detail = "While loop" },
            .{ .label = "for", .detail = "For loop" },
            .{ .label = "in", .detail = "For-in iterator" },
            .{ .label = "do", .detail = "Do block" },
            .{ .label = "end", .detail = "End block" },
            .{ .label = "repeat", .detail = "Repeat-until loop" },
            .{ .label = "until", .detail = "Until condition" },
            .{ .label = "return", .detail = "Return statement" },
            .{ .label = "break", .detail = "Break statement" },
            .{ .label = "continue", .detail = "Continue statement" },
        };

        for (keywords) |kw| {
            try items.append(allocator, .{
                .label = try allocator.dupe(u8, kw.label),
                .kind = .Keyword,
                .detail = try allocator.dupe(u8, kw.detail),
                .documentation = null,
                .insertText = null,
            });
        }
    }

    fn addBuiltinCompletions(allocator: std.mem.Allocator, items: *std.ArrayList(CompletionItem)) !void {
        const builtins = [_]struct { label: []const u8, detail: []const u8, doc: []const u8 }{
            // Blockchain APIs (GhostLang v0.2.3+)
            .{ .label = "emit", .detail = "function(event_name: string, data: table)", .doc = "Emit a blockchain event with name and data payload" },

            // Editor APIs
            .{ .label = "getCurrentLine", .detail = "function(): number", .doc = "Get current cursor line number" },
            .{ .label = "getLineText", .detail = "function(line: number): string", .doc = "Get text of specified line" },
            .{ .label = "setLineText", .detail = "function(line: number, text: string)", .doc = "Set text of specified line" },
            .{ .label = "insertText", .detail = "function(text: string)", .doc = "Insert text at cursor position" },
            .{ .label = "getAllText", .detail = "function(): string", .doc = "Get all buffer text" },
            .{ .label = "replaceAllText", .detail = "function(text: string)", .doc = "Replace all buffer text" },
            .{ .label = "getCursorPosition", .detail = "function(): {line: number, col: number}", .doc = "Get cursor position" },
            .{ .label = "setCursorPosition", .detail = "function(line: number, col: number)", .doc = "Set cursor position" },
            .{ .label = "getSelection", .detail = "function(): {start: Position, end: Position}", .doc = "Get current selection" },
            .{ .label = "setSelection", .detail = "function(start: Position, end: Position)", .doc = "Set selection range" },
            .{ .label = "getSelectedText", .detail = "function(): string", .doc = "Get selected text" },
            .{ .label = "replaceSelection", .detail = "function(text: string)", .doc = "Replace selected text" },
            .{ .label = "getFilename", .detail = "function(): string", .doc = "Get current file name" },
            .{ .label = "getFileLanguage", .detail = "function(): string", .doc = "Get current file language" },
            .{ .label = "isModified", .detail = "function(): boolean", .doc = "Check if buffer is modified" },
            .{ .label = "notify", .detail = "function(message: string)", .doc = "Show notification message" },
            .{ .label = "log", .detail = "function(message: string)", .doc = "Log message to console" },
            .{ .label = "prompt", .detail = "function(message: string): string", .doc = "Prompt user for input" },

            // String utilities
            .{ .label = "findAll", .detail = "function(text: string, pattern: string): Array", .doc = "Find all pattern matches" },
            .{ .label = "replaceAll", .detail = "function(text: string, pattern: string, replacement: string): string", .doc = "Replace all occurrences" },
            .{ .label = "split", .detail = "function(text: string, delimiter: string): Array", .doc = "Split string by delimiter" },
            .{ .label = "join", .detail = "function(array: Array, separator: string): string", .doc = "Join array elements" },
            .{ .label = "substring", .detail = "function(text: string, start: number, end: number): string", .doc = "Extract substring" },
            .{ .label = "indexOf", .detail = "function(text: string, search: string): number", .doc = "Find index of substring" },
            .{ .label = "replace", .detail = "function(text: string, pattern: string, replacement: string): string", .doc = "Replace first occurrence" },

            // Array utilities
            .{ .label = "createArray", .detail = "function(): Array", .doc = "Create new array" },
            .{ .label = "arrayPush", .detail = "function(array: Array, value: any)", .doc = "Add element to array" },
            .{ .label = "arraySet", .detail = "function(array: Array, index: number, value: any)", .doc = "Set array element" },
            .{ .label = "arrayPop", .detail = "function(array: Array): any", .doc = "Remove and return last element" },
            .{ .label = "arrayLength", .detail = "function(array: Array): number", .doc = "Get array length" },
            .{ .label = "arrayGet", .detail = "function(array: Array, index: number): any", .doc = "Get array element" },

            // Object utilities
            .{ .label = "createObject", .detail = "function(): Object", .doc = "Create new object" },
            .{ .label = "objectSet", .detail = "function(object: Object, key: string, value: any)", .doc = "Set object property" },
            .{ .label = "objectGet", .detail = "function(object: Object, key: string): any", .doc = "Get object property" },
            .{ .label = "objectKeys", .detail = "function(object: Object): Array", .doc = "Get object keys" },

            // Iterators
            .{ .label = "pairs", .detail = "function(table: Table): Iterator", .doc = "Iterate over key-value pairs" },
            .{ .label = "ipairs", .detail = "function(array: Array): Iterator", .doc = "Iterate over array indices" },

            // Math library (v0.2.0)
            .{ .label = "floor", .detail = "function(x: number): number", .doc = "Round down to nearest integer" },
            .{ .label = "ceil", .detail = "function(x: number): number", .doc = "Round up to nearest integer" },
            .{ .label = "abs", .detail = "function(x: number): number", .doc = "Return absolute value" },
            .{ .label = "sqrt", .detail = "function(x: number): number", .doc = "Return square root" },
            .{ .label = "min", .detail = "function(...: number): number", .doc = "Return minimum value from arguments" },
            .{ .label = "max", .detail = "function(...: number): number", .doc = "Return maximum value from arguments" },
            .{ .label = "random", .detail = "function(min: number, max: number): number", .doc = "Generate random integer between min and max (inclusive)" },

            // Table utilities (v0.2.0)
            .{ .label = "table_clone", .detail = "function(table: Table, deep: boolean): Table", .doc = "Clone a table (shallow by default, deep if second arg is true)" },
            .{ .label = "table_merge", .detail = "function(base: Table, override: Table): Table", .doc = "Recursively merge two tables, override values take precedence" },
            .{ .label = "table_keys", .detail = "function(table: Table): Array", .doc = "Get array of all table keys" },
            .{ .label = "table_values", .detail = "function(table: Table): Array", .doc = "Get array of all table values" },
            .{ .label = "table_find", .detail = "function(array: Array, value: any): number", .doc = "Find first index of value in array (returns nil if not found)" },
            .{ .label = "table_map", .detail = "function(array: Array, mapper: function): Array", .doc = "Map function over array elements" },
            .{ .label = "table_filter", .detail = "function(array: Array, predicate: function): Array", .doc = "Filter array elements by predicate" },

            // String utilities (v0.2.0)
            .{ .label = "string_split", .detail = "function(str: string, delimiter: string): Array", .doc = "Split string by delimiter (empty delimiter splits into characters)" },
            .{ .label = "string_trim", .detail = "function(str: string): string", .doc = "Remove leading and trailing whitespace" },
            .{ .label = "string_starts_with", .detail = "function(str: string, prefix: string): boolean", .doc = "Check if string starts with prefix" },
            .{ .label = "string_ends_with", .detail = "function(str: string, suffix: string): boolean", .doc = "Check if string ends with suffix" },

            // Path utilities (v0.2.0)
            .{ .label = "path_join", .detail = "function(...: string): string", .doc = "Join path components with platform-appropriate separator" },
            .{ .label = "path_basename", .detail = "function(path: string): string", .doc = "Extract filename from path" },
            .{ .label = "path_dirname", .detail = "function(path: string): string", .doc = "Extract directory from path" },
            .{ .label = "path_is_absolute", .detail = "function(path: string): boolean", .doc = "Check if path is absolute" },

            // Table concat (v0.2.0)
            .{ .label = "concat", .detail = "function(array: Array, separator: string): string", .doc = "Join array elements into string with separator" },
        };

        for (builtins) |builtin| {
            try items.append(allocator, .{
                .label = try allocator.dupe(u8, builtin.label),
                .kind = .Function,
                .detail = try allocator.dupe(u8, builtin.detail),
                .documentation = try allocator.dupe(u8, builtin.doc),
                .insertText = null,
            });
        }
    }
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind,
    detail: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    insertText: ?[]const u8 = null,
};

pub const CompletionItemKind = enum(u32) {
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
