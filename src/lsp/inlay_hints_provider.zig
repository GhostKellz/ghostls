const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Provides inlay hints (inline type annotations and parameter names)
pub const InlayHintsProvider = struct {
    allocator: std.mem.Allocator,

    pub const InlayHint = struct {
        position: protocol.Position,
        label: []const u8,
        kind: InlayHintKind,
        padding_left: bool = false,
        padding_right: bool = false,

        pub fn deinit(self: *InlayHint, allocator: std.mem.Allocator) void {
            allocator.free(self.label);
        }
    };

    pub const InlayHintKind = enum(u32) {
        type = 1,
        parameter = 2,
    };

    pub fn init(allocator: std.mem.Allocator) InlayHintsProvider {
        return .{ .allocator = allocator };
    }

    /// Get inlay hints for a document range
    pub fn getInlayHints(
        self: *InlayHintsProvider,
        tree: *const grove.Tree,
        text: []const u8,
        range: protocol.Range,
    ) ![]InlayHint {
        var hints = std.ArrayList(InlayHint).init(self.allocator);
        errdefer {
            for (hints.items) |*hint| {
                hint.deinit(self.allocator);
            }
            hints.deinit();
        }

        const root_opt = tree.rootNode();
        if (root_opt == null) return try hints.toOwnedSlice();

        const root = root_opt.?;

        // Find type hints for variable declarations
        try self.findTypeHints(root, text, range, &hints);

        // Find parameter name hints for function calls
        try self.findParameterHints(root, text, range, &hints);

        return try hints.toOwnedSlice();
    }

    fn findTypeHints(
        self: *InlayHintsProvider,
        node: grove.Node,
        text: []const u8,
        range: protocol.Range,
        hints: *std.ArrayList(InlayHint),
    ) !void {
        const kind = node.kind();

        // Check if this is a variable declaration
        if (std.mem.eql(u8, kind, "variable_declaration") or
            std.mem.eql(u8, kind, "let_declaration") or
            std.mem.eql(u8, kind, "const_declaration")) {

            const end_pos = node.endPosition();

            // Check if this node is in the requested range
            if (positionInRange(.{ .line = end_pos.row, .character = end_pos.column }, range)) {
                // Try to infer the type from the value
                const inferred_type = try self.inferType(node, text);
                if (inferred_type) |type_str| {
                    defer self.allocator.free(type_str);

                    // Find the identifier position
                    const child_count = node.childCount();
                    var i: u32 = 0;
                    while (i < child_count) : (i += 1) {
                        if (node.child(i)) |child| {
                            const child_kind = child.kind();
                            if (std.mem.eql(u8, child_kind, "identifier")) {
                                const id_end = child.endPosition();

                                const label = try std.fmt.allocPrint(self.allocator, ": {s}", .{type_str});

                                try hints.append(.{
                                    .position = .{
                                        .line = id_end.row,
                                        .character = id_end.column,
                                    },
                                    .label = label,
                                    .kind = .type,
                                    .padding_left = false,
                                    .padding_right = true,
                                });
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Recursively check children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.findTypeHints(child, text, range, hints);
            }
        }
    }

    fn findParameterHints(
        self: *InlayHintsProvider,
        node: grove.Node,
        text: []const u8,
        range: protocol.Range,
        hints: *std.ArrayList(InlayHint),
    ) !void {
        const kind = node.kind();

        // Check if this is a call expression
        if (std.mem.eql(u8, kind, "call_expression") or std.mem.eql(u8, kind, "call")) {
            const start_pos = node.startPosition();

            if (positionInRange(.{ .line = start_pos.row, .character = start_pos.column }, range)) {
                // Find arguments and add parameter name hints
                // TODO: Implement parameter name hints (requires function signature lookup)
            }
        }

        // Recursively check children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.findParameterHints(child, text, range, hints);
            }
        }
    }

    fn inferType(self: *InlayHintsProvider, node: grove.Node, text: []const u8) !?[]const u8 {
        // Look for the value being assigned
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const kind = child.kind();

                if (std.mem.eql(u8, kind, "number_literal")) {
                    return try self.allocator.dupe(u8, "number");
                } else if (std.mem.eql(u8, kind, "string_literal")) {
                    return try self.allocator.dupe(u8, "string");
                } else if (std.mem.eql(u8, kind, "boolean_literal")) {
                    const start = child.startByte();
                    const end = child.endByte();
                    if (end > start and end <= text.len) {
                        const val = text[start..end];
                        if (std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "false")) {
                            return try self.allocator.dupe(u8, "boolean");
                        }
                    }
                } else if (std.mem.eql(u8, kind, "array_literal")) {
                    return try self.allocator.dupe(u8, "array");
                } else if (std.mem.eql(u8, kind, "object_literal")) {
                    return try self.allocator.dupe(u8, "object");
                } else if (std.mem.eql(u8, kind, "null_literal")) {
                    return try self.allocator.dupe(u8, "null");
                }
            }
        }

        return null;
    }

    pub fn freeHints(self: *InlayHintsProvider, hints: []InlayHint) void {
        for (hints) |*hint| {
            hint.deinit(self.allocator);
        }
        self.allocator.free(hints);
    }
};

fn positionInRange(pos: protocol.Position, range: protocol.Range) bool {
    // Check if pos.line is before range.start.line
    if (pos.line < range.start.line) return false;
    if (pos.line == range.start.line and pos.character < range.start.character) return false;

    // Check if pos.line is after range.end.line
    if (pos.line > range.end.line) return false;
    if (pos.line == range.end.line and pos.character > range.end.character) return false;

    return true;
}
