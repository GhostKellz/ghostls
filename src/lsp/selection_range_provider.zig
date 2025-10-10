const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Provides selection ranges for smart expand/shrink selections (Vim text objects)
pub const SelectionRangeProvider = struct {
    allocator: std.mem.Allocator,

    pub const SelectionRange = struct {
        range: protocol.Range,
        parent: ?*SelectionRange,

        pub fn deinit(self: *SelectionRange, allocator: std.mem.Allocator) void {
            if (self.parent) |parent| {
                parent.deinit(allocator);
                allocator.destroy(parent);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) SelectionRangeProvider {
        return .{ .allocator = allocator };
    }

    /// Get selection ranges for multiple positions
    pub fn getSelectionRanges(
        self: *SelectionRangeProvider,
        tree: *const grove.Tree,
        positions: []const protocol.Position,
    ) ![]SelectionRange {
        var ranges = std.ArrayList(SelectionRange).init(self.allocator);
        errdefer {
            for (ranges.items) |*range| {
                range.deinit(self.allocator);
            }
            ranges.deinit();
        }

        const root_opt = tree.rootNode();
        if (root_opt == null) return try ranges.toOwnedSlice();

        const root = root_opt.?;

        for (positions) |position| {
            if (try self.getSelectionRangeAt(root, position)) |range| {
                try ranges.append(range);
            }
        }

        return try ranges.toOwnedSlice();
    }

    /// Get selection range hierarchy for a single position
    fn getSelectionRangeAt(
        self: *SelectionRangeProvider,
        root: grove.Node,
        position: protocol.Position,
    ) !?SelectionRange {
        // Find all nodes containing the position, from innermost to outermost
        var nodes = std.ArrayList(grove.Node).init(self.allocator);
        defer nodes.deinit();

        try self.findContainingNodes(root, position, &nodes);

        if (nodes.items.len == 0) return null;

        // Build linked list of selection ranges from outermost to innermost
        var current_parent: ?*SelectionRange = null;

        // Iterate in reverse (outermost first)
        var i: usize = nodes.items.len;
        while (i > 0) {
            i -= 1;
            const node = nodes.items[i];
            const start_pos = node.startPosition();
            const end_pos = node.endPosition();

            const new_range = try self.allocator.create(SelectionRange);
            new_range.* = .{
                .range = .{
                    .start = .{ .line = start_pos.row, .character = start_pos.column },
                    .end = .{ .line = end_pos.row, .character = end_pos.column },
                },
                .parent = current_parent,
            };

            current_parent = new_range;
        }

        // Return the innermost range (which has all parents linked)
        if (current_parent) |range| {
            // Transfer ownership - create a copy that the caller will own
            const result = try self.allocator.create(SelectionRange);
            result.* = range.*;
            return result.*;
        }

        return null;
    }

    fn findContainingNodes(
        self: *SelectionRangeProvider,
        node: grove.Node,
        position: protocol.Position,
        nodes: *std.ArrayList(grove.Node),
    ) !void {
        const start_pos = node.startPosition();
        const end_pos = node.endPosition();

        if (!positionInRange(position, start_pos, end_pos)) {
            return;
        }

        // Add this node if it's meaningful for selection
        const kind = node.kind();
        if (self.isMeaningfulNode(kind)) {
            try nodes.append(node);
        }

        // Recursively check children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.findContainingNodes(child, position, nodes);
            }
        }
    }

    fn isMeaningfulNode(self: *SelectionRangeProvider, kind: []const u8) bool {
        _ = self;

        // Filter out noise nodes that don't make good selection targets
        const meaningful_kinds = [_][]const u8{
            "identifier",
            "number_literal",
            "string_literal",
            "expression",
            "call_expression",
            "member_expression",
            "variable_declaration",
            "function_declaration",
            "if_statement",
            "while_statement",
            "for_statement",
            "block_statement",
            "array_literal",
            "object_literal",
            "statement",
            "source_file",
        };

        for (meaningful_kinds) |mk| {
            if (std.mem.eql(u8, kind, mk)) return true;
        }

        return false;
    }

    pub fn freeRanges(self: *SelectionRangeProvider, ranges: []SelectionRange) void {
        for (ranges) |*range| {
            range.deinit(self.allocator);
        }
        self.allocator.free(ranges);
    }
};

fn positionInRange(pos: protocol.Position, start: grove.Point, end: grove.Point) bool {
    if (pos.line < start.row) return false;
    if (pos.line == start.row and pos.character < start.column) return false;
    if (pos.line > end.row) return false;
    if (pos.line == end.row and pos.character > end.column) return false;
    return true;
}
