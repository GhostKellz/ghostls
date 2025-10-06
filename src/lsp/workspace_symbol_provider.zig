const std = @import("std");
const protocol = @import("protocol.zig");
const grove = @import("grove");

pub const WorkspaceSymbolProvider = struct {
    allocator: std.mem.Allocator,
    symbol_index: std.StringHashMap(std.ArrayList(protocol.SymbolInformation)),

    pub fn init(allocator: std.mem.Allocator) WorkspaceSymbolProvider {
        return .{
            .allocator = allocator,
            .symbol_index = std.StringHashMap(std.ArrayList(protocol.SymbolInformation)).init(allocator),
        };
    }

    pub fn deinit(self: *WorkspaceSymbolProvider) void {
        var it = self.symbol_index.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.symbol_index.deinit();
    }

    /// Index symbols from a document
    pub fn indexDocument(
        self: *WorkspaceSymbolProvider,
        uri: []const u8,
        tree: *grove.Tree,
        text: []const u8,
    ) !void {
        // Clear existing symbols for this document
        if (self.symbol_index.fetchRemove(uri)) |kv| {
            var mutable_existing = kv.value;
            mutable_existing.deinit(self.allocator);
            self.allocator.free(kv.key);
        }

        var symbols: std.ArrayList(protocol.SymbolInformation) = .empty;
        errdefer symbols.deinit(self.allocator);

        // Extract symbols from tree
        const root = tree.rootNode() orelse return;
        try self.extractSymbols(root, text, uri, &symbols);

        // Store in index
        try self.symbol_index.put(try self.allocator.dupe(u8, uri), symbols);
    }

    /// Search workspace symbols with fuzzy matching
    pub fn search(
        self: *WorkspaceSymbolProvider,
        query: []const u8,
    ) ![]protocol.SymbolInformation {
        var results: std.ArrayList(protocol.SymbolInformation) = .empty;
        errdefer results.deinit(self.allocator);

        // Search through all indexed symbols
        var it = self.symbol_index.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |symbol| {
                // Fuzzy match against query
                if (try self.fuzzyMatch(symbol.name, query)) {
                    try results.append(self.allocator, .{
                        .name = try self.allocator.dupe(u8, symbol.name),
                        .kind = symbol.kind,
                        .location = .{
                            .uri = try self.allocator.dupe(u8, symbol.location.uri),
                            .range = symbol.location.range,
                        },
                        .containerName = if (symbol.containerName) |name|
                            try self.allocator.dupe(u8, name)
                        else
                            null,
                    });
                }
            }
        }

        return try results.toOwnedSlice(self.allocator);
    }

    fn extractSymbols(
        self: *WorkspaceSymbolProvider,
        node: grove.Node,
        text: []const u8,
        uri: []const u8,
        symbols: *std.ArrayList(protocol.SymbolInformation),
    ) !void {
        var cursor = try node.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const current = cursor.currentNode();
                const node_type = current.kind();

                // Extract function declarations
                if (std.mem.eql(u8, node_type, "function_declaration") or
                    std.mem.eql(u8, node_type, "function_definition"))
                {
                    if (current.childByFieldName("name")) |name_node| {
                        try self.addSymbol(
                            name_node,
                            text,
                            uri,
                            .Function,
                            null,
                            symbols,
                        );
                    }
                }
                // Extract variable declarations
                else if (std.mem.eql(u8, node_type, "variable_declaration") or
                         std.mem.eql(u8, node_type, "local_declaration"))
                {
                    if (current.childByFieldName("name")) |name_node| {
                        try self.addSymbol(
                            name_node,
                            text,
                            uri,
                            .Variable,
                            null,
                            symbols,
                        );
                    }
                }
                // Extract class declarations (if supported)
                else if (std.mem.eql(u8, node_type, "class_declaration")) {
                    if (current.childByFieldName("name")) |name_node| {
                        try self.addSymbol(
                            name_node,
                            text,
                            uri,
                            .Class,
                            null,
                            symbols,
                        );
                    }
                }

                // Recurse into children
                try self.extractSymbols(current, text, uri, symbols);

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    fn addSymbol(
        self: *WorkspaceSymbolProvider,
        name_node: grove.Node,
        text: []const u8,
        uri: []const u8,
        kind: protocol.SymbolKind,
        container_name: ?[]const u8,
        symbols: *std.ArrayList(protocol.SymbolInformation),
    ) !void {
        const start = name_node.startByte();
        const end = name_node.endByte();

        if (end > text.len) return;

        const name = text[start..end];
        const range = try byteRangeToRange(text, start, end);

        try symbols.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .kind = kind,
            .location = .{
                .uri = try self.allocator.dupe(u8, uri),
                .range = range,
            },
            .containerName = if (container_name) |cn|
                try self.allocator.dupe(u8, cn)
            else
                null,
        });
    }

    fn fuzzyMatch(self: *WorkspaceSymbolProvider, text: []const u8, query: []const u8) !bool {
        _ = self;

        if (query.len == 0) return true;
        if (text.len == 0) return false;

        // Simple fuzzy matching: check if all query characters appear in order
        var query_idx: usize = 0;
        var text_idx: usize = 0;

        while (text_idx < text.len and query_idx < query.len) {
            const text_char = std.ascii.toLower(text[text_idx]);
            const query_char = std.ascii.toLower(query[query_idx]);

            if (text_char == query_char) {
                query_idx += 1;
            }
            text_idx += 1;
        }

        return query_idx == query.len;
    }

    pub fn freeSymbols(self: *WorkspaceSymbolProvider, symbols: []protocol.SymbolInformation) void {
        for (symbols) |symbol| {
            self.allocator.free(symbol.name);
            self.allocator.free(symbol.location.uri);
            if (symbol.containerName) |name| {
                self.allocator.free(name);
            }
        }
        self.allocator.free(symbols);
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

    return .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 0 },
    };
}
