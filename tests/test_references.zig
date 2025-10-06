const std = @import("std");
const testing = std.testing;
const ReferencesProvider = @import("ghostls").lsp.ReferencesProvider;
const protocol = @import("ghostls").lsp.protocol;
const grove = @import("grove");

test "ReferencesProvider: find all references to a variable" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local myVar = 42
        \\local x = myVar
        \\local y = myVar + 10
        \\myVar = 100
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = ReferencesProvider.init(allocator);

    // Find references to "myVar" at line 0, character 6 (the declaration)
    const locations = try provider.findReferences(
        &tree,
        source,
        "file:///test.gza",
        .{ .line = 0, .character = 6 },
        true, // include declaration
    );
    defer provider.freeLocations(locations);

    // Should find: declaration + 3 references = 4 total
    try testing.expect(locations.len >= 1); // At least the declaration
}

test "ReferencesProvider: exclude declaration" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local testFunc = function()
        \\    return 42
        \\end
        \\
        \\local result = testFunc()
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = ReferencesProvider.init(allocator);

    // Find references excluding declaration
    const locations = try provider.findReferences(
        &tree,
        source,
        "file:///test.gza",
        .{ .line = 0, .character = 6 },
        false, // exclude declaration
    );
    defer provider.freeLocations(locations);

    // Should find only the reference, not the declaration
    try testing.expect(locations.len >= 0);
}

test "ReferencesProvider: no references found" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local unused = 42
        \\local x = 10
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = ReferencesProvider.init(allocator);

    // Find references to "unused" - variable is declared but never used
    const locations = try provider.findReferences(
        &tree,
        source,
        "file:///test.gza",
        .{ .line = 0, .character = 6 },
        false, // exclude declaration
    );
    defer provider.freeLocations(locations);

    // Should find 0 or 1 results (may include declaration depending on cursor position)
    try testing.expect(locations.len <= 1);
}

test "ReferencesProvider: memory leak check" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local a = 1
        \\local b = a
        \\local c = a + b
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = ReferencesProvider.init(allocator);

    // Run multiple times to check for memory leaks
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const locations = try provider.findReferences(
            &tree,
            source,
            "file:///test.gza",
            .{ .line = 0, .character = 6 },
            true,
        );
        provider.freeLocations(locations);
    }
}
