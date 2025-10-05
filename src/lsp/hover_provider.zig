const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// HoverProvider provides hover information for positions in the document
pub const HoverProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HoverProvider {
        return .{ .allocator = allocator };
    }

    /// Get hover information for a position in the document
    pub fn hover(
        self: *HoverProvider,
        tree: *const grove.Tree,
        text: []const u8,
        position: protocol.Position,
    ) !?protocol.Hover {
        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the smallest node at the given position
        const node_opt = self.findNodeAtPosition(root, position);
        if (node_opt == null) return null;

        const node = node_opt.?;
        const kind = node.kind();

        // Get the text of the node
        const start_byte = node.startByte();
        const end_byte = node.endByte();
        const node_text = if (end_byte > start_byte and end_byte <= text.len)
            text[start_byte..end_byte]
        else
            "";

        // Build hover content based on node kind
        const hover_text = try self.buildHoverContent(kind, node_text, node);

        return protocol.Hover{
            .contents = .{
                .kind = "markdown",
                .value = hover_text,
            },
            .range = nodeToRange(node),
        };
    }

    /// Find the smallest node that contains the position
    fn findNodeAtPosition(
        self: *HoverProvider,
        node: grove.Node,
        position: protocol.Position,
    ) ?grove.Node {
        const start_pos = node.startPosition();
        const end_pos = node.endPosition();

        // Check if position is within this node's range
        if (!positionInRange(position, start_pos, end_pos)) {
            return null;
        }

        // Check children for a more specific match
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_start = child.startPosition();
                const child_end = child.endPosition();

                if (positionInRange(position, child_start, child_end)) {
                    // Recursively check if a child has a more specific match
                    if (self.findNodeAtPosition(child, position)) |found| {
                        return found;
                    }
                    return child;
                }
            }
        }

        // No child matched, return this node
        return node;
    }

    /// Build hover content based on node kind
    fn buildHoverContent(
        self: *HoverProvider,
        kind: []const u8,
        node_text: []const u8,
        node: grove.Node,
    ) ![]const u8 {
        // Check for common Ghostlang constructs
        if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "function")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Function Declaration**\n\n```ghostlang\n{s}\n```",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "variable_declaration") or
                   std.mem.eql(u8, kind, "let_declaration")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Variable Declaration**\n\n```ghostlang\n{s}\n```",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "identifier")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Identifier**: `{s}`\n\nType: _{s}_",
                .{node_text, kind},
            );
        } else if (std.mem.eql(u8, kind, "type_identifier") or
                   std.mem.eql(u8, kind, "type")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Type**: `{s}`",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "string") or
                   std.mem.eql(u8, kind, "string_literal")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**String Literal**\n\n```\n{s}\n```",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "number") or
                   std.mem.eql(u8, kind, "number_literal") or
                   std.mem.eql(u8, kind, "integer")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Number Literal**: `{s}`",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "comment")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Comment**\n\n> {s}",
                .{node_text},
            );
        }

        // Default hover with node info
        _ = node; // Will use for more advanced info later
        return try std.fmt.allocPrint(
            self.allocator,
            "**Node**: `{s}`\n\n```\n{s}\n```",
            .{kind, node_text},
        );
    }
};

/// Check if a position is within a range
fn positionInRange(
    pos: protocol.Position,
    start: grove.Point,
    end: grove.Point,
) bool {
    // Position is before the start
    if (pos.line < start.row) return false;
    if (pos.line == start.row and pos.character < start.column) return false;

    // Position is after the end
    if (pos.line > end.row) return false;
    if (pos.line == end.row and pos.character > end.column) return false;

    return true;
}

/// Convert a tree-sitter node to LSP range
fn nodeToRange(node: grove.Node) protocol.Range {
    const start_point = node.startPosition();
    const end_point = node.endPosition();

    return .{
        .start = .{
            .line = start_point.row,
            .character = start_point.column,
        },
        .end = .{
            .line = end_point.row,
            .character = end_point.column,
        },
    };
}
