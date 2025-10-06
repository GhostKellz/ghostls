# ghostls v0.2.0 Development Progress

**Target:** Smart Intelligence Release
**Started:** 2025-10-06
**Status:** In Progress

---

## ✅ Completed

### 1. Context-Aware Completions (Partially)
- ✅ Created context analysis system
- ✅ Added trigger character detection (`.`, `:`)
- ✅ Implemented scope-based filtering
- ✅ Added object method completions
- ✅ Local variable collection
- ⚠️ **NEEDS FIX:** Grove API compatibility (`descendantForPointRange` vs `descendantForByteRange`)

**File:** `src/lsp/completion_provider.zig`

### 2. References Provider
- ✅ Created `ReferencesProvider`
- ✅ Symbol name extraction
- ✅ Tree traversal for references
- ✅ Declaration vs usage detection
- ⚠️ **NEEDS:** Integration into server.zig handlers

**File:** `src/lsp/references_provider.zig`

### 3. Workspace Symbols
- ✅ Created `WorkspaceSymbolProvider`
- ✅ Symbol indexing system
- ✅ Fuzzy search implementation
- ✅ Cross-file symbol tracking
- ⚠️ **NEEDS:** Integration into server.zig handlers

**File:** `src/lsp/workspace_symbol_provider.zig`

### 4. Protocol Extensions
- ✅ Added `SymbolInformation` to protocol.zig

---

## ⚠️ In Progress / Needs Completion

### 1. Fix Grove API Compatibility
**Issue:** Using wrong API method name
```zig
// WRONG:
const node = root.descendantForByteRange(offset, offset);

// CORRECT (from Grove source):
const node = root.descendantForPointRange(point, point);
```

**Action Required:**
- Convert byte offsets to Point (line/column)
- Update all tree-sitter API calls
- Test with real Ghostlang files

---

### 2. Server Integration
**Files to Update:** `src/lsp/server.zig`

#### Add Method Handlers

**a) `textDocument/references`**
```zig
// Add to handleMessage routing (around line 130)
} else if (std.mem.eql(u8, method_str, protocol.Methods.text_document_references)) {
    const id = maybe_id orelse return error.InvalidRequest;
    return try self.handleReferences(id, obj.get("params"));
}

// Add handler method
fn handleReferences(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
    if (params) |p| {
        const text_document = p.object.get("textDocument") orelse return error.InvalidParams;
        const uri = text_document.object.get("uri") orelse return error.InvalidParams;
        const position = p.object.get("position") orelse return error.InvalidParams;

        const line = @as(u32, @intCast(position.object.get("line").?.integer));
        const character = @as(u32, @intCast(position.object.get("character").?.integer));

        const doc = self.document_manager.get(uri.string) orelse {
            return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
        };

        if (doc.tree) |*tree| {
            const locations = try self.references_provider.findReferences(
                tree,
                doc.text,
                uri.string,
                .{ .line = line, .character = character },
                true, // include declaration
            );
            defer self.references_provider.freeLocations(locations);

            // Build JSON response
            // TODO: Implement JSON serialization
        }
    }

    return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
}
```

**b) `workspace/symbol`**
```zig
// Add to handleMessage routing
} else if (std.mem.eql(u8, method_str, protocol.Methods.workspace_symbol)) {
    const id = maybe_id orelse return error.InvalidRequest;
    return try self.handleWorkspaceSymbol(id, obj.get("params"));
}

// Add handler method
fn handleWorkspaceSymbol(self: *Server, id: std.json.Value, params: ?std.json.Value) ![]const u8 {
    const query = if (params) |p|
        if (p.object.get("query")) |q| q.string else ""
    else
        "";

    const symbols = try self.workspace_symbol_provider.search(query);
    defer self.workspace_symbol_provider.freeSymbols(symbols);

    // Build JSON response
    // TODO: Implement JSON serialization

    return try self.response_builder.success(self.jsonIdToProtocolId(id), null);
}
```

**c) Update `handleDidOpen` to index symbols**
```zig
fn handleDidOpen(self: *Server, params: ?std.json.Value) !?[]const u8 {
    // ... existing code ...

    // Index symbols for workspace search
    if (doc.tree) |*tree| {
        try self.workspace_symbol_provider.indexDocument(uri, tree, text);
    }

    // ... rest of existing code ...
}
```

---

### 3. Update Server Capabilities
**File:** `src/lsp/server.zig`, `handleInitialize` method

Add to capabilities JSON:
```zig
"referencesProvider":true,
"workspaceSymbolProvider":true
```

Current (line ~155):
```zig
\\{{"positionEncoding":"utf-16","textDocumentSync":{{"openClose":true,"change":1,"save":{{"includeText":true}}}},"hoverProvider":true,"completionProvider":{{"triggerCharacters":[".",":"]}},"definitionProvider":true,"referencesProvider":false,"documentSymbolProvider":true}}
```

Should be:
```zig
\\{{"positionEncoding":"utf-16","textDocumentSync":{{"openClose":true,"change":1,"save":{{"includeText":true}}}},"hoverProvider":true,"completionProvider":{{"triggerCharacters":[".",":"]}},"definitionProvider":true,"referencesProvider":true,"workspaceSymbolProvider":true,"documentSymbolProvider":true}}
```

---

### 4. Protocol Methods Constants
**File:** `src/lsp/protocol.zig`

Add missing method constants:
```zig
pub const Methods = struct {
    // ... existing methods ...
    pub const text_document_references = "textDocument/references";
    pub const workspace_symbol = "workspace/symbol";
};
```

---

## 🚀 Testing Plan

### 1. Context-Aware Completions
```gza
// Test file: test_completions.gza

// Test 1: After dot (should show methods)
local arr = createArray()
arr.|  ← Should suggest: push, pop, length, etc.

// Test 2: Inside function (should show local vars + builtins)
function test()
    local myVar = 42
    local result = my|  ← Should suggest: myVar
end

// Test 3: Top-level (should show keywords + builtins)
|  ← Should suggest: function, var, local, createArray, etc.
```

### 2. Find References
```gza
// Test file: test_references.gza

local myFunction = function()
    return 42
end

local x = myFunction()  -- Reference 1
local y = myFunction()  -- Reference 2

-- Place cursor on 'myFunction' and request references
-- Should find: declaration + 2 references
```

### 3. Workspace Symbols
```bash
# Test: Search for "test" across workspace
# Should find all functions/variables with "test" in name
```

---

## 📋 TODO Before Release

- [ ] Fix Grove API compatibility issues
- [ ] Add textDocument/references handler
- [ ] Add workspace/symbol handler
- [ ] Update server capabilities
- [ ] Add protocol method constants
- [ ] Write unit tests
- [ ] Update CHANGELOG.md
- [ ] Update README.md with new features
- [ ] Test with Grim integration
- [ ] Bump version to 0.2.0

---

## 🎯 v0.2.0 Goals (Revised)

### Must Have
1. ✅ Context-aware completions (trigger character filtering)
2. ✅ Find references (textDocument/references)
3. ✅ Workspace symbols (workspace/symbol)

### Nice to Have (v0.3.0)
- Incremental document sync
- Cross-file goto definition
- Semantic tokens
- Code actions
- Signature help

---

## 📝 Notes

- Grove uses `Point` (line, column) not byte offsets
- Need helper function to convert LSP Position → Grove Point
- All new providers are created but need server.zig integration
- Focus on getting v0.2.0 working, then iterate

---

**Next Session:** Complete server.zig integration and test
