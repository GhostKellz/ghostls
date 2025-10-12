const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// Language type for a document
pub const LanguageType = enum {
    ghostlang, // .gza, .ghost files
    gshell, // .gsh files (pure shell scripts)
    gshell_config, // .gshrc.gza, .gshrc files (shell config with ghostlang)

    /// Detect language type from URI/filename
    pub fn fromUri(uri: []const u8) LanguageType {
        if (std.mem.endsWith(u8, uri, ".gshrc.gza")) {
            return .gshell_config;
        } else if (std.mem.endsWith(u8, uri, ".gshrc")) {
            return .gshell_config;
        } else if (std.mem.endsWith(u8, uri, ".gsh")) {
            return .gshell;
        } else if (std.mem.endsWith(u8, uri, ".gza")) {
            return .ghostlang;
        } else if (std.mem.endsWith(u8, uri, ".ghost")) {
            return .ghostlang;
        }
        // Default to ghostlang for unknown extensions
        return .ghostlang;
    }

    /// Get the Grove language for this type
    pub fn getGroveLanguage(self: LanguageType) !grove.Language {
        return switch (self) {
            .ghostlang => try grove.Languages.ghostlang.get(),
            .gshell => try grove.Languages.gshell.get(),
            .gshell_config => try grove.Languages.ghostlang.get(), // Config files use Ghostlang syntax
        };
    }

    /// Check if this language type supports shell FFI
    pub fn supportsShellFFI(self: LanguageType) bool {
        return switch (self) {
            .ghostlang => false,
            .gshell => true,
            .gshell_config => true, // .gshrc.gza has full shell FFI access
        };
    }
};

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
        language_type: LanguageType,

        pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
            allocator.free(self.uri);
            allocator.free(self.text);
            if (self.tree) |*tree| {
                tree.deinit();
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator) !DocumentManager {
        // Initialize parser (language will be set per-document)
        const parser = try grove.Parser.init(allocator);

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
        // Detect language type from URI
        const lang_type = LanguageType.fromUri(uri);

        // Set appropriate grammar
        const language = try lang_type.getGroveLanguage();
        try self.parser.setLanguage(language);

        // Parse the document
        const tree = try self.parser.parseUtf8(null, text);

        const doc = Document{
            .uri = try self.allocator.dupe(u8, uri),
            .version = version,
            .text = try self.allocator.dupe(u8, text),
            .tree = tree,
            .language_type = lang_type,
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

        // Set appropriate grammar based on document's language type
        const language = try doc.language_type.getGroveLanguage();
        try self.parser.setLanguage(language);

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
