const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Provides semantic tokens for enhanced syntax highlighting
/// Uses Grove's LSP helpers with full modifier support
pub const SemanticTokensProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SemanticTokensProvider {
        return .{ .allocator = allocator };
    }

    /// Get semantic tokens for a document
    /// Uses Grove's extractSemanticTokens helper with automatic modifiers
    pub fn getSemanticTokens(
        self: *SemanticTokensProvider,
        tree: *const grove.Tree,
        text: []const u8,
    ) ![]SemanticToken {
        const root_opt = tree.rootNode();
        if (root_opt == null) {
            return try self.allocator.alloc(SemanticToken, 0);
        }

        const root = root_opt.?;

        // Use Grove's LSP helper to extract semantic tokens with modifiers
        var grove_tokens = try grove.LSP.extractSemanticTokens(
            self.allocator,
            root,
            text,
            null, // Use default token type mapper
        );
        defer grove_tokens.deinit(self.allocator);

        // Convert Grove tokens to our protocol format
        var tokens: std.ArrayList(SemanticToken) = .empty;
        errdefer tokens.deinit(self.allocator);

        for (grove_tokens.items) |grove_token| {
            try tokens.append(self.allocator, .{
                .line = grove_token.line,
                .start_char = grove_token.start_char,
                .length = grove_token.length,
                .token_type = @intFromEnum(grove_token.token_type),
                .token_modifiers = grove_token.modifiers, // Bitmask of modifiers
            });
        }

        return try tokens.toOwnedSlice(self.allocator);
    }

    pub fn freeTokens(self: *SemanticTokensProvider, tokens: []SemanticToken) void {
        self.allocator.free(tokens);
    }
};

/// Semantic token structure for LSP protocol
pub const SemanticToken = struct {
    line: u32,
    start_char: u32,
    length: u32,
    token_type: u32,
    token_modifiers: u32, // Bitmask of SemanticTokenModifier flags
};
