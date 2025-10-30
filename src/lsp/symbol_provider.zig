const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// SymbolProvider collects document symbols for outline view
/// Now uses Grove's LSP helpers for simplified implementation
pub const SymbolProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolProvider {
        return .{ .allocator = allocator };
    }

    /// Get all document symbols using Grove's extractSymbols helper
    pub fn getSymbols(
        self: *SymbolProvider,
        tree: *const grove.Tree,
        text: []const u8,
    ) ![]protocol.DocumentSymbol {
        const root_opt = tree.rootNode();
        if (root_opt == null) return &[_]protocol.DocumentSymbol{};

        const root = root_opt.?;

        // Use Grove's LSP helper to extract symbols (replaces ~100 lines of code!)
        var grove_symbols = try grove.LSP.extractSymbols(
            self.allocator,
            root,
            text,
            null, // Use default node_kind_map
        );
        defer {
            for (grove_symbols.items) |*sym| {
                sym.deinit(self.allocator);
            }
            grove_symbols.deinit(self.allocator);
        }

        // Convert Grove symbols to protocol symbols
        return try self.convertToProtocolSymbols(grove_symbols.items);
    }

    /// Convert Grove SymbolInfo to protocol DocumentSymbol
    fn convertToProtocolSymbols(self: *SymbolProvider, grove_symbols: []const grove.LSP.SymbolInfo) ![]protocol.DocumentSymbol {
        var symbols = try std.ArrayList(protocol.DocumentSymbol).initCapacity(self.allocator, grove_symbols.len);
        errdefer {
            for (symbols.items) |sym| {
                self.freeSymbol(sym);
            }
            symbols.deinit(self.allocator);
        }

        for (grove_symbols) |grove_sym| {
            const name = try self.allocator.dupe(u8, grove_sym.name);
            errdefer self.allocator.free(name);

            // Convert children recursively (Grove SymbolInfo.children is ArrayList, not optional)
            const children = if (grove_sym.children.items.len > 0)
                try self.convertToProtocolSymbols(grove_sym.children.items)
            else
                null;
            errdefer if (children) |ch| {
                for (ch) |child| {
                    self.freeSymbol(child);
                }
                self.allocator.free(ch);
            };

            try symbols.append(self.allocator, .{
                .name = name,
                .detail = null, // Grove doesn't provide details, could extract from node text later
                .kind = groveSymbolKindToProtocol(grove_sym.kind),
                .range = groveRangeToProtocol(grove_sym.range),
                .selectionRange = groveRangeToProtocol(grove_sym.selection_range),
                .children = children,
            });
        }

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
};

/// Convert Grove SymbolKind to protocol SymbolKind
fn groveSymbolKindToProtocol(kind: grove.LSP.SymbolKind) protocol.SymbolKind {
    return switch (kind) {
        .file => .File,
        .module => .Module,
        .namespace => .Namespace,
        .package => .Package,
        .class => .Class,
        .method => .Method,
        .property => .Property,
        .field => .Field,
        .constructor => .Constructor,
        .@"enum" => .Enum,
        .interface => .Interface,
        .function => .Function,
        .variable => .Variable,
        .constant => .Constant,
        .string => .String,
        .number => .Number,
        .boolean => .Boolean,
        .array => .Array,
        .object => .Object,
        .key => .Key,
        .null => .Null,
        .enum_member => .EnumMember,
        .@"struct" => .Struct,
        .event => .Event,
        .operator => .Operator,
        .type_parameter => .TypeParameter,
    };
}

/// Convert Grove Range to protocol Range
fn groveRangeToProtocol(range: grove.LSP.Range) protocol.Range {
    return .{
        .start = .{
            .line = range.start.line,
            .character = range.start.character,
        },
        .end = .{
            .line = range.end.line,
            .character = range.end.character,
        },
    };
}
