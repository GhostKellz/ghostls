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

        // Use Grove's LSP helper to find node at position
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };

        const node_opt = grove.LSP.findNodeAtPosition(root, grove_pos);
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

        // Use Grove's LSP helper to find definition (replaces ~50 lines!)
        const def_node_opt = grove.LSP.findDefinition(root, identifier, text);
        if (def_node_opt == null) return null;

        const def_node = def_node_opt.?;

        // Use Grove's helper to convert node to range
        const grove_range = grove.LSP.nodeToRange(def_node);
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

        return protocol.Location{
            .uri = uri,
            .range = lsp_range,
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

        // Convert position to Grove format
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };

        // First, get the identifier at the current position using Grove helper
        var identifier: []const u8 = undefined;
        for (trees) |tree_info| {
            if (std.mem.eql(u8, tree_info.uri, current_uri)) {
                const root_opt = tree_info.tree.rootNode();
                if (root_opt == null) continue;

                const node_opt = grove.LSP.findNodeAtPosition(root_opt.?, grove_pos);
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

        // Search all files for the definition using Grove's helper
        for (trees) |tree_info| {
            const root_opt = tree_info.tree.rootNode();
            if (root_opt == null) continue;

            if (grove.LSP.findDefinition(root_opt.?, identifier, tree_info.text)) |def_node| {
                const grove_range = grove.LSP.nodeToRange(def_node);
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

                return protocol.Location{
                    .uri = tree_info.uri,
                    .range = lsp_range,
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
};
