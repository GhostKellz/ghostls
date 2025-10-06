const std = @import("std");
const testing = std.testing;
const CompletionProvider = @import("ghostls").lsp.CompletionProvider;
const protocol = @import("ghostls").lsp.protocol;
const grove = @import("grove");

test "CompletionProvider: trigger after dot" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local arr = createArray()
        \\arr.
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = CompletionProvider.init(allocator);

    // Request completions after the dot
    const items = try provider.complete(&tree, source, .{ .line = 1, .character = 4 });
    defer provider.freeCompletions(items);

    // Should return method completions (push, pop, length, etc.)
    try testing.expect(items.len > 0);

    // Verify we get method-type completions
    var has_method = false;
    for (items) |item| {
        if (item.kind == .Method or item.kind == .Property) {
            has_method = true;
            break;
        }
    }
    try testing.expect(has_method);
}

test "CompletionProvider: inside function body" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local function test()
        \\    local myVar = 42
        \\    local result =
        \\end
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = CompletionProvider.init(allocator);

    // Request completions inside function
    const items = try provider.complete(&tree, source, .{ .line = 2, .character = 19 });
    defer provider.freeCompletions(items);

    try testing.expect(items.len > 0);

    // Should include local variables and builtins
    var has_builtin = false;
    for (items) |item| {
        if (item.kind == .Function or item.kind == .Variable) {
            has_builtin = true;
            break;
        }
    }
    try testing.expect(has_builtin);
}

test "CompletionProvider: top level context" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source = "";

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = CompletionProvider.init(allocator);

    // Request completions at top level
    const items = try provider.complete(&tree, source, .{ .line = 0, .character = 0 });
    defer provider.freeCompletions(items);

    try testing.expect(items.len > 0);

    // Should include keywords and builtins
    var has_keyword = false;
    for (items) |item| {
        if (item.kind == .Keyword) {
            has_keyword = true;
            break;
        }
    }
    try testing.expect(has_keyword);
}

test "CompletionProvider: local variable completions" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local function process()
        \\    local inputData = "test"
        \\    local outputData = "result"
        \\    local x =
        \\end
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = CompletionProvider.init(allocator);

    const items = try provider.complete(&tree, source, .{ .line = 3, .character = 14 });
    defer provider.freeCompletions(items);

    try testing.expect(items.len > 0);
}

test "CompletionProvider: memory leak check" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local x = 1
        \\local y = 2
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = CompletionProvider.init(allocator);

    // Request completions multiple times to check for leaks
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const items = try provider.complete(&tree, source, .{ .line = 1, .character = 12 });
        provider.freeCompletions(items);
    }
}

test "CompletionProvider: empty source" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source = "";

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = CompletionProvider.init(allocator);

    const items = try provider.complete(&tree, source, .{ .line = 0, .character = 0 });
    defer provider.freeCompletions(items);

    // Should still return some completions (keywords/builtins)
    try testing.expect(items.len > 0);
}
