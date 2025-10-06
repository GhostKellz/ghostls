# Grim Editor Integration for ghostls

This directory contains integration for **ghostls** with **Grim** editor.

## Overview

Grim is a Neovim-alternative editor built in Zig and Ghostlang. It has native LSP support and will integrate directly with ghostls for `.gza` files.

## Integration Status

**Current**: Grim has basic LSP client (`lsp/client.zig`) with initialize + diagnostics working.

**Ready**: ghostls supports all features needed by Grim (didOpen, didChange, didSave, completions, hover, definitions, symbols)

**Needed**: Grim client needs to add completion/hover/definition request methods (see below)

## Grim LSP Client Implementation Required

### What Grim Already Has ✅

From `archive/grim/lsp/client.zig`:
- ✅ JSON-RPC framing (Content-Length headers)
- ✅ `sendInitialize()` - LSP handshake
- ✅ `poll()` - Read and dispatch messages
- ✅ `handlePayload()` - Parse JSON-RPC
- ✅ Diagnostics sink for `publishDiagnostics`
- ✅ Transport abstraction (stdio)

### What Grim Needs to Add ⚠️

**File: `lsp/client.zig` - Add these methods:**

```zig
// 1. Send didSave notification
pub fn sendDidSave(self: *Client, uri: []const u8, text: ?[]const u8) Error!void {
    const Params = struct {
        textDocument: struct { uri: []const u8 },
        text: ?[]const u8 = null,
    };

    const notification = .{
        .jsonrpc = "2.0",
        .method = "textDocument/didSave",
        .params = Params{
            .textDocument = .{ .uri = uri },
            .text = text,
        },
    };

    const body = try std.json.stringifyAlloc(self.allocator, notification, .{});
    defer self.allocator.free(body);
    try self.writeMessage(body);
}

// 2. Request completion
pub fn requestCompletion(
    self: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
) Error!u32 {
    const id = self.next_id;
    self.next_id += 1;

    const Params = struct {
        textDocument: struct { uri: []const u8 },
        position: struct { line: u32, character: u32 },
    };

    const request = .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/completion",
        .params = Params{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        },
    };

    const body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(body);
    try self.writeMessage(body);

    return id; // Caller matches this ID in handlePayload
}

// 3. Request hover
pub fn requestHover(
    self: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
) Error!u32 {
    const id = self.next_id;
    self.next_id += 1;

    const request = .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/hover",
        .params = .{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        },
    };

    const body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(body);
    try self.writeMessage(body);

    return id;
}

// 4. Request definition
pub fn requestDefinition(
    self: *Client,
    uri: []const u8,
    line: u32,
    character: u32,
) Error!u32 {
    const id = self.next_id;
    self.next_id += 1;

    const request = .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/definition",
        .params = .{
            .textDocument = .{ .uri = uri },
            .position = .{ .line = line, .character = character },
        },
    };

    const body = try std.json.stringifyAlloc(self.allocator, request, .{});
    defer self.allocator.free(body);
    try self.writeMessage(body);

    return id;
}
```

**File: `lsp/server_manager.zig` - NEW FILE NEEDED:**

```zig
const std = @import("std");
const Client = @import("client.zig").Client;

pub const ServerManager = struct {
    allocator: std.mem.Allocator,
    servers: std.StringHashMap(*ServerProcess),

    pub const ServerProcess = struct {
        process: std.process.Child,
        client: Client,
        name: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) ServerManager {
        return .{
            .allocator = allocator,
            .servers = std.StringHashMap(*ServerProcess).init(allocator),
        };
    }

    pub fn deinit(self: *ServerManager) void {
        var it = self.servers.iterator();
        while (it.next()) |entry| {
            self.shutdownServer(entry.value_ptr.*) catch {};
        }
        self.servers.deinit();
    }

    pub fn spawn(self: *ServerManager, name: []const u8, cmd: []const []const u8) !*ServerProcess {
        var process = std.process.Child.init(cmd, self.allocator);
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Inherit;

        try process.spawn();

        const transport = Transport{
            .ctx = &process,
            .readFn = processRead,
            .writeFn = processWrite,
        };

        const client = Client.init(self.allocator, transport);

        const server = try self.allocator.create(ServerProcess);
        server.* = .{
            .process = process,
            .client = client,
            .name = try self.allocator.dupe(u8, name),
        };

        try self.servers.put(name, server);
        return server;
    }

    // Helper functions for process I/O
    fn processRead(ctx: *anyopaque, buffer: []u8) !usize {
        const process: *std.process.Child = @ptrCast(@alignCast(ctx));
        return process.stdout.?.read(buffer);
    }

    fn processWrite(ctx: *anyopaque, buffer: []const u8) !usize {
        const process: *std.process.Child = @ptrCast(@alignCast(ctx));
        return process.stdin.?.write(buffer);
    }
};
```

## Planned Integration

### Native LSP Client

Grim's LSP client (in `lsp/client.zig`) will spawn and communicate with ghostls:

```zig
// Grim will use:
const ghostls_dep = b.dependency("ghostls", .{
    .target = target,
    .optimize = optimize,
});
```

### Plugin Support

Grim plugins written in `.gza` will have full LSP support via ghostls:

- **Completions** - Autocomplete for editor APIs
- **Hover** - Documentation for `getCurrentLine()`, `insertText()`, etc.
- **Diagnostics** - Real-time syntax checking
- **Navigation** - Jump to plugin function definitions

### Auto-spawn

Grim will automatically spawn ghostls when opening `.gza` files:

```zig
// src/lsp/manager.zig (planned)
pub fn ensureGhostLS(allocator: Allocator) !*Process {
    const exe_path = try findExecutable(allocator, "ghostls");
    return try spawn(allocator, &.{exe_path}, .{
        .stdin = .Pipe,
        .stdout = .Pipe,
        .stderr = .Inherit,
    });
}
```

## Building for Grim

From the Grim repository:

```bash
# Add ghostls as dependency
zig fetch --save https://github.com/ghostkellz/ghostls/archive/refs/heads/main.tar.gz

# Grim's build.zig will handle the rest
zig build run
```

## Features for Grim Users

When editing Grim plugins (`.gza` files):

✅ **Real-time validation** - Catch errors as you type
✅ **Smart completions** - All 44+ editor API functions
✅ **Quick docs** - Hover over `notify()` to see usage
✅ **Symbol navigation** - Jump between plugin functions
✅ **Workspace support** - Multi-file plugin projects

## Example Grim Plugin with LSP

```gza
-- ~/.config/grim/plugins/hello.gza

function on_startup()
    notify("Grim started!")
    -- ^ LSP shows: function notify(message: string)
    --   Hover to see documentation
end

function insert_date()
    local line = getCurrentLine()
    --         ^ LSP autocompletes: getCurrentLine()
    local text = os.date("%Y-%m-%d")
    insertText(text)
end

-- LSP shows these as document symbols in outline view
```

## Status

- [ ] Grim LSP client implementation
- [ ] Auto-spawn ghostls for .gza files
- [ ] Plugin API documentation integration
- [ ] Debugging support for plugins

## Links

- Grim: https://github.com/ghostkellz/grim
- ghostls: https://github.com/ghostkellz/ghostls
- Grove (Tree-sitter): https://github.com/ghostkellz/grove
- Ghostlang: https://github.com/ghostkellz/ghostlang
