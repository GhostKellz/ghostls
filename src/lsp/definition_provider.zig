const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// DefinitionProvider finds symbol definitions (single-file and cross-file)
pub const DefinitionProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DefinitionProvider {
        return .{ .allocator = allocator };
    }

    /// Find the definition of a symbol at the given position (single file)
    pub fn findDefinition(
        self: *DefinitionProvider,
        tree: *const grove.Tree,
        text: []const u8,
        uri: []const u8,
        position: protocol.Position,
    ) !?protocol.Location {
        _ = self;

        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the node at the cursor position
        const node_opt = findNodeAtPosition(root, position);
        if (node_opt == null) return null;

        const node = node_opt.?;
        const kind = node.kind();

        // Only handle identifiers
        if (!std.mem.eql(u8, kind, "identifier") and
            !std.mem.eql(u8, kind, "type_identifier")) {
            return null;
        }

        // Get the identifier text
        const start_byte = node.startByte();
        const end_byte = node.endByte();
        if (end_byte <= start_byte or end_byte > text.len) return null;

        const identifier = text[start_byte..end_byte];

        // Search for the declaration of this identifier
        const def_node_opt = findDeclaration(root, identifier, text);
        if (def_node_opt == null) return null;

        const def_node = def_node_opt.?;

        return protocol.Location{
            .uri = uri,
            .range = nodeToRange(def_node),
        };
    }

    /// Find definition across multiple files (workspace-wide)
    pub fn findDefinitionCrossFile(
        self: *DefinitionProvider,
        trees: []const TreeWithUri,
        current_uri: []const u8,
        position: protocol.Position,
    ) !?protocol.Location {
        _ = self;

        // First, get the identifier at the current position
        var identifier: []const u8 = undefined;
        for (trees) |tree_info| {
            if (std.mem.eql(u8, tree_info.uri, current_uri)) {
                const root_opt = tree_info.tree.rootNode();
                if (root_opt == null) continue;

                const node_opt = findNodeAtPosition(root_opt.?, position);
                if (node_opt == null) continue;

                const node = node_opt.?;
                const kind = node.kind();

                if (!std.mem.eql(u8, kind, "identifier") and
                    !std.mem.eql(u8, kind, "type_identifier")) {
                    continue;
                }

                const start_byte = node.startByte();
                const end_byte = node.endByte();
                if (end_byte <= start_byte or end_byte > tree_info.text.len) continue;

                identifier = tree_info.text[start_byte..end_byte];
                break;
            }
        }

        if (identifier.len == 0) return null;

        // Search all files for the definition, starting with current file
        for (trees) |tree_info| {
            const root_opt = tree_info.tree.rootNode();
            if (root_opt == null) continue;

            if (findDeclaration(root_opt.?, identifier, tree_info.text)) |def_node| {
                return protocol.Location{
                    .uri = tree_info.uri,
                    .range = nodeToRange(def_node),
                };
            }
        }

        return null;
    }

    pub const TreeWithUri = struct {
        uri: []const u8,
        tree: *const grove.Tree,
        text: []const u8,
    };

    /// Find a declaration for the given identifier
    fn findDeclaration(
        node: grove.Node,
        identifier: []const u8,
        text: []const u8,
    ) ?grove.Node {
        const kind = node.kind();

        // Check if this is a declaration node
        if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "function") or
            std.mem.eql(u8, kind, "variable_declaration") or
            std.mem.eql(u8, kind, "let_declaration") or
            std.mem.eql(u8, kind, "const_declaration") or
            std.mem.eql(u8, kind, "class_declaration") or
            std.mem.eql(u8, kind, "struct_declaration")) {

            // Look for an identifier child that matches
            const child_count = node.childCount();
            var i: u32 = 0;
            while (i < child_count) : (i += 1) {
                if (node.child(i)) |child| {
                    const child_kind = child.kind();
                    if (std.mem.eql(u8, child_kind, "identifier") or
                        std.mem.eql(u8, child_kind, "type_identifier")) {

                        const start = child.startByte();
                        const end = child.endByte();
                        if (end > start and end <= text.len) {
                            const child_text = text[start..end];
                            if (std.mem.eql(u8, child_text, identifier)) {
                                return node;
                            }
                        }
                    }
                }
            }
        }

        // Recursively search children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                if (findDeclaration(child, identifier, text)) |found| {
                    return found;
                }
            }
        }

        return null;
    }
};

/// Find the smallest node that contains the position
fn findNodeAtPosition(
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
                if (findNodeAtPosition(child, position)) |found| {
                    return found;
                }
                return child;
            }
        }
    }

    // No child matched, return this node
    return node;
}

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
