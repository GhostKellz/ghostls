const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// DiagnosticEngine finds syntax errors using tree-sitter
pub const DiagnosticEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticEngine {
        return .{ .allocator = allocator };
    }

    /// Analyze a document and return diagnostics
    pub fn diagnose(self: *DiagnosticEngine, tree: *const grove.Tree, text: []const u8) ![]protocol.Diagnostic {
        var diagnostics: std.ArrayList(protocol.Diagnostic) = .empty;
        errdefer diagnostics.deinit(self.allocator);

        const root_opt = tree.rootNode();
        if (root_opt) |root| {
            // Find ERROR and MISSING nodes in the tree
            try self.findErrors(root, text, &diagnostics);
        }

        return try diagnostics.toOwnedSlice(self.allocator);
    }

    /// Recursively find error nodes in the tree
    fn findErrors(
        self: *DiagnosticEngine,
        node: grove.Node,
        text: []const u8,
        diagnostics: *std.ArrayList(protocol.Diagnostic),
    ) !void {
        // Check if this node is an ERROR node
        const node_kind = node.kind();
        if (std.mem.eql(u8, node_kind, "ERROR")) {
            const range = nodeToRange(node);
            const start_byte = node.startByte();
            const end_byte = node.endByte();
            const node_text = if (end_byte > start_byte and end_byte <= text.len)
                text[start_byte..end_byte]
            else
                "<error>";

            try diagnostics.append(self.allocator, .{
                .range = range,
                .severity = .Error,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Syntax error near '{s}'",
                    .{node_text},
                ),
                .source = "ghostls",
            });
        }

        // Recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child_node| {
                try self.findErrors(child_node, text, diagnostics);
            }
        }
    }
};

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
