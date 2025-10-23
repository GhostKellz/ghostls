const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");
const ffi_loader = @import("ffi_loader.zig");

/// HoverProvider provides hover information for positions in the document
pub const HoverProvider = struct {
    allocator: std.mem.Allocator,
    ffi_loader: *ffi_loader.FFILoader,

    pub fn init(allocator: std.mem.Allocator, ffi: *ffi_loader.FFILoader) HoverProvider {
        return .{ .allocator = allocator, .ffi_loader = ffi };
    }

    /// Get hover information for a position in the document
    pub fn hover(
        self: *HoverProvider,
        tree: *const grove.Tree,
        text: []const u8,
        position: protocol.Position,
        supports_shell_ffi: bool,
    ) !?protocol.Hover {
        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the smallest node at the given position
        const node_opt = self.findNodeAtPosition(root, position);
        if (node_opt == null) return null;

        const node = node_opt.?;
        const kind = node.kind();

        // Get the text of the node
        const start_byte = node.startByte();
        const end_byte = node.endByte();
        const node_text = if (end_byte > start_byte and end_byte <= text.len)
            text[start_byte..end_byte]
        else
            "";

        // Build hover content based on node kind
        const hover_text = try self.buildHoverContent(kind, node_text, node, text, supports_shell_ffi);

        return protocol.Hover{
            .contents = .{
                .kind = "markdown",
                .value = hover_text,
            },
            .range = nodeToRange(node),
        };
    }

    /// Find the smallest node that contains the position
    fn findNodeAtPosition(
        self: *HoverProvider,
        node: grove.Node,
        position: protocol.Position,
    ) ?grove.Node {
        const start_pos = node.startPosition();
        const end_pos = node.endPosition();

        // Check if position is within this node's range
        if (!positionInRange(position, start_pos, end_pos)) {
            return null;
        }

        // Check children for a more specific match
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                const child_start = child.startPosition();
                const child_end = child.endPosition();

                if (positionInRange(position, child_start, child_end)) {
                    // Recursively check if a child has a more specific match
                    if (self.findNodeAtPosition(child, position)) |found| {
                        return found;
                    }
                    return child;
                }
            }
        }

        // No child matched, return this node
        return node;
    }

    /// Build hover content based on node kind
    fn buildHoverContent(
        self: *HoverProvider,
        kind: []const u8,
        node_text: []const u8,
        node: grove.Node,
        full_text: []const u8,
        supports_shell_ffi: bool,
    ) ![]const u8 {
        // Check for FFI functions/globals first (if in GShell file)
        if (supports_shell_ffi and std.mem.eql(u8, kind, "identifier")) {
            // Check if this is part of a member expression (shell.alias, git.current_branch, etc.)
            if (node.parent()) |parent| {
                const parent_kind = parent.kind();

                // Check for field access (shell.alias or git.current_branch)
                if (std.mem.eql(u8, parent_kind, "field") or
                    std.mem.eql(u8, parent_kind, "dot_index_expression") or
                    std.mem.eql(u8, parent_kind, "index_expression") or
                    std.mem.eql(u8, parent_kind, "member_expression") or
                    std.mem.eql(u8, parent_kind, "property_identifier")) {

                    // Try to find the namespace (shell or git)
                    const namespace = try self.detectFFINamespace(parent, full_text);

                    if (namespace) |ns| {
                        // Check if this identifier is an FFI function
                        if (self.ffi_loader.getFunction(ns, node_text)) |func| {
                            return try self.formatFFIFunctionHover(func);
                        }
                    }
                }
            }

            // Check if it's a shell global variable (SHELL_VERSION, HOME, etc.)
            if (self.ffi_loader.getGlobal("shell", node_text)) |global| {
                return try self.formatFFIGlobalHover(global);
            }
        }

        // Check for builtin functions (v0.2.0 stdlib)
        if (std.mem.eql(u8, kind, "identifier")) {
            if (try self.getBuiltinHover(node_text)) |builtin_hover| {
                return builtin_hover;
            }
        }

        // Check for common Ghostlang constructs
        if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "function")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Function Declaration**\n\n```ghostlang\n{s}\n```",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "variable_declaration") or
                   std.mem.eql(u8, kind, "let_declaration")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Variable Declaration**\n\n```ghostlang\n{s}\n```",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "identifier")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Identifier**: `{s}`\n\nType: _{s}_",
                .{node_text, kind},
            );
        } else if (std.mem.eql(u8, kind, "type_identifier") or
                   std.mem.eql(u8, kind, "type")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Type**: `{s}`",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "string") or
                   std.mem.eql(u8, kind, "string_literal")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**String Literal**\n\n```\n{s}\n```",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "number") or
                   std.mem.eql(u8, kind, "number_literal") or
                   std.mem.eql(u8, kind, "integer")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Number Literal**: `{s}`",
                .{node_text},
            );
        } else if (std.mem.eql(u8, kind, "comment")) {
            return try std.fmt.allocPrint(
                self.allocator,
                "**Comment**\n\n> {s}",
                .{node_text},
            );
        }

        // Default hover with node info
        return try std.fmt.allocPrint(
            self.allocator,
            "**Node**: `{s}`\n\n```\n{s}\n```",
            .{kind, node_text},
        );
    }

    /// Detect FFI namespace (shell or git) from a parent node
    fn detectFFINamespace(
        self: *HoverProvider,
        parent: grove.Node,
        text: []const u8,
    ) !?[]const u8 {
        _ = self;

        // For member_expression nodes, the object is the first child
        // Look at parent's children to find the namespace identifier
        const child_count = parent.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (parent.child(i)) |child| {
                const kind = child.kind();
                if (std.mem.eql(u8, kind, "identifier")) {
                    const start = child.startByte();
                    const end = child.endByte();
                    if (end > start and end <= text.len) {
                        const name = text[start..end];
                        // Return string literals for known namespaces (safer for lifetime)
                        if (std.mem.eql(u8, name, "shell")) {
                            return "shell";
                        } else if (std.mem.eql(u8, name, "git")) {
                            return "git";
                        }
                    }
                }
            }
        }
        return null;
    }

    /// Format hover text for an FFI function
    fn formatFFIFunctionHover(
        self: *HoverProvider,
        func: *const ffi_loader.FFIFunction,
    ) ![]const u8 {
        // Build markdown documentation
        var doc = std.ArrayList(u8){};
        defer doc.deinit(self.allocator);

        // Function signature
        try doc.appendSlice(self.allocator, "**FFI Function**\n\n```lua\n");
        try doc.appendSlice(self.allocator, func.signature);
        try doc.appendSlice(self.allocator, "\n```\n\n");

        // Description
        try doc.appendSlice(self.allocator, func.description);
        try doc.appendSlice(self.allocator, "\n\n");

        // Parameters
        if (func.parameters.len > 0) {
            try doc.appendSlice(self.allocator, "**Parameters:**\n");
            for (func.parameters) |param| {
                try doc.appendSlice(self.allocator, "- `");
                try doc.appendSlice(self.allocator, param.name);
                try doc.appendSlice(self.allocator, "` (");
                try doc.appendSlice(self.allocator, param.type);
                try doc.appendSlice(self.allocator, "): ");
                try doc.appendSlice(self.allocator, param.description);
                try doc.appendSlice(self.allocator, "\n");
            }
            try doc.appendSlice(self.allocator, "\n");
        }

        // Return type
        try doc.appendSlice(self.allocator, "**Returns:** `");
        try doc.appendSlice(self.allocator, func.returns.type);
        try doc.appendSlice(self.allocator, "`");
        if (func.returns.description) |desc| {
            try doc.appendSlice(self.allocator, " - ");
            try doc.appendSlice(self.allocator, desc);
        }
        try doc.appendSlice(self.allocator, "\n\n");

        // Examples
        if (func.examples.len > 0) {
            try doc.appendSlice(self.allocator, "**Example:**\n```lua\n");
            try doc.appendSlice(self.allocator, func.examples[0]);
            try doc.appendSlice(self.allocator, "\n```\n");
        }

        return try doc.toOwnedSlice(self.allocator);
    }

    /// Format hover text for an FFI global variable
    fn formatFFIGlobalHover(
        self: *HoverProvider,
        global: *const ffi_loader.FFIGlobal,
    ) ![]const u8 {
        const readonly_str = if (global.readonly) " (readonly)" else "";

        return try std.fmt.allocPrint(
            self.allocator,
            "**Shell Global Variable**\n\n```lua\n{s}: {s}{s}\n```\n\n{s}",
            .{global.name, global.type, readonly_str, global.description},
        );
    }

    /// Get hover documentation for builtin functions (v0.2.0 stdlib)
    fn getBuiltinHover(self: *HoverProvider, name: []const u8) !?[]const u8 {
        // Math library
        if (std.mem.eql(u8, name, "floor")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nfloor(x: number): number\n```\n\nRounds down to the nearest integer.\n\n**Example:**\n```lua\nvar result = floor(3.7)  -- 3\nvar result = floor(-2.3) -- -3\n```", .{});
        } else if (std.mem.eql(u8, name, "ceil")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nceil(x: number): number\n```\n\nRounds up to the nearest integer.\n\n**Example:**\n```lua\nvar result = ceil(3.2)  -- 4\nvar result = ceil(-2.8) -- -2\n```", .{});
        } else if (std.mem.eql(u8, name, "abs")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nabs(x: number): number\n```\n\nReturns the absolute value.\n\n**Example:**\n```lua\nvar result = abs(-42)  -- 42\nvar result = abs(15)   -- 15\n```", .{});
        } else if (std.mem.eql(u8, name, "sqrt")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nsqrt(x: number): number\n```\n\nReturns the square root.\n\n**Example:**\n```lua\nvar result = sqrt(144)  -- 12\nvar result = sqrt(25)   -- 5\n```", .{});
        } else if (std.mem.eql(u8, name, "min")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nmin(...: number): number\n```\n\nReturns the minimum value from all arguments.\n\n**Example:**\n```lua\nvar result = min(5, 3, 8, 1)  -- 1\nvar result = min(10, 20)      -- 10\n```", .{});
        } else if (std.mem.eql(u8, name, "max")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nmax(...: number): number\n```\n\nReturns the maximum value from all arguments.\n\n**Example:**\n```lua\nvar result = max(5, 3, 8, 1)  -- 8\nvar result = max(10, 20)      -- 20\n```", .{});
        } else if (std.mem.eql(u8, name, "random")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nrandom(min: number, max: number): number\n```\n\nGenerates a random integer between min and max (inclusive).\n\n**Example:**\n```lua\nvar dice = random(1, 6)      -- Random 1-6\nvar score = random(0, 100)   -- Random 0-100\n```", .{});
        }

        // Table utilities
        else if (std.mem.eql(u8, name, "table_clone")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_clone(table: Table, deep: boolean): Table\n```\n\nClones a table. Shallow copy by default, deep copy if second argument is true.\n\n**Example:**\n```lua\nvar orig = {{name = \"Alice\", age = 30}}\nvar shallow = table_clone(orig)\nvar deep = table_clone(orig, true)\n```", .{});
        } else if (std.mem.eql(u8, name, "table_merge")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_merge(base: Table, override: Table): Table\n```\n\nRecursively merges two tables. Override values take precedence.\n\n**Example:**\n```lua\nvar base = {{a = 1, b = 2}}\nvar override = {{b = 3, c = 4}}\nvar merged = table_merge(base, override)\n-- Result: {{a = 1, b = 3, c = 4}}\n```", .{});
        } else if (std.mem.eql(u8, name, "table_keys")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_keys(table: Table): Array\n```\n\nReturns an array of all table keys.\n\n**Example:**\n```lua\nvar data = {{x = 10, y = 20, z = 30}}\nvar keys = table_keys(data)\n-- Result: {{\"x\", \"y\", \"z\"}}\n```", .{});
        } else if (std.mem.eql(u8, name, "table_values")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_values(table: Table): Array\n```\n\nReturns an array of all table values.\n\n**Example:**\n```lua\nvar data = {{x = 10, y = 20, z = 30}}\nvar vals = table_values(data)\n-- Result: {{10, 20, 30}}\n```", .{});
        } else if (std.mem.eql(u8, name, "table_find")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_find(array: Array, value: any): number\n```\n\nFinds the first index of value in array. Returns nil if not found.\n\n**Example:**\n```lua\nvar numbers = {{5, 10, 15, 20}}\nvar idx = table_find(numbers, 15)  -- 3\n```", .{});
        } else if (std.mem.eql(u8, name, "table_map")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_map(array: Array, mapper: function): Array\n```\n\nMaps a function over array elements.\n\n**Example:**\n```lua\n-- Placeholder: Function callbacks not yet implemented\n```", .{});
        } else if (std.mem.eql(u8, name, "table_filter")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\ntable_filter(array: Array, predicate: function): Array\n```\n\nFilters array elements by predicate function.\n\n**Example:**\n```lua\n-- Placeholder: Function callbacks not yet implemented\n```", .{});
        }

        // String utilities
        else if (std.mem.eql(u8, name, "string_split")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nstring_split(str: string, delimiter: string): Array\n```\n\nSplits a string by delimiter. Empty delimiter splits into characters.\n\n**Example:**\n```lua\nvar csv = \"apple,banana,cherry\"\nvar fruits = string_split(csv, \",\")\n-- Result: {{\"apple\", \"banana\", \"cherry\"}}\n```", .{});
        } else if (std.mem.eql(u8, name, "string_trim")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nstring_trim(str: string): string\n```\n\nRemoves leading and trailing whitespace.\n\n**Example:**\n```lua\nvar messy = \"  hello world  \"\nvar clean = string_trim(messy)\n-- Result: \"hello world\"\n```", .{});
        } else if (std.mem.eql(u8, name, "string_starts_with")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nstring_starts_with(str: string, prefix: string): boolean\n```\n\nChecks if string starts with prefix.\n\n**Example:**\n```lua\nvar filename = \"script.gza\"\nvar result = string_starts_with(filename, \"script\")\n-- Result: true\n```", .{});
        } else if (std.mem.eql(u8, name, "string_ends_with")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nstring_ends_with(str: string, suffix: string): boolean\n```\n\nChecks if string ends with suffix.\n\n**Example:**\n```lua\nvar filename = \"script.gza\"\nvar result = string_ends_with(filename, \".gza\")\n-- Result: true\n```", .{});
        }

        // Path utilities
        else if (std.mem.eql(u8, name, "path_join")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\npath_join(...: string): string\n```\n\nJoins path components with platform-appropriate separator.\n\n**Example:**\n```lua\nvar dir = path_join(\"home\", \"user\", \"docs\")\n-- Result: \"home/user/docs\" (Unix) or \"home\\\\user\\\\docs\" (Windows)\n```", .{});
        } else if (std.mem.eql(u8, name, "path_basename")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\npath_basename(path: string): string\n```\n\nExtracts filename from path.\n\n**Example:**\n```lua\nvar fullpath = \"/home/user/file.txt\"\nvar name = path_basename(fullpath)\n-- Result: \"file.txt\"\n```", .{});
        } else if (std.mem.eql(u8, name, "path_dirname")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\npath_dirname(path: string): string\n```\n\nExtracts directory from path.\n\n**Example:**\n```lua\nvar fullpath = \"/home/user/file.txt\"\nvar dir = path_dirname(fullpath)\n-- Result: \"/home/user\"\n```", .{});
        } else if (std.mem.eql(u8, name, "path_is_absolute")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\npath_is_absolute(path: string): boolean\n```\n\nChecks if path is absolute.\n\n**Example:**\n```lua\nvar result1 = path_is_absolute(\"/home/user\")  -- true\nvar result2 = path_is_absolute(\"docs/file\")   -- false\n```", .{});
        }

        // Table concat
        else if (std.mem.eql(u8, name, "concat")) {
            return try std.fmt.allocPrint(self.allocator,
                "**Builtin Function** (v0.2.0)\n\n```lua\nconcat(array: Array, separator: string): string\n```\n\nJoins array elements into string with separator.\n\n**Example:**\n```lua\nvar fruits = {{\"apple\", \"banana\", \"cherry\"}}\nvar csv = concat(fruits, \", \")\n-- Result: \"apple, banana, cherry\"\n```", .{});
        }

        return null;
    }
};

/// Check if a position is within a range
fn positionInRange(
    pos: protocol.Position,
    start: grove.Point,
    end: grove.Point,
) bool {
    // Position is before the start
    if (pos.line < start.row) return false;
    if (pos.line == start.row and pos.character < start.column) return false;

    // Position is after the end
    if (pos.line > end.row) return false;
    if (pos.line == end.row and pos.character > end.column) return false;

    return true;
}

/// Convert a tree-sitter node to LSP range
fn nodeToRange(node: grove.Node) protocol.Range {
    const start_point = node.startPosition();
    const end_point = node.endPosition();

    return .{
        .start = .{
            .line = start_point.row,
            .character = start_point.column,
        },
        .end = .{
            .line = end_point.row,
            .character = end_point.column,
        },
    };
}
