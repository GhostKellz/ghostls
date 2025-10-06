const std = @import("std");
const testing = std.testing;
const protocol = @import("ghostls").lsp.protocol;

test "Protocol: method constants are correct" {
    try testing.expectEqualStrings("textDocument/references", protocol.Methods.text_document_references);
    try testing.expectEqualStrings("workspace/symbol", protocol.Methods.workspace_symbol);
    try testing.expectEqualStrings("textDocument/completion", protocol.Methods.text_document_completion);
    try testing.expectEqualStrings("textDocument/hover", protocol.Methods.text_document_hover);
    try testing.expectEqualStrings("textDocument/definition", protocol.Methods.text_document_definition);
}

test "Protocol: Position structure" {
    const pos = protocol.Position{ .line = 10, .character = 5 };
    try testing.expectEqual(@as(u32, 10), pos.line);
    try testing.expectEqual(@as(u32, 5), pos.character);
}

test "Protocol: Range structure" {
    const range = protocol.Range{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 5, .character = 10 },
    };
    try testing.expectEqual(@as(u32, 0), range.start.line);
    try testing.expectEqual(@as(u32, 5), range.end.line);
}

test "Protocol: Location structure" {
    const location = protocol.Location{
        .uri = "file:///test.gza",
        .range = .{
            .start = .{ .line = 0, .character = 0 },
            .end = .{ .line = 1, .character = 0 },
        },
    };
    try testing.expectEqualStrings("file:///test.gza", location.uri);
}

test "Protocol: SymbolKind enumeration" {
    try testing.expectEqual(@as(u32, 12), @intFromEnum(protocol.SymbolKind.Function));
    try testing.expectEqual(@as(u32, 13), @intFromEnum(protocol.SymbolKind.Variable));
    try testing.expectEqual(@as(u32, 5), @intFromEnum(protocol.SymbolKind.Class));
}

test "Protocol: SymbolInformation structure" {
    const allocator = testing.allocator;

    const name = try allocator.dupe(u8, "testFunction");
    defer allocator.free(name);

    const uri = try allocator.dupe(u8, "file:///test.gza");
    defer allocator.free(uri);

    const symbol = protocol.SymbolInformation{
        .name = name,
        .kind = .Function,
        .location = .{
            .uri = uri,
            .range = .{
                .start = .{ .line = 0, .character = 0 },
                .end = .{ .line = 3, .character = 3 },
            },
        },
        .containerName = null,
    };

    try testing.expectEqualStrings("testFunction", symbol.name);
    try testing.expectEqual(protocol.SymbolKind.Function, symbol.kind);
}

test "Protocol: DiagnosticSeverity" {
    try testing.expectEqual(@as(u32, 1), @intFromEnum(protocol.DiagnosticSeverity.Error));
    try testing.expectEqual(@as(u32, 2), @intFromEnum(protocol.DiagnosticSeverity.Warning));
    try testing.expectEqual(@as(u32, 3), @intFromEnum(protocol.DiagnosticSeverity.Information));
    try testing.expectEqual(@as(u32, 4), @intFromEnum(protocol.DiagnosticSeverity.Hint));
}
