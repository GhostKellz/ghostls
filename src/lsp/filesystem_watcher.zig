const std = @import("std");

/// Watches filesystem for changes to Ghostlang files
pub const FilesystemWatcher = struct {
    allocator: std.mem.Allocator,
    watch_patterns: std.ArrayList(WatchPattern),
    watched_files: std.StringHashMap(FileInfo),

    pub const WatchPattern = struct {
        glob_pattern: []const u8,
        kind: WatchKind,
    };

    pub const WatchKind = enum(u32) {
        create = 1,
        change = 2,
        delete = 4,
        all = 7, // create | change | delete
    };

    pub const FileInfo = struct {
        path: []const u8,
        last_modified: i128, // Unix timestamp in nanoseconds

        pub fn deinit(self: *FileInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.path);
        }
    };

    pub const FileChangeEvent = struct {
        uri: []const u8,
        change_type: ChangeType,
    };

    pub const ChangeType = enum {
        created,
        changed,
        deleted,
    };

    pub fn init(allocator: std.mem.Allocator) FilesystemWatcher {
        return .{
            .allocator = allocator,
            .watch_patterns = std.ArrayList(WatchPattern).init(allocator),
            .watched_files = std.StringHashMap(FileInfo).init(allocator),
        };
    }

    pub fn deinit(self: *FilesystemWatcher) void {
        for (self.watch_patterns.items) |*pattern| {
            self.allocator.free(pattern.glob_pattern);
        }
        self.watch_patterns.deinit();

        var it = self.watched_files.valueIterator();
        while (it.next()) |info| {
            info.deinit(self.allocator);
        }
        self.watched_files.deinit();
    }

    /// Add a watch pattern
    pub fn addWatchPattern(
        self: *FilesystemWatcher,
        glob_pattern: []const u8,
        kind: WatchKind,
    ) !void {
        const pattern_copy = try self.allocator.dupe(u8, glob_pattern);
        try self.watch_patterns.append(.{
            .glob_pattern = pattern_copy,
            .kind = kind,
        });
    }

    /// Register a file for watching
    pub fn watchFile(self: *FilesystemWatcher, uri: []const u8, path: []const u8) !void {
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            std.log.warn("Failed to open file for watching: {s} - {}", .{ path, err });
            return;
        };
        defer file.close();

        const stat = file.stat() catch |err| {
            std.log.warn("Failed to stat file: {s} - {}", .{ path, err });
            return;
        };

        const uri_copy = try self.allocator.dupe(u8, uri);
        const path_copy = try self.allocator.dupe(u8, path);

        try self.watched_files.put(uri_copy, .{
            .path = path_copy,
            .last_modified = stat.mtime,
        });
    }

    /// Check for file changes
    pub fn checkForChanges(self: *FilesystemWatcher) ![]FileChangeEvent {
        var events = std.ArrayList(FileChangeEvent).init(self.allocator);
        errdefer {
            for (events.items) |*event| {
                self.allocator.free(event.uri);
            }
            events.deinit();
        }

        var it = self.watched_files.iterator();
        while (it.next()) |entry| {
            const uri = entry.key_ptr.*;
            const info = entry.value_ptr;

            // Check if file still exists
            const file = std.fs.openFileAbsolute(info.path, .{}) catch {
                // File was deleted
                const uri_copy = try self.allocator.dupe(u8, uri);
                try events.append(.{
                    .uri = uri_copy,
                    .change_type = .deleted,
                });
                continue;
            };
            defer file.close();

            const stat = file.stat() catch continue;

            // Check if file was modified
            if (stat.mtime > info.last_modified) {
                info.last_modified = stat.mtime;

                const uri_copy = try self.allocator.dupe(u8, uri);
                try events.append(.{
                    .uri = uri_copy,
                    .change_type = .changed,
                });
            }
        }

        return try events.toOwnedSlice();
    }

    pub fn freeEvents(self: *FilesystemWatcher, events: []FileChangeEvent) void {
        for (events) |*event| {
            self.allocator.free(event.uri);
        }
        self.allocator.free(events);
    }
};
