const std = @import("std");
const protocol = @import("protocol.zig");
const grove = @import("grove");

/// ReferencesProvider finds all references to symbols
/// Now uses Grove's LSP helpers for simplified implementation
pub const ReferencesProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ReferencesProvider {
        return .{ .allocator = allocator };
    }

    /// Find all references to the symbol at the given position
    /// Uses Grove's findReferences helper (replaces ~150 lines of tree walking!)
    pub fn findReferences(
        self: *ReferencesProvider,
        tree: *grove.Tree,
        text: []const u8,
        uri: []const u8,
        position: protocol.Position,
        include_declaration: bool,
    ) ![]protocol.Location {
        const root = tree.rootNode() orelse {
            return try self.allocator.alloc(protocol.Location, 0);
        };

        // Use Grove's LSP helper to find node at position
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };

        const node_opt = grove.LSP.findNodeAtPosition(root, grove_pos);
        if (node_opt == null) {
            return try self.allocator.alloc(protocol.Location, 0);
        }

        const node = node_opt.?;
        const kind = node.kind();

        // Only handle identifiers
        if (!std.mem.eql(u8, kind, "identifier") and
            !std.mem.eql(u8, kind, "type_identifier")) {
            return try self.allocator.alloc(protocol.Location, 0);
        }

        // Get identifier text
        const start_byte = node.startByte();
        const end_byte = node.endByte();
        if (end_byte <= start_byte or end_byte > text.len) {
            return try self.allocator.alloc(protocol.Location, 0);
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

        // Filter by include_declaration flag and convert to protocol format
        var locations: std.ArrayList(protocol.Location) = .empty;
        errdefer {
            for (locations.items) |loc| {
                self.allocator.free(loc.uri);
            }
            locations.deinit(self.allocator);
        }

        for (grove_refs.items) |ref_node| {
            // Check if this is a declaration
            const is_decl = self.isDeclarationNode(ref_node);

            if (include_declaration or !is_decl) {
                const uri_copy = try self.allocator.dupe(u8, uri);
                errdefer self.allocator.free(uri_copy);

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

                try locations.append(self.allocator, .{
                    .uri = uri_copy,
                    .range = lsp_range,
                });
            }
        }

        return try locations.toOwnedSlice(self.allocator);
    }

    /// Check if a node is part of a declaration
    fn isDeclarationNode(self: *ReferencesProvider, node: grove.Node) bool {
        _ = self;

        // Check if parent is a declaration
        if (node.parent()) |parent| {
            const parent_kind = parent.kind();
            return std.mem.eql(u8, parent_kind, "variable_declaration") or
                   std.mem.eql(u8, parent_kind, "function_declaration") or
                   std.mem.eql(u8, parent_kind, "const_declaration") or
                   std.mem.eql(u8, parent_kind, "let_declaration") or
                   std.mem.eql(u8, parent_kind, "local_declaration") or
                   std.mem.eql(u8, parent_kind, "class_declaration") or
                   std.mem.eql(u8, parent_kind, "struct_declaration");
        }

        return false;
    }

    pub fn freeLocations(self: *ReferencesProvider, locations: []protocol.Location) void {
        for (locations) |loc| {
            self.allocator.free(loc.uri);
        }
        self.allocator.free(locations);
    }
};
