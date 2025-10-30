const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");

/// DiagnosticEngine finds syntax errors using tree-sitter
/// Now uses Grove's enhanced error diagnostics with context and suggestions
pub const DiagnosticEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticEngine {
        return .{ .allocator = allocator };
    }

    /// Analyze a document and return diagnostics
    /// Uses Grove's getSyntaxErrors for enhanced error reporting (replaces ~50 lines!)
    pub fn diagnose(self: *DiagnosticEngine, tree: *const grove.Tree, _: []const u8) ![]protocol.Diagnostic {
        // Use Grove's enhanced syntax error collection (dereference pointer)
        const grove_errors = try grove.getSyntaxErrors(tree.*, self.allocator);
        defer {
            for (grove_errors) |*err| {
                var e = err.*;
                e.deinit(self.allocator);
            }
            self.allocator.free(grove_errors);
        }

        // Convert Grove errors to LSP diagnostics
        var diagnostics = try std.ArrayList(protocol.Diagnostic).initCapacity(
            self.allocator,
            grove_errors.len,
        );
        errdefer {
            for (diagnostics.items) |diag| {
                self.allocator.free(diag.message);
            }
            diagnostics.deinit(self.allocator);
        }

        for (grove_errors) |grove_err| {
            // Convert Grove severity to LSP severity
            const lsp_severity: protocol.DiagnosticSeverity = switch (grove_err.severity) {
                .@"error" => .Error,
                .warning => .Warning,
                .hint => .Hint,
            };

            // Build comprehensive diagnostic message
            var message = std.ArrayList(u8){};
            defer message.deinit(self.allocator);

            try message.appendSlice(self.allocator, grove_err.message);

            // Add expected tokens if available (array of strings)
            if (grove_err.expected) |expected_tokens| {
                try message.appendSlice(self.allocator, "\n\nExpected: ");
                for (expected_tokens, 0..) |token, i| {
                    if (i > 0) try message.appendSlice(self.allocator, ", ");
                    try message.appendSlice(self.allocator, token);
                }
            }

            // Add context if available
            if (grove_err.context_kind) |context| {
                try message.appendSlice(self.allocator, "\n\nContext: ");
                try message.appendSlice(self.allocator, context);
            }

            const message_owned = try message.toOwnedSlice(self.allocator);
            errdefer self.allocator.free(message_owned);

            // Convert Grove range to LSP range
            const lsp_range = protocol.Range{
                .start = .{
                    .line = grove_err.start_point.row,
                    .character = grove_err.start_point.column,
                },
                .end = .{
                    .line = grove_err.end_point.row,
                    .character = grove_err.end_point.column,
                },
            };

            try diagnostics.append(self.allocator, .{
                .range = lsp_range,
                .severity = lsp_severity,
                .message = message_owned,
                .source = "ghostls (Grove)",
            });
        }

        // Also check for any remaining errors manually (fallback)
        const root_opt = tree.rootNode();
        if (root_opt) |root| {
            try self.findBasicErrors(root, &diagnostics);
        }

        return try diagnostics.toOwnedSlice(self.allocator);
    }

    /// Fallback: Find basic ERROR nodes (in case Grove misses any)
    fn findBasicErrors(
        self: *DiagnosticEngine,
        node: grove.Node,
        diagnostics: *std.ArrayList(protocol.Diagnostic),
    ) !void {
        const node_kind = node.kind();

        // Only look for ERROR nodes not already caught by Grove
        if (std.mem.eql(u8, node_kind, "ERROR")) {
            // Check if we already have a diagnostic at this position
            const node_range = protocol.Range{
                .start = .{
                    .line = node.startPosition().row,
                    .character = node.startPosition().column,
                },
                .end = .{
                    .line = node.endPosition().row,
                    .character = node.endPosition().column,
                },
            };

            var already_reported = false;
            for (diagnostics.items) |diag| {
                if (diag.range.start.line == node_range.start.line and
                    diag.range.start.character == node_range.start.character) {
                    already_reported = true;
                    break;
                }
            }

            if (!already_reported) {
                try diagnostics.append(self.allocator, .{
                    .range = node_range,
                    .severity = .Error,
                    .message = try self.allocator.dupe(u8, "Syntax error"),
                    .source = "ghostls",
                });
            }
        }

        // Recurse
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child_node| {
                try self.findBasicErrors(child_node, diagnostics);
            }
        }
    }
};
