const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Provides rename symbol functionality (workspace-wide)
pub const RenameProvider = struct {
    allocator: std.mem.Allocator,

    pub const WorkspaceEdit = struct {
        changes: std.StringHashMap([]TextEdit),

        pub fn deinit(self: *WorkspaceEdit, allocator: std.mem.Allocator) void {
            var it = self.changes.iterator();
            while (it.next()) |entry| {
                for (entry.value_ptr.*) |*edit| {
                    allocator.free(edit.new_text);
                }
                allocator.free(entry.value_ptr.*);
                allocator.free(entry.key_ptr.*);
            }
            self.changes.deinit();
        }
    };

    pub const TextEdit = struct {
        range: protocol.Range,
        new_text: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) RenameProvider {
        return .{ .allocator = allocator };
    }

    /// Prepare rename (check if rename is valid at position)
    pub fn prepareRename(
        self: *RenameProvider,
        tree: *const grove.Tree,
        text: []const u8,
        position: protocol.Position,
    ) !?protocol.Range {
        _ = self;
        _ = text;

        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the node at the cursor position
        const node_opt = findNodeAtPosition(root, position);
        if (node_opt == null) return null;

        const node = node_opt.?;
        const kind = node.kind();

        // Only allow renaming identifiers
        if (!std.mem.eql(u8, kind, "identifier") and
            !std.mem.eql(u8, kind, "type_identifier")) {
            return null;
        }

        // Return the range of the identifier
        const start_pos = node.startPosition();
        const end_pos = node.endPosition();

        return protocol.Range{
            .start = .{ .line = start_pos.row, .character = start_pos.column },
            .end = .{ .line = end_pos.row, .character = end_pos.column },
        };
    }

    /// Perform rename (single file)
    pub fn rename(
        self: *RenameProvider,
        tree: *const grove.Tree,
        text: []const u8,
        uri: []const u8,
        position: protocol.Position,
        new_name: []const u8,
    ) !?WorkspaceEdit {
        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the identifier to rename
        const node_opt = findNodeAtPosition(root, position);
        if (node_opt == null) return null;

        const node = node_opt.?;
        const kind = node.kind();

        if (!std.mem.eql(u8, kind, "identifier") and
            !std.mem.eql(u8, kind, "type_identifier")) {
            return null;
        }

        const start_byte = node.startByte();
        const end_byte = node.endByte();
        if (end_byte <= start_byte or end_byte > text.len) return null;

        const old_name = text[start_byte..end_byte];

        // Find all occurrences of this identifier
        var edits = std.ArrayList(TextEdit).init(self.allocator);
        defer edits.deinit();

        try self.findAllOccurrences(root, text, old_name, new_name, &edits);

        if (edits.items.len == 0) return null;

        var changes = std.StringHashMap([]TextEdit).init(self.allocator);
        const uri_copy = try self.allocator.dupe(u8, uri);
        try changes.put(uri_copy, try edits.toOwnedSlice());

        return WorkspaceEdit{ .changes = changes };
    }

    fn findAllOccurrences(
        self: *RenameProvider,
        node: grove.Node,
        text: []const u8,
        old_name: []const u8,
        new_name: []const u8,
        edits: *std.ArrayList(TextEdit),
    ) !void {
        const kind = node.kind();

        if (std.mem.eql(u8, kind, "identifier") or
            std.mem.eql(u8, kind, "type_identifier")) {

            const start_byte = node.startByte();
            const end_byte = node.endByte();

            if (end_byte > start_byte and end_byte <= text.len) {
                const identifier = text[start_byte..end_byte];
                if (std.mem.eql(u8, identifier, old_name)) {
                    const start_pos = node.startPosition();
                    const end_pos = node.endPosition();

                    const new_text = try self.allocator.dupe(u8, new_name);

                    try edits.append(.{
                        .range = .{
                            .start = .{ .line = start_pos.row, .character = start_pos.column },
                            .end = .{ .line = end_pos.row, .character = end_pos.column },
                        },
                        .new_text = new_text,
                    });
                }
            }
        }

        // Recursively check children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try self.findAllOccurrences(child, text, old_name, new_name, edits);
            }
        }
    }

    pub fn freeWorkspaceEdit(self: *RenameProvider, edit: *WorkspaceEdit) void {
        edit.deinit(self.allocator);
    }
};

/// Find the smallest node that contains the position
fn findNodeAtPosition(
    node: grove.Node,
    position: protocol.Position,
) ?grove.Node {
    const start_pos = node.startPosition();
    const end_pos = node.endPosition();

    // Check if position is within this node's range
    if (!positionInRange(position, start_pos, end_pos)) {
        return null;
    }

    // Check children for a more specific match
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_start = child.startPosition();
            const child_end = child.endPosition();

            if (positionInRange(position, child_start, child_end)) {
                if (findNodeAtPosition(child, position)) |found| {
                    return found;
                }
                return child;
            }
        }
    }

    return node;
}

fn positionInRange(
    pos: protocol.Position,
    start: grove.Point,
    end: grove.Point,
) bool {
    if (pos.line < start.row) return false;
    if (pos.line == start.row and pos.character < start.column) return false;
    if (pos.line > end.row) return false;
    if (pos.line == end.row and pos.character > end.column) return false;
    return true;
}
