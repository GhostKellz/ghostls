const std = @import("std");
const protocol = @import("protocol.zig");
const transport = @import("transport.zig");
const DocumentManager = @import("document_manager.zig").DocumentManager;
const DiagnosticEngine = @import("diagnostics.zig").DiagnosticEngine;
const HoverProvider = @import("hover_provider.zig").HoverProvider;
const SymbolProvider = @import("symbol_provider.zig").SymbolProvider;
const DefinitionProvider = @import("definition_provider.zig").DefinitionProvider;
const CompletionProvider = @import("completion_provider.zig").CompletionProvider;
const ReferencesProvider = @import("references_provider.zig").ReferencesProvider;
const WorkspaceSymbolProvider = @import("workspace_symbol_provider.zig").WorkspaceSymbolProvider;
const FFILoader = @import("ffi_loader.zig").FFILoader;

pub const Server = struct {
    allocator: std.mem.Allocator,
    transport: transport.Transport,
    response_builder: transport.ResponseBuilder,
    document_manager: DocumentManager,
    diagnostic_engine: DiagnosticEngine,
    hover_provider: HoverProvider,
    symbol_provider: SymbolProvider,
    definition_provider: DefinitionProvider,
    completion_provider: CompletionProvider,
    references_provider: ReferencesProvider,
    workspace_symbol_provider: WorkspaceSymbolProvider,
    ffi_loader: FFILoader,
    initialized: bool = false,
    shutdown_requested: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Server {
        // Initialize FFI loader with embedded definitions
        var ffi_loader = FFILoader.init(allocator);
        try ffi_loader.loadEmbedded();

        return .{
            .allocator = allocator,
            .transport = transport.Transport.init(allocator),
            .response_builder = transport.ResponseBuilder.init(allocator),
            .document_manager = try DocumentManager.init(allocator),
            .diagnostic_engine = DiagnosticEngine.init(allocator),
            .hover_provider = HoverProvider.init(allocator, &ffi_loader),
            .symbol_provider = SymbolProvider.init(allocator),
            .definition_provider = DefinitionProvider.init(allocator),
            .completion_provider = CompletionProvider.init(allocator, &ffi_loader),
            .references_provider = ReferencesProvider.init(allocator),
            .workspace_symbol_provider = WorkspaceSymbolProvider.init(allocator),
            .ffi_loader = ffi_loader,
        };
    }

    pub fn deinit(self: *Server) void {
        self.document_manager.deinit();
        self.workspace_symbol_provider.deinit();
        self.ffi_loader.deinit();
    }

    pub fn run(self: *Server) !void {
        self.transport.log("GhostLS starting...", .{});

        while (!self.shutdown_requested) {
            const message = self.transport.readMessage() catch |err| {
                if (err == error.EndOfStream) {
                    self.transport.log("Client disconnected", .{});
                    break;
                }
                self.transport.log("Error reading message: {}", .{err});
                continue;
            };
            defer self.allocator.free(message);

            self.transport.log("Received: {s}", .{message});

            const response = self.handleMessage(message) catch |err| {
                self.transport.log("Error handling message: {}", .{err});
                const err_response = try self.response_builder.@"error"(
                    null,
                    transport.ErrorCodes.InternalError,
                    "Internal error",
                );
                defer self.allocator.free(err_response);
                try self.transport.writeMessage(err_response);
                continue;
            };

            if (response) |resp| {
                defer self.allocator.free(resp);
                self.transport.log("Sending: {s}", .{resp});
                try self.transport.writeMessage(resp);
            }
        }

        self.transport.log("GhostLS shutting down", .{});
    }

    fn handleMessage(self: *Server, message: []const u8) !?[]const u8 {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            message,
            .{},
        );
        defer parsed.deinit();

        const obj = parsed.value.object;
        const method = obj.get("method") orelse {
            // This is a response, not a request/notification - ignore
            return null;
        };

        const method_str = method.string;

        // Get ID if present (requests have IDs, notifications don't)
        const maybe_id = obj.get("id");

        // Route to appropriate handler
        if (std.mem.eql(u8, method_str, protocol.Methods.initialize)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleInitialize(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.initialized)) {
            return try self.handleInitialized();
        } else if (std.mem.eql(u8, method_str, protocol.Methods.shutdown)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleShutdown(id);
        } else if (std.mem.eql(u8, method_str, protocol.Methods.exit)) {
            self.shutdown_requested = true;
            return null;
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_did_open)) {
            return try self.handleDidOpen(obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_did_change)) {
            return try self.handleDidChange(obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_did_save)) {
            return try self.handleDidSave(obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_did_close)) {
            return try self.handleDidClose(obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_hover)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleHover(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_definition)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleDefinition(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_document_symbol)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleDocumentSymbol(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_completion)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleCompletion(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_references)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleReferences(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.workspace_symbol)) {
            const id = maybe_id orelse return error.InvalidRequest;
            return try self.handleWorkspaceSymbol(id, obj.get("params"));
        } else if (std.mem.eql(u8, method_str, protocol.Methods.workspace_did_change_configuration)) {
            return try self.handleDidChangeConfiguration(obj.get("params"));
        } else {
            self.transport.log("Unknown method: {s}", .{method_str});
            if (maybe_id) |id| {
                return try self.response_builder.@"error"(
                    self.jsonIdToProtocolId(id),
                    transport.ErrorCodes.MethodNotFound,
                    "Method not found",
                );
            }
            return null;
        }
    }

    fn handleInitialize(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        _ = params; // We'll use this later to parse client capabilities

        self.transport.log("Handling initialize", .{});

        // Build InitializeResult JSON manually for compatibility
        const capabilities_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"positionEncoding":"utf-16","textDocumentSync":{{"openClose":true,"change":1,"save":{{"includeText":true}}}},"hoverProvider":true,"completionProvider":{{"triggerCharacters":[".",":"]}},"definitionProvider":true,"referencesProvider":true,"workspaceSymbolProvider":true,"documentSymbolProvider":true}}
            ,
            .{},
        );
        defer self.allocator.free(capabilities_json);

        const result_json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"capabilities":{s},"serverInfo":{{"name":"ghostls","version":"0.0.1-alpha"}}}}
            ,
            .{capabilities_json},
        );
        defer self.allocator.free(result_json);

        const id_str = switch (self.jsonIdToProtocolId(id)) {
            .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
            .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
        };
        defer self.allocator.free(id_str);

        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
            .{ id_str, result_json },
        );
    }

    fn handleInitialized(self: *Server) !?[]const u8 {
        self.transport.log("Client initialized", .{});
        self.initialized = true;
        return null;
    }

    fn handleShutdown(self: *Server, id: std.json.Value) ![]const u8 {
        self.transport.log("Shutdown requested", .{});
        self.shutdown_requested = true;
        return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
    }

    fn handleDidOpen(self: *Server, params: ?std.json.Value) !?[]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri_value = text_document.object.get("uri") orelse return error.InvalidParams;
            const text_value = text_document.object.get("text") orelse return error.InvalidParams;
            const version_value = text_document.object.get("version") orelse return error.InvalidParams;

            const uri = uri_value.string;
            const text = text_value.string;
            const version = @as(i32, @intCast(version_value.integer));

            self.transport.log("Document opened: {s}", .{uri});
            self.transport.log("Content length: {d}", .{text.len});

            // Open document and parse
            try self.document_manager.open(uri, text, version);

            // Index symbols for workspace search
            const doc = self.document_manager.get(uri).?;
            if (doc.tree) |*tree| {
                try self.workspace_symbol_provider.indexDocument(uri, tree, text);
            }

            // Publish diagnostics
            try self.publishDiagnostics(uri);
        }
        return null;
    }

    fn handleDidChange(self: *Server, params: ?std.json.Value) !?[]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri_value = text_document.object.get("uri") orelse return error.InvalidParams;
            const version_value = text_document.object.get("version") orelse return error.InvalidParams;
            const content_changes = p.object.get("contentChanges") orelse return error.InvalidParams;

            const uri = uri_value.string;
            const version = @as(i32, @intCast(version_value.integer));

            self.transport.log("Document changed: {s}", .{uri});

            // For MVP, we use full document sync (contentChanges[0].text)
            const changes_array = content_changes.array;
            if (changes_array.items.len > 0) {
                const first_change = changes_array.items[0];
                const new_text = first_change.object.get("text") orelse return error.InvalidParams;

                // Update document
                try self.document_manager.update(uri, new_text.string, version);

                // Re-index symbols for workspace search
                const doc = self.document_manager.get(uri).?;
                if (doc.tree) |*tree| {
                    try self.workspace_symbol_provider.indexDocument(uri, tree, new_text.string);
                }

                // Publish diagnostics
                try self.publishDiagnostics(uri);
            }
        }
        return null;
    }

    fn handleDidSave(self: *Server, params: ?std.json.Value) !?[]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;

            self.transport.log("Document saved: {s}", .{uri.string});

            // If includeText is true, the text will be in params.text
            if (p.object.get("text")) |text_value| {
                self.transport.log("Save included text of length: {d}", .{text_value.string.len});
                // Could re-parse if needed, but we already have latest from didChange
            }

            // Optionally re-run diagnostics on save (already done on didChange)
            // For now, just log the save event
        }
        return null;
    }

    fn handleDidClose(self: *Server, params: ?std.json.Value) !?[]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;

            self.transport.log("Document closed: {s}", .{uri.string});

            // Remove document from manager
            self.document_manager.close(uri.string);
        }
        return null;
    }

    fn handleDidChangeConfiguration(self: *Server, params: ?std.json.Value) !?[]const u8 {
        if (params) |p| {
            self.transport.log("Configuration changed: {any}", .{p});
            // TODO: Parse and apply configuration settings
        } else {
            self.transport.log("Configuration changed (no params)", .{});
        }
        return null;
    }

    fn handleHover(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;
            const position = p.object.get("position") orelse return error.InvalidParams;

            const line = @as(u32, @intCast(position.object.get("line").?.integer));
            const character = @as(u32, @intCast(position.object.get("character").?.integer));

            self.transport.log("Hover requested: {s} at {d}:{d}", .{ uri.string, line, character });

            const doc = self.document_manager.get(uri.string) orelse {
                return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
            };

            if (doc.tree) |*tree| {
                // Check if this document supports shell FFI based on file type
                const supports_ffi = doc.language_type.supportsShellFFI();

                const hover_result = try self.hover_provider.hover(tree, doc.text, .{
                    .line = line,
                    .character = character,
                }, supports_ffi);

                if (hover_result) |hover| {
                    defer self.allocator.free(hover.contents.value);

                    // Build hover response JSON
                    const range_str = if (hover.range) |r|
                        try std.fmt.allocPrint(
                            self.allocator,
                            ",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}",
                            .{ r.start.line, r.start.character, r.end.line, r.end.character },
                        )
                    else
                        try self.allocator.dupe(u8, "");
                    defer self.allocator.free(range_str);

                    const value_escaped = try self.escapeJson(hover.contents.value);
                    defer self.allocator.free(value_escaped);

                    const result = try std.fmt.allocPrint(
                        self.allocator,
                        "{{\"contents\":{{\"kind\":\"{s}\",\"value\":\"{s}\"}}{s}}}",
                        .{ hover.contents.kind, value_escaped, range_str },
                    );
                    defer self.allocator.free(result);

                    const id_str = switch (self.jsonIdToProtocolId(id)) {
                        .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                        .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
                    };
                    defer self.allocator.free(id_str);

                    return try std.fmt.allocPrint(
                        self.allocator,
                        "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
                        .{ id_str, result },
                    );
                }
            }
        }

        return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
    }

    fn handleDefinition(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;
            const position = p.object.get("position") orelse return error.InvalidParams;

            const line = @as(u32, @intCast(position.object.get("line").?.integer));
            const character = @as(u32, @intCast(position.object.get("character").?.integer));

            self.transport.log("Definition requested: {s} at {d}:{d}", .{ uri.string, line, character });

            const doc = self.document_manager.get(uri.string) orelse {
                return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
            };

            if (doc.tree) |*tree| {
                const location = try self.definition_provider.findDefinition(
                    tree,
                    doc.text,
                    uri.string,
                    .{ .line = line, .character = character },
                );

                if (location) |loc| {
                    const uri_escaped = try self.escapeJson(loc.uri);
                    defer self.allocator.free(uri_escaped);

                    const result = try std.fmt.allocPrint(
                        self.allocator,
                        "{{\"uri\":\"{s}\",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}",
                        .{
                            uri_escaped,
                            loc.range.start.line,
                            loc.range.start.character,
                            loc.range.end.line,
                            loc.range.end.character,
                        },
                    );
                    defer self.allocator.free(result);

                    const id_str = switch (self.jsonIdToProtocolId(id)) {
                        .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                        .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
                    };
                    defer self.allocator.free(id_str);

                    return try std.fmt.allocPrint(
                        self.allocator,
                        "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
                        .{ id_str, result },
                    );
                }
            }
        }

        return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
    }

    fn handleDocumentSymbol(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;

            self.transport.log("DocumentSymbol requested: {s}", .{uri.string});

            const doc = self.document_manager.get(uri.string) orelse {
                return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
            };

            if (doc.tree) |*tree| {
                const symbols = try self.symbol_provider.getSymbols(tree, doc.text);
                defer {
                    for (symbols) |sym| {
                        self.symbol_provider.freeSymbol(sym);
                    }
                    self.allocator.free(symbols);
                }

                // Build symbols JSON array
                var symbols_json: std.ArrayList(u8) = .empty;
                defer symbols_json.deinit(self.allocator);

                try symbols_json.appendSlice(self.allocator, "[");
                for (symbols, 0..) |symbol, i| {
                    if (i > 0) try symbols_json.appendSlice(self.allocator, ",");
                    const sym_str = try self.symbolToJson(symbol);
                    defer self.allocator.free(sym_str);
                    try symbols_json.appendSlice(self.allocator, sym_str);
                }
                try symbols_json.appendSlice(self.allocator, "]");

                const id_str = switch (self.jsonIdToProtocolId(id)) {
                    .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                    .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
                };
                defer self.allocator.free(id_str);

                return try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
                    .{ id_str, symbols_json.items },
                );
            }
        }

        return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
    }

    /// Convert a symbol to JSON
    fn symbolToJson(self: *Server, symbol: protocol.DocumentSymbol) ![]const u8 {
        const name_escaped = try self.escapeJson(symbol.name);
        defer self.allocator.free(name_escaped);

        const detail_str = if (symbol.detail) |detail| blk: {
            const detail_escaped = try self.escapeJson(detail);
            defer self.allocator.free(detail_escaped);
            break :blk try std.fmt.allocPrint(
                self.allocator,
                ",\"detail\":\"{s}\"",
                .{detail_escaped},
            );
        } else try self.allocator.dupe(u8, "");
        defer self.allocator.free(detail_str);

        const children_str = if (symbol.children) |children| blk: {
            var children_json: std.ArrayList(u8) = .empty;
            defer children_json.deinit(self.allocator);

            try children_json.appendSlice(self.allocator, ",\"children\":[");
            for (children, 0..) |child, i| {
                if (i > 0) try children_json.appendSlice(self.allocator, ",");
                const child_str = try self.symbolToJson(child);
                defer self.allocator.free(child_str);
                try children_json.appendSlice(self.allocator, child_str);
            }
            try children_json.appendSlice(self.allocator, "]");
            break :blk try children_json.toOwnedSlice(self.allocator);
        } else try self.allocator.dupe(u8, "");
        defer self.allocator.free(children_str);

        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"name\":\"{s}\"{s},\"kind\":{d},\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}},\"selectionRange\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}{s}}}",
            .{
                name_escaped,
                detail_str,
                @intFromEnum(symbol.kind),
                symbol.range.start.line,
                symbol.range.start.character,
                symbol.range.end.line,
                symbol.range.end.character,
                symbol.selectionRange.start.line,
                symbol.selectionRange.start.character,
                symbol.selectionRange.end.line,
                symbol.selectionRange.end.character,
                children_str,
            },
        );
    }

    /// Publish diagnostics for a document
    fn publishDiagnostics(self: *Server, uri: []const u8) !void {
        const doc = self.document_manager.get(uri) orelse return;
        const tree_opt = &doc.tree;
        if (tree_opt.*) |*tree| {
            // Get diagnostics
            const diagnostics = try self.diagnostic_engine.diagnose(tree, doc.text);
            defer {
                // Free diagnostic messages
                for (diagnostics) |diag| {
                    self.allocator.free(diag.message);
                }
                self.allocator.free(diagnostics);
            }

            self.transport.log("Found {d} diagnostics for {s}", .{ diagnostics.len, uri });

        // Build diagnostics JSON array
        var diag_json: std.ArrayList(u8) = .empty;
        defer diag_json.deinit(self.allocator);

        try diag_json.appendSlice(self.allocator, "[");
        for (diagnostics, 0..) |diag, i| {
            if (i > 0) try diag_json.appendSlice(self.allocator, ",");

            const severity = @intFromEnum(diag.severity orelse .Error);
            const message_escaped = try self.escapeJson(diag.message);
            defer self.allocator.free(message_escaped);

            const diag_str = try std.fmt.allocPrint(
                self.allocator,
                "{{\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}},\"severity\":{d},\"message\":\"{s}\",\"source\":\"ghostls\"}}",
                .{
                    diag.range.start.line,
                    diag.range.start.character,
                    diag.range.end.line,
                    diag.range.end.character,
                    severity,
                    message_escaped,
                },
            );
            defer self.allocator.free(diag_str);

            try diag_json.appendSlice(self.allocator, diag_str);
        }
        try diag_json.appendSlice(self.allocator, "]");

        // Build and send notification
        const uri_escaped = try self.escapeJson(uri);
        defer self.allocator.free(uri_escaped);

        const notification = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{{\"uri\":\"{s}\",\"diagnostics\":{s}}}}}",
            .{ uri_escaped, diag_json.items },
        );
        defer self.allocator.free(notification);

            try self.transport.writeMessage(notification);
            self.transport.log("Published diagnostics", .{});
        }
    }

    /// Escape JSON strings
    fn escapeJson(self: *Server, str: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        for (str) |c| {
            switch (c) {
                '"' => try result.appendSlice(self.allocator, "\\\""),
                '\\' => try result.appendSlice(self.allocator, "\\\\"),
                '\n' => try result.appendSlice(self.allocator, "\\n"),
                '\r' => try result.appendSlice(self.allocator, "\\r"),
                '\t' => try result.appendSlice(self.allocator, "\\t"),
                else => try result.append(self.allocator, c),
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    fn handleCompletion(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;
            const position = p.object.get("position") orelse return error.InvalidParams;

            const line = @as(u32, @intCast(position.object.get("line").?.integer));
            const character = @as(u32, @intCast(position.object.get("character").?.integer));

            self.transport.log("Completion requested: {s} at {d}:{d}", .{ uri.string, line, character });

            const doc = self.document_manager.get(uri.string) orelse {
                return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
            };

            if (doc.tree) |*tree| {
                // Check if this document supports shell FFI based on file type
                const supports_ffi = doc.language_type.supportsShellFFI();

                const items = try self.completion_provider.complete(
                    tree,
                    doc.text,
                    .{ .line = line, .character = character },
                    supports_ffi,
                );
                defer self.completion_provider.freeCompletions(items);

                // Build completion items JSON array
                var items_json: std.ArrayList(u8) = .empty;
                defer items_json.deinit(self.allocator);

                try items_json.appendSlice(self.allocator, "[");
                for (items, 0..) |item, i| {
                    if (i > 0) try items_json.appendSlice(self.allocator, ",");

                    const label_escaped = try self.escapeJson(item.label);
                    defer self.allocator.free(label_escaped);

                    const detail_str = if (item.detail) |detail| blk: {
                        const detail_escaped = try self.escapeJson(detail);
                        defer self.allocator.free(detail_escaped);
                        break :blk try std.fmt.allocPrint(
                            self.allocator,
                            ",\"detail\":\"{s}\"",
                            .{detail_escaped},
                        );
                    } else try self.allocator.dupe(u8, "");
                    defer self.allocator.free(detail_str);

                    const doc_str = if (item.documentation) |documentation| blk: {
                        const doc_escaped = try self.escapeJson(documentation);
                        defer self.allocator.free(doc_escaped);
                        break :blk try std.fmt.allocPrint(
                            self.allocator,
                            ",\"documentation\":\"{s}\"",
                            .{doc_escaped},
                        );
                    } else try self.allocator.dupe(u8, "");
                    defer self.allocator.free(doc_str);

                    const item_json = try std.fmt.allocPrint(
                        self.allocator,
                        "{{\"label\":\"{s}\",\"kind\":{d}{s}{s}}}",
                        .{ label_escaped, @intFromEnum(item.kind), detail_str, doc_str },
                    );
                    defer self.allocator.free(item_json);

                    try items_json.appendSlice(self.allocator, item_json);
                }
                try items_json.appendSlice(self.allocator, "]");

                const id_str = switch (self.jsonIdToProtocolId(id)) {
                    .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                    .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
                };
                defer self.allocator.free(id_str);

                return try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
                    .{ id_str, items_json.items },
                );
            }
        }

        return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
    }

    fn handleReferences(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        if (params) |p| {
            const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
            const uri = text_document.object.get("uri") orelse return error.InvalidParams;
            const position = p.object.get("position") orelse return error.InvalidParams;
            const context = p.object.get("context") orelse return error.InvalidParams;

            const line = @as(u32, @intCast(position.object.get("line").?.integer));
            const character = @as(u32, @intCast(position.object.get("character").?.integer));
            const include_declaration = context.object.get("includeDeclaration").?.bool;

            self.transport.log("References requested: {s} at {d}:{d}", .{ uri.string, line, character });

            const doc = self.document_manager.get(uri.string) orelse {
                return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
            };

            if (doc.tree) |*tree| {
                const locations = try self.references_provider.findReferences(
                    tree,
                    doc.text,
                    uri.string,
                    .{ .line = line, .character = character },
                    include_declaration,
                );
                defer self.references_provider.freeLocations(locations);

                // Build locations JSON array
                var locs_json: std.ArrayList(u8) = .empty;
                defer locs_json.deinit(self.allocator);

                try locs_json.appendSlice(self.allocator, "[");
                for (locations, 0..) |loc, i| {
                    if (i > 0) try locs_json.appendSlice(self.allocator, ",");

                    const uri_escaped = try self.escapeJson(loc.uri);
                    defer self.allocator.free(uri_escaped);

                    const loc_json = try std.fmt.allocPrint(
                        self.allocator,
                        "{{\"uri\":\"{s}\",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}",
                        .{
                            uri_escaped,
                            loc.range.start.line,
                            loc.range.start.character,
                            loc.range.end.line,
                            loc.range.end.character,
                        },
                    );
                    defer self.allocator.free(loc_json);

                    try locs_json.appendSlice(self.allocator, loc_json);
                }
                try locs_json.appendSlice(self.allocator, "]");

                const id_str = switch (self.jsonIdToProtocolId(id)) {
                    .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                    .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
                };
                defer self.allocator.free(id_str);

                return try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
                    .{ id_str, locs_json.items },
                );
            }
        }

        return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
    }

    fn handleWorkspaceSymbol(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
        const query = if (params) |p|
            if (p.object.get("query")) |q| q.string else ""
        else
            "";

        self.transport.log("Workspace symbol requested: query='{s}'", .{query});

        const symbols = try self.workspace_symbol_provider.search(query);
        defer self.workspace_symbol_provider.freeSymbols(symbols);

        // Build symbols JSON array
        var syms_json: std.ArrayList(u8) = .empty;
        defer syms_json.deinit(self.allocator);

        try syms_json.appendSlice(self.allocator, "[");
        for (symbols, 0..) |symbol, i| {
            if (i > 0) try syms_json.appendSlice(self.allocator, ",");

            const name_escaped = try self.escapeJson(symbol.name);
            defer self.allocator.free(name_escaped);

            const uri_escaped = try self.escapeJson(symbol.location.uri);
            defer self.allocator.free(uri_escaped);

            const container_str = if (symbol.containerName) |container| blk: {
                const container_escaped = try self.escapeJson(container);
                defer self.allocator.free(container_escaped);
                break :blk try std.fmt.allocPrint(
                    self.allocator,
                    ",\"containerName\":\"{s}\"",
                    .{container_escaped},
                );
            } else try self.allocator.dupe(u8, "");
            defer self.allocator.free(container_str);

            const sym_json = try std.fmt.allocPrint(
                self.allocator,
                "{{\"name\":\"{s}\",\"kind\":{d},\"location\":{{\"uri\":\"{s}\",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}{s}}}",
                .{
                    name_escaped,
                    @intFromEnum(symbol.kind),
                    uri_escaped,
                    symbol.location.range.start.line,
                    symbol.location.range.start.character,
                    symbol.location.range.end.line,
                    symbol.location.range.end.character,
                    container_str,
                },
            );
            defer self.allocator.free(sym_json);

            try syms_json.appendSlice(self.allocator, sym_json);
        }
        try syms_json.appendSlice(self.allocator, "]");

        const id_str = switch (self.jsonIdToProtocolId(id)) {
            .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
            .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
        };
        defer self.allocator.free(id_str);

        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
            .{ id_str, syms_json.items },
        );
    }

    /// Helper to convert std.json.Value to protocol ID
    fn jsonIdToProtocolId(self: *Server, value: std.json.Value) protocol.RequestMessage.Id {
        _ = self;
        return switch (value) {
            .integer => |i| .{ .integer = i },
            .number_string => |s| .{ .string = s },
            .string => |s| .{ .string = s },
            else => .{ .integer = 0 }, // Fallback
        };
    }
};
