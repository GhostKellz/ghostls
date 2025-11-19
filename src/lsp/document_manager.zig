const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");
const blockchain_analyzer = @import("blockchain_analyzer.zig");
const kalix_diagnostics = @import("kalix_diagnostics.zig");

/// Language type for a document
pub const LanguageType = enum {
    ghostlang, // .gza, .ghost files
    gshell, // .gsh files (pure shell scripts)
    gshell_config, // .gshrc.gza, .gshrc files (shell config with ghostlang)
    kalix, // .kalix files (smart contracts)

    /// Detect language type from URI/filename
    pub fn fromUri(uri: []const u8) LanguageType {
        if (std.mem.endsWith(u8, uri, ".kalix")) {
            return .kalix;
        } else if (std.mem.endsWith(u8, uri, ".gshrc.gza")) {
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
            .kalix => try grove.Languages.kalix.get(),
        };
    }

    /// Check if this language type supports shell FFI
    pub fn supportsShellFFI(self: LanguageType) bool {
        return switch (self) {
            .ghostlang => false,
            .gshell => true,
            .gshell_config => true, // .gshrc.gza has full shell FFI access
            .kalix => false,
        };
    }

    /// Check if this is a smart contract language (supports blockchain analysis)
    pub fn isSmartContract(self: LanguageType) bool {
        return switch (self) {
            .ghostlang => false,
            .gshell => false,
            .gshell_config => false,
            .kalix => true,
        };
    }
};

/// Manages open documents and their parse trees
pub const DocumentManager = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(Document),
    parser: grove.Parser,
    blockchain_analyzer: blockchain_analyzer.BlockchainAnalyzer,
    kalix_provider: kalix_diagnostics.KalixDiagnosticProvider,

    pub const Document = struct {
        uri: []const u8,
        version: i32,
        text: []const u8,
        tree: ?grove.Tree,
        language_type: LanguageType,
        diagnostics: []blockchain_analyzer.BlockchainDiagnostic,

        pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
            allocator.free(self.uri);
            allocator.free(self.text);
            allocator.free(self.diagnostics);
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
            .blockchain_analyzer = blockchain_analyzer.BlockchainAnalyzer.init(allocator),
            .kalix_provider = kalix_diagnostics.KalixDiagnosticProvider.init(allocator),
        };
    }

    pub fn deinit(self: *DocumentManager) void {
        var it = self.documents.valueIterator();
        while (it.next()) |doc| {
            doc.deinit(self.allocator);
        }
        self.documents.deinit();
        self.parser.deinit();
        self.blockchain_analyzer.deinit();
        self.kalix_provider.deinit();
    }

    /// Open a document and parse it
    pub fn open(self: *DocumentManager, uri: []const u8, text: []const u8, version: i32) !void {
        // Detect language type from URI
        const lang_type = LanguageType.fromUri(uri);

        // For kalix files, use kalix's own parser (not Grove)
        if (lang_type == .kalix) {
            // Kalix uses its own frontend parser, no Grove tree needed
            const diagnostics = try self.allocator.alloc(blockchain_analyzer.BlockchainDiagnostic, 0);

            const doc = Document{
                .uri = try self.allocator.dupe(u8, uri),
                .version = version,
                .text = try self.allocator.dupe(u8, text),
                .tree = null, // Kalix doesn't use Grove tree
                .language_type = lang_type,
                .diagnostics = diagnostics,
            };

            try self.documents.put(doc.uri, doc);
            return;
        }

        // Set appropriate grammar for non-kalix files
        const language = try lang_type.getGroveLanguage();
        try self.parser.setLanguage(language);

        // Parse the document
        const tree = try self.parser.parseUtf8(null, text);

        // Run blockchain analysis for GhostLang files
        const diagnostics = if (lang_type == .ghostlang)
            try self.blockchain_analyzer.analyze(&tree, text)
        else
            try self.allocator.alloc(blockchain_analyzer.BlockchainDiagnostic, 0);

        const doc = Document{
            .uri = try self.allocator.dupe(u8, uri),
            .version = version,
            .text = try self.allocator.dupe(u8, text),
            .tree = tree,
            .language_type = lang_type,
            .diagnostics = diagnostics,
        };

        try self.documents.put(doc.uri, doc);
    }

    /// Update a document with new text (full sync for MVP)
    pub fn update(self: *DocumentManager, uri: []const u8, text: []const u8, version: i32) !void {
        var doc = self.documents.getPtr(uri) orelse return error.DocumentNotFound;

        // Free old text and diagnostics
        self.allocator.free(doc.text);
        self.allocator.free(doc.diagnostics);

        // For kalix files, use kalix's own parser (not Grove)
        if (doc.language_type == .kalix) {
            // Parse new text
            if (doc.tree) |*old_tree| {
                old_tree.deinit();
            }

            // Kalix uses its own frontend parser, no Grove tree needed
            const new_diagnostics = try self.allocator.alloc(blockchain_analyzer.BlockchainDiagnostic, 0);

            // Update document
            doc.text = try self.allocator.dupe(u8, text);
            doc.version = version;
            doc.tree = null;
            doc.diagnostics = new_diagnostics;
            return;
        }

        // Parse new text
        if (doc.tree) |*old_tree| {
            old_tree.deinit();
        }

        // Set appropriate grammar based on document's language type
        const language = try doc.language_type.getGroveLanguage();
        try self.parser.setLanguage(language);

        const new_tree = try self.parser.parseUtf8(null, text);

        // Run blockchain analysis for GhostLang files
        const new_diagnostics = if (doc.language_type == .ghostlang)
            try self.blockchain_analyzer.analyze(&new_tree, text)
        else
            try self.allocator.alloc(blockchain_analyzer.BlockchainDiagnostic, 0);

        // Update document
        doc.text = try self.allocator.dupe(u8, text);
        doc.version = version;
        doc.tree = new_tree;
        doc.diagnostics = new_diagnostics;
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

    /// Get blockchain diagnostics for a document
    pub fn getDiagnostics(self: *DocumentManager, uri: []const u8) []const blockchain_analyzer.BlockchainDiagnostic {
        const doc = self.documents.getPtr(uri) orelse return &[_]blockchain_analyzer.BlockchainDiagnostic{};
        return doc.diagnostics;
    }

    /// Get kalix-specific diagnostics for a kalix document
    /// Caller must free the returned diagnostics using freeKalixDiagnostics()
    pub fn getKalixDiagnostics(self: *DocumentManager, uri: []const u8) ![]const protocol.Diagnostic {
        const doc = self.documents.getPtr(uri) orelse return &[_]protocol.Diagnostic{};
        if (doc.language_type != .kalix) return &[_]protocol.Diagnostic{};

        return try self.kalix_provider.analyze(doc.text);
    }

    /// Free kalix diagnostics returned by getKalixDiagnostics()
    pub fn freeKalixDiagnostics(self: *DocumentManager, diagnostics: []const protocol.Diagnostic) void {
        self.kalix_provider.freeDiagnostics(diagnostics);
    }
};
