const std = @import("std");
const Server = @import("lsp/server.zig").Server;
const transport = @import("lsp/transport.zig");

const VERSION = "0.3.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stderr = std.fs.File{ .handle = std.posix.STDERR_FILENO };

    // Handle CLI flags
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            _ = try stderr.write("ghostls ");
            _ = try stderr.write(VERSION);
            _ = try stderr.write("\n");
            return;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return;
        } else if (std.mem.startsWith(u8, arg, "--log-level=")) {
            const level_str = arg["--log-level=".len..];
            if (transport.LogLevel.fromString(level_str)) |level| {
                transport.setLogLevel(level);
                _ = try stderr.write("[ghostls] Log level set to: ");
                _ = try stderr.write(level_str);
                _ = try stderr.write("\n");
            } else {
                _ = try stderr.write("Invalid log level: ");
                _ = try stderr.write(level_str);
                _ = try stderr.write("\nValid levels: debug, info, warn, error, silent\n");
                std.process.exit(1);
            }
        } else {
            _ = try stderr.write("Unknown argument: ");
            _ = try stderr.write(arg);
            _ = try stderr.write("\n");
            _ = try stderr.write("Run 'ghostls --help' for usage.\n");
            std.process.exit(1);
        }
    }

    // Start LSP server
    var server = try Server.init(allocator);
    defer server.deinit();

    try server.run();
}

fn printHelp() !void {
    const stderr = std.fs.File{ .handle = std.posix.STDERR_FILENO };
    _ = try stderr.write(
        \\ghostls 0.3.0 - Language Server for Ghostlang
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
