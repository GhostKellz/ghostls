const std = @import("std");
const Server = @import("lsp/server.zig").Server;
const transport = @import("lsp/transport.zig");

const VERSION = "0.6.2";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Parse command-line arguments
    var args_iter = init.minimal.args.iterate();
    _ = args_iter.next(); // Skip program name

    // Set up stderr writer
    const stderr_file = std.Io.File.stderr();
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.Writer.initStreaming(stderr_file, io, &stderr_buffer);
    const w = &stderr_writer.interface;

    // Handle CLI flags
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try w.print("ghostls {s}\n", .{VERSION});
            try w.flush();
            return;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w);
            try w.flush();
            return;
        } else if (std.mem.startsWith(u8, arg, "--log-level=")) {
            const level_str = arg["--log-level=".len..];
            if (transport.LogLevel.fromString(level_str)) |level| {
                transport.setLogLevel(level);
                try w.print("[ghostls] Log level set to: {s}\n", .{level_str});
            } else {
                try w.print("Invalid log level: {s}\nValid levels: debug, info, warn, error, silent\n", .{level_str});
                std.process.exit(1);
            }
        } else {
            try w.print("Unknown argument: {s}\nRun 'ghostls --help' for usage.\n", .{arg});
            std.process.exit(1);
        }
    }

    // Start LSP server
    var server = try Server.init(allocator, io);
    defer server.deinit();

    try server.run();
}

fn printHelp(w: *std.Io.Writer) !void {
    try w.writeAll(
        \\ghostls 0.6.2 - Language Server for Ghostlang
        \\
        \\USAGE:
        \\    ghostls [OPTIONS]
        \\
        \\OPTIONS:
        \\    -h, --help              Show this help message
        \\    -v, --version           Show version information
        \\    --log-level=LEVEL       Set log level (debug|info|warn|error|silent)
        \\
        \\DESCRIPTION:
        \\    ghostls is a Language Server Protocol (LSP) server for the Ghostlang
        \\    programming language. It provides code intelligence features such as:
        \\    - Syntax diagnostics
        \\    - Hover documentation
        \\    - Go to definition
        \\    - Auto-completion
        \\    - Document symbols
        \\
        \\    The server communicates via JSON-RPC over stdin/stdout.
        \\    All logging output goes to stderr (not stdout).
        \\
        \\INTEGRATION:
        \\    - Grim:   Auto-detected when opening .gza files
        \\    - Neovim: Configure via nvim-lspconfig
        \\    - VSCode: Install ghostls extension (coming soon)
        \\
        \\EXAMPLES:
        \\    # Start server (used by editors, not run manually)
        \\    ghostls
        \\
        \\    # Check version
        \\    ghostls --version
        \\
        \\    # Show help
        \\    ghostls --help
        \\
        \\PROJECT:
        \\    GitHub:  https://github.com/ghostkellz/ghostls
        \\    Docs:    https://github.com/ghostkellz/ghostls/tree/main/docs
        \\
        \\
    );
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
