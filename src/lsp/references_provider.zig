const std = @import("std");
const protocol = @import("protocol.zig");
const grove = @import("grove");

pub const ReferencesProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ReferencesProvider {
        return .{ .allocator = allocator };
    }

    /// Find all references to the symbol at the given position
    pub fn findReferences(
        self: *ReferencesProvider,
        tree: *grove.Tree,
        text: []const u8,
        uri: []const u8,
        position: protocol.Position,
        include_declaration: bool,
    ) ![]protocol.Location {
        // Get the node at cursor position using Grove Point API
        const root = tree.rootNode() orelse {
            return try self.allocator.alloc(protocol.Location, 0);
        };
        const grove_point = grove.Point{ .row = position.line, .column = position.character };
        const node = root.descendantForPointRange(grove_point, grove_point) orelse {
            return try self.allocator.alloc(protocol.Location, 0);
        };

        // Get the symbol name at cursor
        const symbol_name = try self.getSymbolName(node, text);
        if (symbol_name.len == 0) {
            return try self.allocator.alloc(protocol.Location, 0);
        }
        defer self.allocator.free(symbol_name);

        // Find all references to this symbol in the document
        var locations: std.ArrayList(protocol.Location) = .empty;
        errdefer locations.deinit(self.allocator);

        try self.findSymbolReferences(
            tree,
            text,
            symbol_name,
            uri,
            &locations,
            include_declaration,
        );

        return try locations.toOwnedSlice(self.allocator);
    }

    fn getSymbolName(self: *ReferencesProvider, node: grove.Node, text: []const u8) ![]const u8 {
        const node_type = node.kind();

        // Check if this is an identifier
        if (std.mem.eql(u8, node_type, "identifier")) {
            const start = node.startByte();
            const end = node.endByte();
            if (end <= text.len) {
                return try self.allocator.dupe(u8, text[start..end]);
            }
        }

        // Check if parent is an identifier
        if (node.parent()) |parent| {
            if (std.mem.eql(u8, parent.kind(), "identifier")) {
                const start = parent.startByte();
                const end = parent.endByte();
                if (end <= text.len) {
                    return try self.allocator.dupe(u8, text[start..end]);
                }
            }
        }

        return try self.allocator.alloc(u8, 0);
    }

    fn findSymbolReferences(
        self: *ReferencesProvider,
        tree: *grove.Tree,
        text: []const u8,
        symbol_name: []const u8,
        uri: []const u8,
        locations: *std.ArrayList(protocol.Location),
        include_declaration: bool,
    ) !void {
        const root = tree.rootNode() orelse return;

        // Walk the entire tree looking for identifiers matching the symbol name
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        try self.walkTreeForReferences(
            &cursor,
            text,
            symbol_name,
            uri,
            locations,
            include_declaration,
        );
    }

    fn walkTreeForReferences(
        self: *ReferencesProvider,
        cursor: *grove.TreeCursor,
        text: []const u8,
        symbol_name: []const u8,
        uri: []const u8,
        locations: *std.ArrayList(protocol.Location),
        include_declaration: bool,
    ) !void {
        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Check if this is an identifier
                if (std.mem.eql(u8, node_type, "identifier")) {
                    const start = node.startByte();
                    const end = node.endByte();

                    if (end <= text.len) {
                        const name = text[start..end];
                        if (std.mem.eql(u8, name, symbol_name)) {
                            // Check if this is a declaration (if we should exclude it)
                            const is_declaration = try self.isDeclaration(node);

                            if (include_declaration or !is_declaration) {
                                // Convert byte range to LSP Range
                                const range = try byteRangeToRange(text, start, end);

                                try locations.append(self.allocator, .{
                                    .uri = try self.allocator.dupe(u8, uri),
                                    .range = range,
                                });
                            }
                        }
                    }
                }

                // Recursively search child nodes
                try self.walkTreeForReferences(
                    cursor,
                    text,
                    symbol_name,
                    uri,
                    locations,
                    include_declaration,
                );

                if (!cursor.gotoNextSibling()) break;
            }
            _ = cursor.gotoParent();
        }
    }

    fn isDeclaration(self: *ReferencesProvider, node: grove.Node) !bool {
        _ = self;

        // Check if parent is a variable/function declaration
        if (node.parent()) |parent| {
            const parent_type = parent.kind();
            return std.mem.eql(u8, parent_type, "variable_declaration") or
                   std.mem.eql(u8, parent_type, "function_declaration") or
                   std.mem.eql(u8, parent_type, "local_declaration");
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

fn byteRangeToRange(text: []const u8, start_byte: usize, end_byte: usize) !protocol.Range {
    var line: u32 = 0;
    var character: u32 = 0;
    var start_line: u32 = 0;
    var start_character: u32 = 0;
    var found_start = false;

    for (text, 0..) |byte, i| {
        if (i == start_byte) {
            start_line = line;
            start_character = character;
            found_start = true;
        }

        if (i == end_byte and found_start) {
            return .{
                .start = .{ .line = start_line, .character = start_character },
                .end = .{ .line = line, .character = character },
            };
        }

        if (byte == '\n') {
            line += 1;
            character = 0;
        } else {
            character += 1;
        }
    }

    // Fallback
    return .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 0 },
    };
}
