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

        // Find the node at the cursor position using Grove's LSP helper
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };
        const node_opt = grove.LSP.findNodeAtPosition(root, grove_pos);
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

    /// Perform rename (workspace-wide across all open documents)
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

        // Find the identifier to rename in the current document using Grove's LSP helper
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };
        const node_opt = grove.LSP.findNodeAtPosition(root, grove_pos);
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

        // Find all occurrences in the current file
        var edits: std.ArrayList(TextEdit) = .empty;
        defer edits.deinit(self.allocator);

        try self.findAllOccurrences(root, text, old_name, new_name, &edits);

        if (edits.items.len == 0) return null;

        var changes = std.StringHashMap([]TextEdit).init(self.allocator);
        const uri_copy = try self.allocator.dupe(u8, uri);
        try changes.put(uri_copy, try edits.toOwnedSlice(self.allocator));

        return WorkspaceEdit{ .changes = changes };
    }

    /// Perform rename across multiple documents (workspace-wide)
    /// Takes a document manager to search all open documents
    pub fn renameWorkspace(
        self: *RenameProvider,
        document_manager: anytype,
        uri: []const u8,
        position: protocol.Position,
        new_name: []const u8,
    ) !?WorkspaceEdit {
        // Get the current document
        const doc = document_manager.get(uri) orelse return null;
        const tree = &(doc.tree orelse return null);
        const text = doc.text;

        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the identifier to rename in the current document using Grove's LSP helper
        const grove_pos = grove.LSP.Position{
            .line = position.line,
            .character = position.character,
        };
        const node_opt = grove.LSP.findNodeAtPosition(root, grove_pos);
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

        // Create workspace edit with changes for all documents
        var changes = std.StringHashMap([]TextEdit).init(self.allocator);
        errdefer {
            var it = changes.iterator();
            while (it.next()) |entry| {
                for (entry.value_ptr.*) |edit| {
                    self.allocator.free(edit.new_text);
                }
                self.allocator.free(entry.value_ptr.*);
                self.allocator.free(entry.key_ptr.*);
            }
            changes.deinit();
        }

        // Search all open documents
        var doc_it = document_manager.documents.iterator();
        while (doc_it.next()) |entry| {
            const doc_uri = entry.key_ptr.*;
            const document = entry.value_ptr.*;

            const doc_tree = &(document.tree orelse continue);
            const doc_text = document.text;

            const doc_root_opt = doc_tree.rootNode();
            if (doc_root_opt == null) continue;

            const doc_root = doc_root_opt.?;

            // Find all occurrences in this document
            var doc_edits: std.ArrayList(TextEdit) = .empty;
            errdefer {
                for (doc_edits.items) |edit| {
                    self.allocator.free(edit.new_text);
                }
                doc_edits.deinit(self.allocator);
            }

            try self.findAllOccurrences(doc_root, doc_text, old_name, new_name, &doc_edits);

            // Only add to changes if we found occurrences
            if (doc_edits.items.len > 0) {
                const uri_copy = try self.allocator.dupe(u8, doc_uri);
                errdefer self.allocator.free(uri_copy);

                const edits_slice = try doc_edits.toOwnedSlice(self.allocator);
                try changes.put(uri_copy, edits_slice);
            }
        }

        if (changes.count() == 0) return null;

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

                    try edits.append(self.allocator, .{
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
