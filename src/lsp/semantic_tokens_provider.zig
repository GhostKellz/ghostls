const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Provides semantic tokens for enhanced syntax highlighting
pub const SemanticTokensProvider = struct {
    allocator: std.mem.Allocator,

    // LSP Semantic Token Types (standardized)
    pub const TokenType = enum(u32) {
        namespace = 0,
        type = 1,
        class = 2,
        enum_member = 3,
        interface = 4,
        struct_member = 5,
        type_parameter = 6,
        parameter = 7,
        variable = 8,
        property = 9,
        enum_member_member = 10,
        function = 11,
        method = 12,
        macro = 13,
        keyword = 14,
        modifier = 15,
        comment = 16,
        string = 17,
        number = 18,
        regexp = 19,
        operator = 20,
    };

    pub const TokenModifier = enum(u32) {
        declaration = 0,
        definition = 1,
        readonly = 2,
        static = 3,
        deprecated = 4,
        abstract = 5,
        async = 6,
        modification = 7,
        documentation = 8,
        default_library = 9,
    };

    pub fn init(allocator: std.mem.Allocator) SemanticTokensProvider {
        return .{ .allocator = allocator };
    }

    /// Get semantic tokens for a document
    pub fn getSemanticTokens(
        self: *SemanticTokensProvider,
        tree: *const grove.Tree,
        text: []const u8,
    ) ![]SemanticToken {
        var tokens = std.ArrayList(SemanticToken).init(self.allocator);
        errdefer tokens.deinit();

        const root_opt = tree.rootNode();
        if (root_opt == null) return try tokens.toOwnedSlice();

        const root = root_opt.?;

        // Walk the tree and collect semantic tokens
        try self.visitNode(root, text, &tokens);

        // Sort tokens by position (line, then character)
        std.mem.sort(SemanticToken, tokens.items, {}, struct {
            pub fn lessThan(_: void, a: SemanticToken, b: SemanticToken) bool {
                if (a.line != b.line) return a.line < b.line;
                return a.start_char < b.start_char;
            }
        }.lessThan);

        return try tokens.toOwnedSlice();
    }

    fn visitNode(
        self: *SemanticTokensProvider,
        node: grove.Node,
        text: []const u8,
        tokens: *std.ArrayList(SemanticToken),
    ) !void {
        const kind = node.kind();

        // Map tree-sitter nodes to semantic token types
        const token_type: ?TokenType = blk: {
            if (std.mem.eql(u8, kind, "function_declaration") or
                std.mem.eql(u8, kind, "function")) {
                break :blk .function;
            } else if (std.mem.eql(u8, kind, "variable_declaration")) {
                break :blk .variable;
            } else if (std.mem.eql(u8, kind, "identifier")) {
                // Context-dependent: check parent
                break :blk null; // Will determine from context
            } else if (std.mem.eql(u8, kind, "number_literal")) {
                break :blk .number;
            } else if (std.mem.eql(u8, kind, "string_literal")) {
                break :blk .string;
            } else if (std.mem.eql(u8, kind, "comment")) {
                break :blk .comment;
            } else if (std.mem.eql(u8, kind, "class_declaration")) {
                break :blk .class;
            } else if (isKeyword(kind)) {
                break :blk .keyword;
            }
            break :blk null;
        };

        if (token_type) |tt| {
            const start_pos = node.startPosition();
            const start_byte = node.startByte();
            const end_byte = node.endByte();

            if (end_byte > start_byte and end_byte <= text.len) {
                const length = end_byte - start_byte;

                try tokens.append(.{
                    .line = start_pos.row,
                    .start_char = start_pos.column,
                    .length = @intCast(length),
                    .token_type = @intFromEnum(tt),
                    .token_modifiers = 0,
                });
            }
        }

        // Recursively visit children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.visitNode(child, text, tokens);
            }
        }
    }

    fn isKeyword(kind: []const u8) bool {
        const keywords = [_][]const u8{
            "var", "function", "if", "else", "while", "for",
            "return", "break", "continue", "null", "true", "false",
            "class", "new", "this", "in",
        };

        for (keywords) |kw| {
            if (std.mem.eql(u8, kind, kw)) return true;
        }
        return false;
    }

    pub fn freeTokens(self: *SemanticTokensProvider, tokens: []SemanticToken) void {
        self.allocator.free(tokens);
    }
};

pub const SemanticToken = struct {
    line: u32,
    start_char: u32,
    length: u32,
    token_type: u32,
    token_modifiers: u32,
};
