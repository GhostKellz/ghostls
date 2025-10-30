const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// FoldingRangeProvider provides code folding ranges
/// Uses Grove's LSP helpers for efficient folding range extraction
pub const FoldingRangeProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FoldingRangeProvider {
        return .{ .allocator = allocator };
    }

    /// Get all folding ranges in the document
    pub fn getFoldingRanges(
        self: *FoldingRangeProvider,
        tree: *const grove.Tree,
        text: []const u8,
    ) ![]protocol.FoldingRange {
        const root_opt = tree.rootNode();
        if (root_opt == null) {
            return try self.allocator.alloc(protocol.FoldingRange, 0);
        }

        const root = root_opt.?;

        // Use Grove's LSP helper to extract folding ranges
        var grove_ranges = try grove.LSP.extractFoldingRanges(
            self.allocator,
            root,
            text,
        );
        defer grove_ranges.deinit(self.allocator);

        // Convert to LSP protocol format
        var ranges: std.ArrayList(protocol.FoldingRange) = .empty;
        errdefer ranges.deinit(self.allocator);

        for (grove_ranges.items) |grove_range| {
            // Convert Grove FoldingRange to protocol FoldingRange
            const lsp_kind: ?protocol.FoldingRangeKind = if (grove_range.kind) |k|
                groveFoldingKindToProtocol(k)
            else
                null;

            try ranges.append(self.allocator, .{
                .startLine = grove_range.start_line,
                .startCharacter = grove_range.start_character,
                .endLine = grove_range.end_line,
                .endCharacter = grove_range.end_character,
                .kind = lsp_kind,
            });
        }

        return try ranges.toOwnedSlice(self.allocator);
    }
};

/// Convert Grove FoldingRangeKind to protocol FoldingRangeKind
fn groveFoldingKindToProtocol(kind: grove.LSP.FoldingRangeKind) protocol.FoldingRangeKind {
    return switch (kind) {
        .comment => .comment,
        .imports => .imports,
        .region => .region,
    };
}
