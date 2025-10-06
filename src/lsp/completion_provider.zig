const std = @import("std");
const protocol = @import("protocol.zig");
const grove = @import("grove");

pub const CompletionProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CompletionProvider {
        return .{ .allocator = allocator };
    }

    /// Get completion items at the given position
    pub fn complete(
        self: *CompletionProvider,
        tree: *grove.Tree,
        text: []const u8,
        position: protocol.Position,
    ) ![]CompletionItem {
        _ = tree;
        _ = text;
        _ = position;

        // For RC1, provide static completion items
        // TODO: Add context-aware completions based on AST

        var items: std.ArrayList(CompletionItem) = .empty;
        errdefer items.deinit(self.allocator);

        // Add keywords
        try addKeywordCompletions(self.allocator, &items);

        // Add built-in functions
        try addBuiltinCompletions(self.allocator, &items);

        return try items.toOwnedSlice(self.allocator);
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
