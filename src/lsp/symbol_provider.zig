const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// SymbolProvider collects document symbols for outline view
pub const SymbolProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolProvider {
        return .{ .allocator = allocator };
    }

    /// Get all document symbols
    pub fn getSymbols(
        self: *SymbolProvider,
        tree: *const grove.Tree,
        text: []const u8,
    ) ![]protocol.DocumentSymbol {
        const root_opt = tree.rootNode();
        if (root_opt == null) return &[_]protocol.DocumentSymbol{};

        const root = root_opt.?;

        var symbols: std.ArrayList(protocol.DocumentSymbol) = .empty;
        errdefer {
            for (symbols.items) |sym| {
                self.freeSymbol(sym);
            }
            symbols.deinit(self.allocator);
        }

        // Collect symbols from the tree
        try self.collectSymbols(root, text, &symbols);

        return try symbols.toOwnedSlice(self.allocator);
    }

    /// Free a symbol and its children
    pub fn freeSymbol(self: *SymbolProvider, symbol: protocol.DocumentSymbol) void {
        self.allocator.free(symbol.name);
        if (symbol.detail) |detail| {
            self.allocator.free(detail);
        }
        if (symbol.children) |children| {
            for (children) |child| {
                self.freeSymbol(child);
            }
            self.allocator.free(children);
        }
    }

    /// Collect symbols from a node and its children
    fn collectSymbols(
        self: *SymbolProvider,
        node: grove.Node,
        text: []const u8,
        symbols: *std.ArrayList(protocol.DocumentSymbol),
    ) !void {
        const kind_str = node.kind();

        // Check if this node represents a symbol
        const symbol_info = self.getSymbolInfo(kind_str);

        if (symbol_info) |info| {
            const name = try self.getSymbolName(node, text);
            const detail = try self.getSymbolDetail(node, text);

            var children: std.ArrayList(protocol.DocumentSymbol) = .empty;
            errdefer children.deinit(self.allocator);

            // Recursively collect children for container symbols
            const child_count = node.childCount();
            var i: u32 = 0;
            while (i < child_count) : (i += 1) {
                if (node.child(i)) |child| {
                    try self.collectSymbols(child, text, &children);
                }
            }

            const children_slice = if (children.items.len > 0)
                try children.toOwnedSlice(self.allocator)
            else
                null;

            try symbols.append(self.allocator, .{
                .name = name,
                .detail = detail,
                .kind = info.kind,
                .range = nodeToRange(node),
                .selectionRange = nodeToRange(node),
                .children = children_slice,
            });
        } else {
            // Not a symbol node, but check its children
            const child_count = node.childCount();
            var i: u32 = 0;
            while (i < child_count) : (i += 1) {
                if (node.child(i)) |child| {
                    try self.collectSymbols(child, text, symbols);
                }
            }
        }
    }

    const SymbolInfo = struct {
        kind: protocol.SymbolKind,
    };

    /// Get symbol info for a node kind
    fn getSymbolInfo(self: *SymbolProvider, kind: []const u8) ?SymbolInfo {
        _ = self;

        if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "function")) {
            return .{ .kind = .Function };
        } else if (std.mem.eql(u8, kind, "variable_declaration") or
                   std.mem.eql(u8, kind, "let_declaration")) {
            return .{ .kind = .Variable };
        } else if (std.mem.eql(u8, kind, "const_declaration")) {
            return .{ .kind = .Constant };
        } else if (std.mem.eql(u8, kind, "class_declaration") or
                   std.mem.eql(u8, kind, "class")) {
            return .{ .kind = .Class };
        } else if (std.mem.eql(u8, kind, "struct_declaration") or
                   std.mem.eql(u8, kind, "struct")) {
            return .{ .kind = .Struct };
        } else if (std.mem.eql(u8, kind, "enum_declaration") or
                   std.mem.eql(u8, kind, "enum")) {
            return .{ .kind = .Enum };
        } else if (std.mem.eql(u8, kind, "interface_declaration") or
                   std.mem.eql(u8, kind, "interface")) {
            return .{ .kind = .Interface };
        } else if (std.mem.eql(u8, kind, "method_declaration") or
                   std.mem.eql(u8, kind, "method")) {
            return .{ .kind = .Method };
        }

        return null;
    }

    /// Extract symbol name from node
    fn getSymbolName(self: *SymbolProvider, node: grove.Node, text: []const u8) ![]const u8 {
        // Try to find an identifier child
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
                        return try self.allocator.dupe(u8, text[start..end]);
                    }
                }
            }
        }

        // Fallback: use node text
        const start = node.startByte();
        const end = node.endByte();
        if (end > start and end <= text.len) {
            const node_text = text[start..end];
            // Truncate if too long
            const max_len = 50;
            const truncated = if (node_text.len > max_len)
                node_text[0..max_len]
            else
                node_text;
            return try self.allocator.dupe(u8, truncated);
        }

        return try self.allocator.dupe(u8, "<unnamed>");
    }

    /// Get symbol detail (type info, signature, etc.)
    fn getSymbolDetail(self: *SymbolProvider, node: grove.Node, text: []const u8) !?[]const u8 {
        _ = node;
        _ = text;
        _ = self;
        // TODO: Extract detailed type information
        return null;
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
