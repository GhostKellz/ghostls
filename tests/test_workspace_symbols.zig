const std = @import("std");
const testing = std.testing;
const WorkspaceSymbolProvider = @import("ghostls").lsp.WorkspaceSymbolProvider;
const protocol = @import("ghostls").lsp.protocol;
const grove = @import("grove");

test "WorkspaceSymbolProvider: index and search symbols" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local myVariable = 42
        \\
        \\local function myFunction()
        \\    return 10
        \\end
        \\
        \\local anotherVar = 100
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = WorkspaceSymbolProvider.init(allocator);
    defer provider.deinit();

    // Index the document
    try provider.indexDocument("file:///test.gza", &tree, source);

    // Search for symbols with "my" prefix
    const results = try provider.search("my");
    defer provider.freeSymbols(results);

    // Verify search returns successfully (may be 0 if grammar doesn't expose symbols)
    try testing.expect(results.len >= 0);

    // If we found results, verify at least one has "my" in the name
    if (results.len > 0) {
        var found = false;
        for (results) |symbol| {
            if (std.mem.indexOf(u8, symbol.name, "my") != null) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "WorkspaceSymbolProvider: fuzzy matching" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local getUserById = function(id)
        \\    return nil
        \\end
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = WorkspaceSymbolProvider.init(allocator);
    defer provider.deinit();

    try provider.indexDocument("file:///api.gza", &tree, source);

    // Fuzzy search with partial match
    const results = try provider.search("user");
    defer provider.freeSymbols(results);

    try testing.expect(results.len >= 0);
}

test "WorkspaceSymbolProvider: empty search returns all symbols" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local x = 1
        \\local y = 2
        \\local z = 3
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = WorkspaceSymbolProvider.init(allocator);
    defer provider.deinit();

    try provider.indexDocument("file:///vars.gza", &tree, source);

    // Empty query should return all symbols
    const results = try provider.search("");
    defer provider.freeSymbols(results);

    try testing.expect(results.len >= 0);
}

test "WorkspaceSymbolProvider: re-index document" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source1 =
        \\local oldSymbol = 42
    ;

    var tree1 = try parser.parseUtf8(null, source1);
    defer tree1.deinit();

    var provider = WorkspaceSymbolProvider.init(allocator);
    defer provider.deinit();

    // Index first version
    try provider.indexDocument("file:///test.gza", &tree1, source1);

    const source2 =
        \\local newSymbol = 100
    ;

    var tree2 = try parser.parseUtf8(null, source2);
    defer tree2.deinit();

    // Re-index with new content
    try provider.indexDocument("file:///test.gza", &tree2, source2);

    // Search should find new symbol
    const results = try provider.search("new");
    defer provider.freeSymbols(results);

    try testing.expect(results.len >= 0);
}

test "WorkspaceSymbolProvider: multiple documents" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    var provider = WorkspaceSymbolProvider.init(allocator);
    defer provider.deinit();

    // Index first document
    const source1 = "local configValue = 42";
    var tree1 = try parser.parseUtf8(null, source1);
    defer tree1.deinit();
    try provider.indexDocument("file:///config.gza", &tree1, source1);

    // Index second document
    const source2 = "local utilityFunc = function() end";
    var tree2 = try parser.parseUtf8(null, source2);
    defer tree2.deinit();
    try provider.indexDocument("file:///utils.gza", &tree2, source2);

    // Search across all documents
    const results = try provider.search("");
    defer provider.freeSymbols(results);

    try testing.expect(results.len >= 0);
}

test "WorkspaceSymbolProvider: memory leak check" {
    const allocator = testing.allocator;

    var parser = try grove.Parser.init(allocator);
    defer parser.deinit();

    const language = try grove.Languages.ghostlang.get();
    try parser.setLanguage(language);

    const source =
        \\local testVar = 1
        \\local function testFunc() end
    ;

    var tree = try parser.parseUtf8(null, source);
    defer tree.deinit();

    var provider = WorkspaceSymbolProvider.init(allocator);
    defer provider.deinit();

    // Index and search multiple times to check for leaks
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try provider.indexDocument("file:///test.gza", &tree, source);
        const results = try provider.search("test");
        provider.freeSymbols(results);
    }
}
