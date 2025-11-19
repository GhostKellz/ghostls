const std = @import("std");
const protocol = @import("protocol.zig");

/// Provides completion items for kalix smart contracts
pub const KalixCompletionProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) KalixCompletionProvider {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *KalixCompletionProvider) void {
        // No resources to clean up
    }

    /// Get completion items for kalix
    pub fn complete(self: *KalixCompletionProvider) ![]const CompletionItem {
        var items: std.ArrayList(CompletionItem) = .{};
        errdefer items.deinit(self.allocator);

        // Kalix keywords
        try items.append(self.allocator, .{ .label = "contract", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "state", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "table", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "event", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "fn", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "pub", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "view", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "payable", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "let", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "mut", .kind = .Keyword });
        try items.append(self.allocator, .{ .label = "return", .kind = .Keyword });

        // Kalix types
        try items.append(self.allocator, .{ .label = "u8", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "u16", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "u32", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "u64", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "u128", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "u256", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "Address", .kind = .TypeParameter });
        try items.append(self.allocator, .{ .label = "Map", .kind = .TypeParameter });

        return try items.toOwnedSlice(self.allocator);
    }

    pub fn freeCompletions(self: *KalixCompletionProvider, items: []const CompletionItem) void {
        self.allocator.free(items);
    }
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind,
};

pub const CompletionItemKind = enum {
    Keyword,
    TypeParameter,
    Function,
    Variable,
};
