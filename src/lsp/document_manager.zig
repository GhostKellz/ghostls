const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Manages open documents and their parse trees
pub const DocumentManager = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(Document),
    parser: grove.Parser,

    pub const Document = struct {
        uri: []const u8,
        version: i32,
        text: []const u8,
        tree: ?grove.Tree,

        pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
            allocator.free(self.uri);
            allocator.free(self.text);
            if (self.tree) |*tree| {
                tree.deinit();
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) !DocumentManager {
        // Initialize parser with Ghostlang grammar
        const ghostlang_language = try grove.Languages.ghostlang.get();
        var parser = try grove.Parser.init(allocator);
        try parser.setLanguage(ghostlang_language);

        return .{
            .allocator = allocator,
            .documents = std.StringHashMap(Document).init(allocator),
            .parser = parser,
        };
    }

    pub fn deinit(self: *DocumentManager) void {
        var it = self.documents.valueIterator();
        while (it.next()) |doc| {
            doc.deinit(self.allocator);
        }
        self.documents.deinit();
        self.parser.deinit();
    }

    /// Open a document and parse it
    pub fn open(self: *DocumentManager, uri: []const u8, text: []const u8, version: i32) !void {
        // Parse the document
        const tree = try self.parser.parseUtf8(null, text);

        const doc = Document{
            .uri = try self.allocator.dupe(u8, uri),
            .version = version,
            .text = try self.allocator.dupe(u8, text),
            .tree = tree,
        };

        try self.documents.put(doc.uri, doc);
    }

    /// Update a document with new text (full sync for MVP)
    pub fn update(self: *DocumentManager, uri: []const u8, text: []const u8, version: i32) !void {
        var doc = self.documents.getPtr(uri) orelse return error.DocumentNotFound;

        // Free old text
        self.allocator.free(doc.text);

        // Parse new text
        if (doc.tree) |*old_tree| {
            old_tree.deinit();
        }

        const new_tree = try self.parser.parseUtf8(null, text);

        // Update document
        doc.text = try self.allocator.dupe(u8, text);
        doc.version = version;
        doc.tree = new_tree;
    }

    /// Close a document
    pub fn close(self: *DocumentManager, uri: []const u8) void {
        if (self.documents.fetchRemove(uri)) |kv| {
            var doc = kv.value;
            doc.deinit(self.allocator);
        }
    }

    /// Get a document by URI
    pub fn get(self: *DocumentManager, uri: []const u8) ?*Document {
        return self.documents.getPtr(uri);
    }
};
