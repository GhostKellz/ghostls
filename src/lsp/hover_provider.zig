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
