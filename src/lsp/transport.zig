const std = @import("std");
const protocol = @import("protocol.zig");

/// LSP Transport handles reading and writing JSON-RPC messages over stdio
pub const Transport = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
    stderr: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) Transport {
        return .{
            .allocator = allocator,
            .stdin = .{ .handle = std.posix.STDIN_FILENO },
            .stdout = .{ .handle = std.posix.STDOUT_FILENO },
            .stderr = .{ .handle = std.posix.STDERR_FILENO },
        };
    }

    /// Read a JSON-RPC message from stdin
    /// Returns owned slice that caller must free
    pub fn readMessage(self: *Transport) ![]const u8 {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();

        // Read headers
        while (true) {
            const line = try self.readLine();
            defer self.allocator.free(line);

            // Empty line marks end of headers
            if (line.len == 0) break;

            // Parse header (e.g., "Content-Length: 123")
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const key = line[0..colon_pos];
                const value = line[colon_pos + 2 ..];
                try headers.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
            }
        }

        // Get content length
        const content_length_str = headers.get("Content-Length") orelse return error.MissingContentLength;
        const content_length = try std.fmt.parseInt(usize, content_length_str, 10);

        // Free header values
        var it = headers.valueIterator();
        while (it.next()) |value| {
            self.allocator.free(value.*);
        }
        var key_it = headers.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }

        // Read message body
        const message = try self.allocator.alloc(u8, content_length);
        errdefer self.allocator.free(message);

        const bytes_read = try self.stdin.read(message);
        if (bytes_read != content_length) {
            return error.IncompleteMessage;
        }

        return message;
    }

    /// Write a JSON-RPC message to stdout
    pub fn writeMessage(self: *Transport, message: []const u8) !void {
        var buf: [128]u8 = undefined;
        const header = try std.fmt.bufPrint(&buf, "Content-Length: {d}\r\n\r\n", .{message.len});
        _ = try self.stdout.write(header);
        _ = try self.stdout.write(message);
    }

    /// Log a message to stderr (for debugging)
    pub fn log(self: *Transport, comptime fmt: []const u8, args: anytype) void {
        _ = self.stderr.write("[ghostls] ") catch {};
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "[fmt error]";
        _ = self.stderr.write(msg) catch {};
        _ = self.stderr.write("\n") catch {};
    }

    /// Read a line from stdin (helper)
    fn readLine(self: *Transport) ![]const u8 {
        var line: std.ArrayList(u8) = .empty;
        errdefer line.deinit(self.allocator);

        while (true) {
            var byte_buf: [1]u8 = undefined;
            const n = try self.stdin.read(&byte_buf);
            if (n == 0) return error.EndOfStream;

            const byte = byte_buf[0];
            if (byte == '\n') break;
            if (byte == '\r') continue;
            try line.append(self.allocator, byte);
        }

        return try line.toOwnedSlice(self.allocator);
    }
};

/// Response builder helper
pub const ResponseBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ResponseBuilder {
        return .{ .allocator = allocator };
    }

    /// Build a success response
    pub fn success(self: ResponseBuilder, id: protocol.RequestMessage.Id, result: anytype) ![]const u8 {
        const id_str = switch (id) {
            .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
            .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
        };
        defer self.allocator.free(id_str);

        // Serialize result to JSON
        const result_str = if (@TypeOf(result) == @TypeOf(null))
            try self.allocator.dupe(u8, "null")
        else blk: {
            var json_buf: std.ArrayList(u8) = .empty;
            errdefer json_buf.deinit(self.allocator);
            var allocating_writer = std.Io.Writer.Allocating.fromArrayList(self.allocator, &json_buf);
            try std.json.Stringify.value(result, .{}, &allocating_writer.writer);
            break :blk try json_buf.toOwnedSlice(self.allocator);
        };
        defer self.allocator.free(result_str);

        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{s}}}",
            .{ id_str, result_str },
        );
    }

    /// Build an error response
    pub fn @"error"(
        self: ResponseBuilder,
        id: ?protocol.RequestMessage.Id,
        code: i32,
        message: []const u8,
    ) ![]const u8 {
        const id_str = if (id) |i| switch (i) {
            .integer => |n| try std.fmt.allocPrint(self.allocator, "{d}", .{n}),
            .string => |s| try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{s}),
        } else try self.allocator.dupe(u8, "null");
        defer self.allocator.free(id_str);

        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":{d},\"message\":\"{s}\"}}}}",
            .{ id_str, code, message },
        );
    }

    /// Build a notification
    pub fn notification(self: ResponseBuilder, method: []const u8, params: anytype) ![]const u8 {
        _ = params; // Will implement full serialization later
        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"{s}\",\"params\":null}}",
            .{method},
        );
    }
};

/// JSON-RPC error codes
pub const ErrorCodes = struct {
    pub const ParseError: i32 = -32700;
    pub const InvalidRequest: i32 = -32600;
    pub const MethodNotFound: i32 = -32601;
    pub const InvalidParams: i32 = -32602;
    pub const InternalError: i32 = -32603;
    pub const ServerNotInitialized: i32 = -32002;
    pub const UnknownErrorCode: i32 = -32001;
};
