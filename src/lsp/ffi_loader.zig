const std = @import("std");

/// FFI Function definition from shell_ffi.json
pub const FFIFunction = struct {
    name: []const u8,
    signature: []const u8,
    description: []const u8,
    parameters: []Parameter,
    returns: Return,
    examples: [][]const u8,

    pub const Parameter = struct {
        name: []const u8,
        type: []const u8,
        description: []const u8,
    };

    pub const Return = struct {
        type: []const u8,
        description: ?[]const u8 = null,
    };

    pub fn deinit(self: *FFIFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.signature);
        allocator.free(self.description);

        for (self.parameters) |param| {
            allocator.free(param.name);
            allocator.free(param.type);
            allocator.free(param.description);
        }
        allocator.free(self.parameters);

        allocator.free(self.returns.type);
        if (self.returns.description) |desc| {
            allocator.free(desc);
        }

        for (self.examples) |example| {
            allocator.free(example);
        }
        allocator.free(self.examples);
    }
};

/// FFI Global variable definition
pub const FFIGlobal = struct {
    name: []const u8,
    type: []const u8,
    description: []const u8,
    readonly: bool,

    pub fn deinit(self: *FFIGlobal, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.type);
        allocator.free(self.description);
    }
};

/// FFI Namespace (e.g., "shell", "git")
pub const FFINamespace = struct {
    name: []const u8,
    description: []const u8,
    functions: std.StringArrayHashMap(FFIFunction),
    globals: std.StringArrayHashMap(FFIGlobal),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, description: []const u8) !FFINamespace {
        return .{
            .name = try allocator.dupe(u8, name),
            .description = try allocator.dupe(u8, description),
            .functions = std.StringArrayHashMap(FFIFunction).init(allocator),
            .globals = std.StringArrayHashMap(FFIGlobal).init(allocator),
        };
    }

    pub fn deinit(self: *FFINamespace, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);

        var func_iter = self.functions.iterator();
        while (func_iter.next()) |entry| {
            var func = entry.value_ptr.*;
            func.deinit(allocator);
        }
        self.functions.deinit();

        var global_iter = self.globals.iterator();
        while (global_iter.next()) |entry| {
            var global = entry.value_ptr.*;
            global.deinit(allocator);
        }
        self.globals.deinit();
    }
};

/// FFI Definitions loader
pub const FFILoader = struct {
    allocator: std.mem.Allocator,
    namespaces: std.StringArrayHashMap(FFINamespace),
    file_associations: std.StringArrayHashMap([][]const u8),

    pub fn init(allocator: std.mem.Allocator) FFILoader {
        return .{
            .allocator = allocator,
            .namespaces = std.StringArrayHashMap(FFINamespace).init(allocator),
            .file_associations = std.StringArrayHashMap([][]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *FFILoader) void {
        var ns_iter = self.namespaces.iterator();
        while (ns_iter.next()) |entry| {
            var ns = entry.value_ptr.*;
            ns.deinit(self.allocator);
        }
        self.namespaces.deinit();

        var assoc_iter = self.file_associations.iterator();
        while (assoc_iter.next()) |entry| {
            for (entry.value_ptr.*) |ext| {
                self.allocator.free(ext);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.file_associations.deinit();
    }

    /// Load FFI definitions from JSON file
    pub fn loadFromFile(self: *FFILoader, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        try self.loadFromJson(content);
    }

    /// Load FFI definitions from embedded JSON
    pub fn loadEmbedded(self: *FFILoader) !void {
        // Load from shell_ffi.json (embedded in binary)
        const ffi_json = @embedFile("shell_ffi.json");
        try self.loadFromJson(ffi_json);
    }

    /// Load FFI definitions from JSON string
    fn loadFromJson(self: *FFILoader, json: []const u8) !void {
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;

        // Load namespaces
        if (root.get("namespaces")) |namespaces_obj| {
            const namespaces = namespaces_obj.object;
            var ns_iter = namespaces.iterator();

            while (ns_iter.next()) |ns_entry| {
                const ns_name = ns_entry.key_ptr.*;
                const ns_obj = ns_entry.value_ptr.*.object;

                const ns_desc = if (ns_obj.get("description")) |d| d.string else "";
                var namespace = try FFINamespace.init(self.allocator, ns_name, ns_desc);

                // Load functions
                if (ns_obj.get("functions")) |funcs_obj| {
                    const funcs = funcs_obj.object;
                    var func_iter = funcs.iterator();

                    while (func_iter.next()) |func_entry| {
                        const func_name = func_entry.key_ptr.*;
                        const func_obj = func_entry.value_ptr.*.object;

                        const func = try self.parseFunctionDefinition(func_name, func_obj);
                        try namespace.functions.put(func.name, func);
                    }
                }

                // Load globals
                if (ns_obj.get("globals")) |globals_obj| {
                    const globals = globals_obj.object;
                    var global_iter = globals.iterator();

                    while (global_iter.next()) |global_entry| {
                        const global_name = global_entry.key_ptr.*;
                        const global_obj = global_entry.value_ptr.*.object;

                        const global = try self.parseGlobalDefinition(global_name, global_obj);
                        try namespace.globals.put(global.name, global);
                    }
                }

                try self.namespaces.put(namespace.name, namespace);
            }
        }

        // Load file associations
        if (root.get("file_associations")) |assoc_obj| {
            const assoc = assoc_obj.object;
            var assoc_iter = assoc.iterator();

            while (assoc_iter.next()) |assoc_entry| {
                const category = assoc_entry.key_ptr.*;
                const extensions_array = assoc_entry.value_ptr.*.array;

                var extensions = try self.allocator.alloc([]const u8, extensions_array.items.len);
                for (extensions_array.items, 0..) |ext_value, i| {
                    extensions[i] = try self.allocator.dupe(u8, ext_value.string);
                }

                try self.file_associations.put(category, extensions);
            }
        }
    }

    fn parseFunctionDefinition(
        self: *FFILoader,
        name: []const u8,
        obj: std.json.ObjectMap,
    ) !FFIFunction {
        const signature = if (obj.get("signature")) |s| s.string else "";
        const description = if (obj.get("description")) |d| d.string else "";

        // Parse parameters
        var params = std.ArrayList(FFIFunction.Parameter){};
        defer params.deinit(self.allocator);

        if (obj.get("parameters")) |params_obj| {
            const params_array = params_obj.array;
            for (params_array.items) |param_value| {
                const param_obj = param_value.object;
                const param_name = if (param_obj.get("name")) |n| n.string else "";
                const param_type = if (param_obj.get("type")) |t| t.string else "";
                const param_desc = if (param_obj.get("description")) |d| d.string else "";

                try params.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, param_name),
                    .type = try self.allocator.dupe(u8, param_type),
                    .description = try self.allocator.dupe(u8, param_desc),
                });
            }
        }

        // Parse return type
        const returns_obj = if (obj.get("returns")) |r| r.object else std.json.ObjectMap.init(self.allocator);
        const return_type = if (returns_obj.get("type")) |t| t.string else "void";
        const return_desc = if (returns_obj.get("description")) |d| d.string else null;

        const returns = FFIFunction.Return{
            .type = try self.allocator.dupe(u8, return_type),
            .description = if (return_desc) |desc| try self.allocator.dupe(u8, desc) else null,
        };

        // Parse examples
        var examples = std.ArrayList([]const u8){};
        defer examples.deinit(self.allocator);

        if (obj.get("examples")) |examples_obj| {
            const examples_array = examples_obj.array;
            for (examples_array.items) |example_value| {
                try examples.append(self.allocator, try self.allocator.dupe(u8, example_value.string));
            }
        }

        return .{
            .name = try self.allocator.dupe(u8, name),
            .signature = try self.allocator.dupe(u8, signature),
            .description = try self.allocator.dupe(u8, description),
            .parameters = try params.toOwnedSlice(self.allocator),
            .returns = returns,
            .examples = try examples.toOwnedSlice(self.allocator),
        };
    }

    fn parseGlobalDefinition(
        self: *FFILoader,
        name: []const u8,
        obj: std.json.ObjectMap,
    ) !FFIGlobal {
        const type_str = if (obj.get("type")) |t| t.string else "any";
        const description = if (obj.get("description")) |d| d.string else "";
        const readonly = if (obj.get("readonly")) |r| r.bool else false;

        return .{
            .name = try self.allocator.dupe(u8, name),
            .type = try self.allocator.dupe(u8, type_str),
            .description = try self.allocator.dupe(u8, description),
            .readonly = readonly,
        };
    }

    /// Get all functions in a namespace
    pub fn getFunctions(self: *const FFILoader, namespace: []const u8) ?*const std.StringArrayHashMap(FFIFunction) {
        const ns = self.namespaces.getPtr(namespace) orelse return null;
        return &ns.functions;
    }

    /// Get all globals in a namespace
    pub fn getGlobals(self: *const FFILoader, namespace: []const u8) ?*const std.StringArrayHashMap(FFIGlobal) {
        const ns = self.namespaces.getPtr(namespace) orelse return null;
        return &ns.globals;
    }

    /// Get a specific function
    pub fn getFunction(self: *const FFILoader, namespace: []const u8, func_name: []const u8) ?*const FFIFunction {
        const ns = self.namespaces.getPtr(namespace) orelse return null;
        return ns.functions.getPtr(func_name);
    }

    /// Get a specific global
    pub fn getGlobal(self: *const FFILoader, namespace: []const u8, global_name: []const u8) ?*const FFIGlobal {
        const ns = self.namespaces.getPtr(namespace) orelse return null;
        return ns.globals.getPtr(global_name);
    }

    /// Check if a file extension is associated with shell scripts
    pub fn isShellFile(self: *const FFILoader, extension: []const u8) bool {
        var assoc_iter = self.file_associations.iterator();
        while (assoc_iter.next()) |entry| {
            for (entry.value_ptr.*) |ext| {
                if (std.mem.eql(u8, ext, extension)) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Get all namespaces
    pub fn getNamespaces(self: *const FFILoader) []const []const u8 {
        return self.namespaces.keys();
    }
};

// Tests
test "FFILoader loads embedded JSON" {
    var loader = FFILoader.init(std.testing.allocator);
    defer loader.deinit();

    try loader.loadEmbedded();

    // Verify shell namespace exists
    const shell_funcs = loader.getFunctions("shell");
    try std.testing.expect(shell_funcs != null);

    // Verify git namespace exists
    const git_funcs = loader.getFunctions("git");
    try std.testing.expect(git_funcs != null);

    // Verify some key functions exist
    const alias_func = loader.getFunction("shell", "alias");
    try std.testing.expect(alias_func != null);
    try std.testing.expectEqualStrings("alias", alias_func.?.name);

    const git_branch_func = loader.getFunction("git", "current_branch");
    try std.testing.expect(git_branch_func != null);
}

test "FFILoader recognizes shell file extensions" {
    var loader = FFILoader.init(std.testing.allocator);
    defer loader.deinit();

    try loader.loadEmbedded();

    try std.testing.expect(loader.isShellFile(".gshrc.gza"));
    try std.testing.expect(loader.isShellFile(".gsh"));
    try std.testing.expect(loader.isShellFile(".gza"));
    try std.testing.expect(!loader.isShellFile(".txt"));
}
