const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// DocumentHighlightProvider highlights all occurrences of the symbol under cursor
/// Uses Grove's LSP helpers for efficient reference finding
pub const DocumentHighlightProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DocumentHighlightProvider {
        return .{ .allocator = allocator };
    }

    /// Get all highlights for the symbol at the given position
    pub fn getHighlights(
        self: *DocumentHighlightProvider,
        tree: *const grove.Tree,
        text: []const u8,
        position: protocol.Position,
    ) ![]protocol.DocumentHighlight {
        const root = tree.rootNode() orelse {
            return try self.allocator.alloc(protocol.DocumentHighlight, 0);
        };

        // Use Grove's LSP helper to find node at position
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };

        const node_opt = grove.LSP.findNodeAtPosition(root, grove_pos);
        if (node_opt == null) {
            return try self.allocator.alloc(protocol.DocumentHighlight, 0);
        }

        const node = node_opt.?;
        const kind = node.kind();

        // Only highlight identifiers
        if (!std.mem.eql(u8, kind, "identifier") and
            !std.mem.eql(u8, kind, "type_identifier"))
        {
            return try self.allocator.alloc(protocol.DocumentHighlight, 0);
        }

        // Get identifier text
        const start_byte = node.startByte();
        const end_byte = node.endByte();
        if (end_byte <= start_byte or end_byte > text.len) {
            return try self.allocator.alloc(protocol.DocumentHighlight, 0);
        }

        const identifier = text[start_byte..end_byte];

        // Use Grove's LSP helper to find all references
        var grove_refs = try grove.LSP.findReferences(
            self.allocator,
            root,
            identifier,
            text,
        );
        defer grove_refs.deinit(self.allocator);

        // Convert to DocumentHighlight with proper kind (Read vs Write)
        var highlights: std.ArrayList(protocol.DocumentHighlight) = .empty;
        errdefer highlights.deinit(self.allocator);

        for (grove_refs.items) |ref_node| {
            const grove_range = grove.LSP.nodeToRange(ref_node);
            const lsp_range = protocol.Range{
                .start = .{
                    .line = grove_range.start.line,
                    .character = grove_range.start.character,
                },
                .end = .{
                    .line = grove_range.end.line,
                    .character = grove_range.end.character,
                },
            };

            // Determine if this is a write or read reference
            const highlight_kind = self.getHighlightKind(ref_node);

            try highlights.append(self.allocator, .{
                .range = lsp_range,
                .kind = highlight_kind,
            });
        }

        return try highlights.toOwnedSlice(self.allocator);
    }

    /// Determine if a reference is a write or read
    fn getHighlightKind(self: *DocumentHighlightProvider, node: grove.Node) protocol.DocumentHighlightKind {
        _ = self;

        // Check if parent is an assignment or declaration
        if (node.parent()) |parent| {
            const parent_kind = parent.kind();

            // Write: variable declarations, assignments
            if (std.mem.eql(u8, parent_kind, "variable_declaration") or
                std.mem.eql(u8, parent_kind, "const_declaration") or
                std.mem.eql(u8, parent_kind, "let_declaration") or
                std.mem.eql(u8, parent_kind, "assignment_expression") or
                std.mem.eql(u8, parent_kind, "update_expression"))
            {
                return .Write;
            }

            // Check if we're on the left side of an assignment
            if (std.mem.eql(u8, parent_kind, "assignment_expression")) {
                // First child is typically the left-hand side
                if (parent.child(0)) |first_child| {
                    if (first_child.eql(node)) {
                        return .Write;
                    }
                }
            }
        }

        // Default to Read
        return .Read;
    }
};
