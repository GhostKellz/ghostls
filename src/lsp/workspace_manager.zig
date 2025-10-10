const std = @import("std");
const protocol = @import("protocol.zig");

/// Manages workspace-wide file tracking and project structure
pub const WorkspaceManager = struct {
    allocator: std.mem.Allocator,
    root_uri: ?[]const u8,
    workspace_files: std.StringHashMap(WorkspaceFile),

    pub const WorkspaceFile = struct {
        uri: []const u8,
        path: []const u8,
        is_open: bool,

        pub fn deinit(self: *WorkspaceFile, allocator: std.mem.Allocator) void {
            allocator.free(self.uri);
            allocator.free(self.path);
        }
    };

    pub fn init(allocator: std.mem.Allocator) WorkspaceManager {
        return .{
            .allocator = allocator,
            .root_uri = null,
            .workspace_files = std.StringHashMap(WorkspaceFile).init(allocator),
        };
    }

    pub fn deinit(self: *WorkspaceManager) void {
        if (self.root_uri) |uri| {
            self.allocator.free(uri);
        }

        var it = self.workspace_files.valueIterator();
        while (it.next()) |file| {
            file.deinit(self.allocator);
        }
        self.workspace_files.deinit();
    }

    /// Set workspace root from initialize parameters
    pub fn setRootUri(self: *WorkspaceManager, uri: []const u8) !void {
        if (self.root_uri) |old_uri| {
            self.allocator.free(old_uri);
        }
        self.root_uri = try self.allocator.dupe(u8, uri);
    }

    /// Scan workspace for Ghostlang files (.gza, .ghost)
    pub fn scanWorkspace(self: *WorkspaceManager) !void {
        const root = self.root_uri orelse return;

        // Convert file:// URI to filesystem path
        const path = try self.uriToPath(root);
        defer self.allocator.free(path);

        // Recursively scan directory for .gza and .ghost files
        try self.scanDirectory(path);
    }

    /// Convert file:// URI to filesystem path
    fn uriToPath(self: *WorkspaceManager, uri: []const u8) ![]const u8 {
        if (std.mem.startsWith(u8, uri, "file://")) {
            const path_part = uri[7..]; // Skip "file://"
            return try self.allocator.dupe(u8, path_part);
        }
        return try self.allocator.dupe(u8, uri);
    }

    /// Recursively scan directory for Ghostlang files
    fn scanDirectory(self: *WorkspaceManager, dir_path: []const u8) !void {
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch |err| {
            std.log.err("Failed to open directory {s}: {}", .{ dir_path, err });
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                // Skip hidden directories and common ignore patterns
                if (std.mem.startsWith(u8, entry.name, ".")) continue;
                if (std.mem.eql(u8, entry.name, "node_modules")) continue;
                if (std.mem.eql(u8, entry.name, "zig-cache")) continue;
                if (std.mem.eql(u8, entry.name, "zig-out")) continue;

                // Recursively scan subdirectory
                const subdir_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
                defer self.allocator.free(subdir_path);
                try self.scanDirectory(subdir_path);
            } else if (entry.kind == .file) {
                // Check for .gza or .ghost extension
                if (std.mem.endsWith(u8, entry.name, ".gza") or std.mem.endsWith(u8, entry.name, ".ghost")) {
                    const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
                    errdefer self.allocator.free(file_path);

                    const file_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{file_path});
                    errdefer self.allocator.free(file_uri);

                    const workspace_file = WorkspaceFile{
                        .uri = file_uri,
                        .path = file_path,
                        .is_open = false,
                    };

                    try self.workspace_files.put(file_uri, workspace_file);
                }
            }
        }
    }

    /// Mark a file as open
    pub fn markFileOpen(self: *WorkspaceManager, uri: []const u8) !void {
        if (self.workspace_files.getPtr(uri)) |file| {
            file.is_open = true;
        } else {
            // File not in workspace scan, add it dynamically
            const file_uri = try self.allocator.dupe(u8, uri);
            errdefer self.allocator.free(file_uri);

            const path = try self.uriToPath(uri);
            errdefer self.allocator.free(path);

            const workspace_file = WorkspaceFile{
                .uri = file_uri,
                .path = path,
                .is_open = true,
            };

            try self.workspace_files.put(file_uri, workspace_file);
        }
    }

    /// Mark a file as closed
    pub fn markFileClosed(self: *WorkspaceManager, uri: []const u8) void {
        if (self.workspace_files.getPtr(uri)) |file| {
            file.is_open = false;
        }
    }

    /// Get all workspace file URIs
    pub fn getAllFileUris(self: *WorkspaceManager) ![][]const u8 {
        var uris = std.ArrayList([]const u8).init(self.allocator);
        defer uris.deinit();

        var it = self.workspace_files.keyIterator();
        while (it.next()) |uri| {
            try uris.append(uri.*);
        }

        return try uris.toOwnedSlice();
    }
};
