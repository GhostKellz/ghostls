const std = @import("std");
const kalix = @import("kalix");
const protocol = @import("protocol.zig");

/// Converts kalix frontend diagnostics to LSP diagnostics
pub const KalixDiagnosticProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) KalixDiagnosticProvider {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *KalixDiagnosticProvider) void {
        // No resources to clean up
    }

    /// Analyze kalix source code and return LSP diagnostics
    pub fn analyze(self: *KalixDiagnosticProvider, source: []const u8) ![]const protocol.Diagnostic {
        var result = try kalix.frontend.api.analyzeSource(self.allocator, source);
        defer result.deinit();

        var diagnostics: std.ArrayList(protocol.Diagnostic) = .{};
        errdefer {
            for (diagnostics.items) |*diag| {
                self.allocator.free(diag.message);
            }
            diagnostics.deinit(self.allocator);
        }

        // Convert kalix diagnostics to LSP diagnostics
        for (result.diagnostics) |kalix_diag| {
            const lsp_diag = protocol.Diagnostic{
                .range = protocol.Range{
                    .start = protocol.Position{ .line = 0, .character = 0 },
                    .end = protocol.Position{ .line = 0, .character = 0 },
                },
                .severity = .Error,
                .code = null,
                .source = "kalix",
                .message = try self.allocator.dupe(u8, kalix_diag.message),
            };

            try diagnostics.append(self.allocator, lsp_diag);
        }

        return try diagnostics.toOwnedSlice(self.allocator);
    }

    /// Free diagnostics returned by analyze()
    pub fn freeDiagnostics(self: *KalixDiagnosticProvider, diagnostics: []const protocol.Diagnostic) void {
        for (diagnostics) |diag| {
            self.allocator.free(diag.message);
        }
        self.allocator.free(diagnostics);
    }
};

const testing = std.testing;

test "kalix diagnostics provider analyzes valid source" {
    var provider = KalixDiagnosticProvider.init(testing.allocator);
    defer provider.deinit();

    const source =
        \\contract Treasury {
        \\    state balance: u64;
        \\
        \\    fn deposit(amount: u64) payable {
        \\        state.balance = state.balance + amount;
        \\    }
        \\
        \\    fn getBalance() view -> u64 {
        \\        return state.balance;
        \\    }
        \\}
    ;

    const diagnostics = try provider.analyze(source);
    defer provider.freeDiagnostics(diagnostics);

    // Valid kalix source should produce no diagnostics
    try testing.expectEqual(@as(usize, 0), diagnostics.len);
}

test "kalix diagnostics provider detects semantic errors" {
    var provider = KalixDiagnosticProvider.init(testing.allocator);
    defer provider.deinit();

    const source =
        \\contract Treasury {
        \\    state balance: u64;
        \\    state balance: u64;
        \\}
    ;

    const diagnostics = try provider.analyze(source);
    defer provider.freeDiagnostics(diagnostics);

    // Duplicate state declaration should produce diagnostic
    try testing.expect(diagnostics.len > 0);
    try testing.expect(std.mem.indexOf(u8, diagnostics[0].message, "duplicate") != null or
        std.mem.indexOf(u8, diagnostics[0].message, "semantic") != null);
}
