const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Provides code actions (quick fixes and refactorings)
pub const CodeActionsProvider = struct {
    allocator: std.mem.Allocator,

    pub const CodeActionKind = enum {
        quick_fix,
        refactor,
        refactor_extract,
        refactor_inline,
        refactor_rewrite,
        source,
        source_organize_imports,

        pub fn toString(self: CodeActionKind) []const u8 {
            return switch (self) {
                .quick_fix => "quickfix",
                .refactor => "refactor",
                .refactor_extract => "refactor.extract",
                .refactor_inline => "refactor.inline",
                .refactor_rewrite => "refactor.rewrite",
                .source => "source",
                .source_organize_imports => "source.organizeImports",
            };
        }
    };

    pub const CodeAction = struct {
        title: []const u8,
        kind: CodeActionKind,
        edit: ?WorkspaceEdit,
        is_preferred: bool = false,

        pub fn deinit(self: *CodeAction, allocator: std.mem.Allocator) void {
            allocator.free(self.title);
            if (self.edit) |*edit| {
                edit.deinit(allocator);
            }
        }
    };

    pub const WorkspaceEdit = struct {
        changes: std.StringHashMap([]TextEdit),

        pub fn deinit(self: *WorkspaceEdit, allocator: std.mem.Allocator) void {
            var it = self.changes.valueIterator();
            while (it.next()) |edits| {
                for (edits.*) |*edit| {
                    allocator.free(edit.new_text);
                }
                allocator.free(edits.*);
            }
            self.changes.deinit();
        }
    };

    pub const TextEdit = struct {
        range: protocol.Range,
        new_text: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) CodeActionsProvider {
        return .{ .allocator = allocator };
    }

    /// Get available code actions for a range in a document
    pub fn getCodeActions(
        self: *CodeActionsProvider,
        tree: *const grove.Tree,
        text: []const u8,
        uri: []const u8,
        range: protocol.Range,
    ) ![]CodeAction {
        var actions = std.ArrayList(CodeAction).init(self.allocator);
        errdefer {
            for (actions.items) |*action| {
                action.deinit(self.allocator);
            }
            actions.deinit();
        }

        const root_opt = tree.rootNode();
        if (root_opt == null) return try actions.toOwnedSlice();

        const root = root_opt.?;

        // Check for missing semicolons
        try self.detectMissingSemicolons(root, text, uri, &actions);

        // Check for unused variables
        try self.detectUnusedVariables(root, text, uri, &actions);

        // Offer extract function refactoring for selected code
        if (!isRangeEmpty(range)) {
            try self.offerExtractFunction(text, uri, range, &actions);
        }

        // Offer inline variable refactoring
        try self.offerInlineVariable(root, text, uri, range, &actions);

        return try actions.toOwnedSlice();
    }

    fn detectMissingSemicolons(
        self: *CodeActionsProvider,
        node: grove.Node,
        text: []const u8,
        uri: []const u8,
        actions: *std.ArrayList(CodeAction),
    ) !void {
        // Check if this node has an error and might be missing a semicolon
        if (node.hasError()) {
            const kind_str = node.kind();
            if (std.mem.eql(u8, kind_str, "expression_statement") or
                std.mem.eql(u8, kind_str, "variable_declaration") or
                std.mem.eql(u8, kind_str, "return_statement")) {

                const end_pos = node.endPosition();
                const end_byte = node.endByte();

                // Check if missing semicolon
                if (end_byte < text.len and text[end_byte - 1] != ';') {
                    const title = try std.fmt.allocPrint(self.allocator, "Add missing semicolon", .{});
                    errdefer self.allocator.free(title);

                    var changes = std.StringHashMap([]TextEdit).init(self.allocator);
                    errdefer changes.deinit();

                    var edits = std.ArrayList(TextEdit).init(self.allocator);
                    defer edits.deinit();

                    const new_text = try self.allocator.dupe(u8, ";");

                    try edits.append(.{
                        .range = .{
                            .start = .{ .line = end_pos.row, .character = end_pos.column },
                            .end = .{ .line = end_pos.row, .character = end_pos.column },
                        },
                        .new_text = new_text,
                    });

                    try changes.put(uri, try edits.toOwnedSlice());

                    try actions.append(.{
                        .title = title,
                        .kind = .quick_fix,
                        .edit = .{ .changes = changes },
                        .is_preferred = true,
                    });
                }
            }
        }

        // Recursively check children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.detectMissingSemicolons(child, text, uri, actions);
            }
        }
    }

    fn detectUnusedVariables(
        self: *CodeActionsProvider,
        node: grove.Node,
        text: []const u8,
        uri: []const u8,
        actions: *std.ArrayList(CodeAction),
    ) !void {
        _ = node;
        _ = text;
        _ = uri;
        _ = actions;
        _ = self;
        // TODO: Implement unused variable detection
        // This requires building a symbol table and usage tracking
    }

    fn offerExtractFunction(
        self: *CodeActionsProvider,
        text: []const u8,
        uri: []const u8,
        range: protocol.Range,
        actions: *std.ArrayList(CodeAction),
    ) !void {
        _ = text;
        _ = uri;
        _ = range;
        _ = actions;
        _ = self;
        // TODO: Implement extract function refactoring
        // This requires analyzing the selected code and generating a new function
    }

    fn offerInlineVariable(
        self: *CodeActionsProvider,
        node: grove.Node,
        text: []const u8,
        uri: []const u8,
        range: protocol.Range,
        actions: *std.ArrayList(CodeAction),
    ) !void {
        _ = node;
        _ = text;
        _ = uri;
        _ = range;
        _ = actions;
        _ = self;
        // TODO: Implement inline variable refactoring
    }

    pub fn freeActions(self: *CodeActionsProvider, actions: []CodeAction) void {
        for (actions) |*action| {
            action.deinit(self.allocator);
        }
        self.allocator.free(actions);
    }
};

fn isRangeEmpty(range: protocol.Range) bool {
    return range.start.line == range.end.line and
        range.start.character == range.end.character;
}
