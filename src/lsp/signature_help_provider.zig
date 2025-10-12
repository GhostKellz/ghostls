const std = @import("std");
const grove = @import("grove");
const protocol = @import("protocol.zig");
const ffi_loader = @import("ffi_loader.zig");

/// Provides signature help (parameter hints) for function calls
pub const SignatureHelpProvider = struct {
    allocator: std.mem.Allocator,
    ffi_loader: *ffi_loader.FFILoader,

    pub const SignatureHelp = struct {
        signatures: []SignatureInformation,
        active_signature: u32,
        active_parameter: u32,

        pub fn deinit(self: *SignatureHelp, allocator: std.mem.Allocator) void {
            for (self.signatures) |*sig| {
                sig.deinit(allocator);
            }
            allocator.free(self.signatures);
        }
    };

    pub const SignatureInformation = struct {
        label: []const u8,
        documentation: ?[]const u8,
        parameters: []ParameterInformation,

        pub fn deinit(self: *SignatureInformation, allocator: std.mem.Allocator) void {
            allocator.free(self.label);
            if (self.documentation) |doc| {
                allocator.free(doc);
            }
            for (self.parameters) |*param| {
                param.deinit(allocator);
            }
            allocator.free(self.parameters);
        }
    };

    pub const ParameterInformation = struct {
        label: []const u8,
        documentation: ?[]const u8,

        pub fn deinit(self: *ParameterInformation, allocator: std.mem.Allocator) void {
            allocator.free(self.label);
            if (self.documentation) |doc| {
                allocator.free(doc);
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, ffi: *ffi_loader.FFILoader) SignatureHelpProvider {
        return .{ .allocator = allocator, .ffi_loader = ffi };
    }

    /// Get signature help at the cursor position
    pub fn getSignatureHelp(
        self: *SignatureHelpProvider,
        tree: *const grove.Tree,
        text: []const u8,
        position: protocol.Position,
        supports_shell_ffi: bool,
    ) !?SignatureHelp {
        const root_opt = tree.rootNode();
        if (root_opt == null) return null;

        const root = root_opt.?;

        // Find the call expression containing the cursor
        const call_node_opt = findCallExpression(root, position);
        if (call_node_opt == null) return null;

        const call_node = call_node_opt.?;

        // Get the function being called
        const func_name = try self.getFunctionName(call_node, text);
        defer if (func_name) |name| self.allocator.free(name);

        if (func_name == null) return null;

        // Count which parameter the cursor is on
        const active_param = try self.getActiveParameter(call_node, text, position);

        // Build signature information
        const signature = try self.buildSignature(func_name.?, text, supports_shell_ffi);

        var signatures = try self.allocator.alloc(SignatureInformation, 1);
        signatures[0] = signature;

        return SignatureHelp{
            .signatures = signatures,
            .active_signature = 0,
            .active_parameter = active_param,
        };
    }

    fn getFunctionName(self: *SignatureHelpProvider, call_node: grove.Node, text: []const u8) !?[]const u8 {
        // Look for the function field in call_expression
        const child_count = call_node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (call_node.child(i)) |child| {
                const kind = child.kind();
                if (std.mem.eql(u8, kind, "identifier") or
                    std.mem.eql(u8, kind, "member_expression")) {

                    const start = child.startByte();
                    const end = child.endByte();
                    if (end > start and end <= text.len) {
                        return try self.allocator.dupe(u8, text[start..end]);
                    }
                }
            }
        }
        return null;
    }

    fn getActiveParameter(
        self: *SignatureHelpProvider,
        call_node: grove.Node,
        text: []const u8,
        position: protocol.Position,
    ) !u32 {
        _ = self;
        _ = call_node;
        _ = text;
        _ = position;

        // Count commas before the cursor position
        // TODO: Implement proper parameter counting
        return 0;
    }

    fn buildSignature(self: *SignatureHelpProvider, func_name: []const u8, text: []const u8, supports_shell_ffi: bool) !SignatureInformation {
        _ = text;

        // Check for FFI functions first (if in GShell file)
        if (supports_shell_ffi) {
            if (try self.getFFISignature(func_name)) |sig| {
                return sig;
            }
        }

        // For built-in functions, provide known signatures
        if (try self.getBuiltinSignature(func_name)) |sig| {
            return sig;
        }

        // Default signature for unknown functions
        const label = try std.fmt.allocPrint(self.allocator, "{s}(...)", .{func_name});
        const params = try self.allocator.alloc(ParameterInformation, 0);

        return SignatureInformation{
            .label = label,
            .documentation = null,
            .parameters = params,
        };
    }

    fn getFFISignature(self: *SignatureHelpProvider, func_name: []const u8) !?SignatureInformation {
        // Check if this is a shell.* or git.* function
        // func_name might be "shell.alias" or just "alias" depending on how it was extracted
        var namespace: ?[]const u8 = null;
        var function_name: []const u8 = func_name;

        // Check if func_name contains a dot (namespace.function)
        if (std.mem.indexOf(u8, func_name, ".")) |dot_index| {
            namespace = func_name[0..dot_index];
            function_name = func_name[dot_index + 1..];
        }

        // Try shell namespace
        if (self.ffi_loader.getFunction("shell", function_name)) |func| {
            return try self.buildFFISignature(func);
        }

        // Try git namespace
        if (self.ffi_loader.getFunction("git", function_name)) |func| {
            return try self.buildFFISignature(func);
        }

        // If we had a namespace hint, try that specifically
        if (namespace) |ns| {
            if (self.ffi_loader.getFunction(ns, function_name)) |func| {
                return try self.buildFFISignature(func);
            }
        }

        return null;
    }

    fn buildFFISignature(self: *SignatureHelpProvider, func: *const ffi_loader.FFIFunction) !SignatureInformation {
        // Build signature label
        const label = try self.allocator.dupe(u8, func.signature);

        // Build documentation from description
        const documentation = try self.allocator.dupe(u8, func.description);

        // Build parameter information
        var params = try self.allocator.alloc(ParameterInformation, func.parameters.len);
        for (func.parameters, 0..) |param, i| {
            params[i] = .{
                .label = try self.allocator.dupe(u8, param.name),
                .documentation = try std.fmt.allocPrint(
                    self.allocator,
                    "({s}) {s}",
                    .{param.type, param.description},
                ),
            };
        }

        return SignatureInformation{
            .label = label,
            .documentation = documentation,
            .parameters = params,
        };
    }

    fn getBuiltinSignature(self: *SignatureHelpProvider, func_name: []const u8) !?SignatureInformation {
        // Provide signatures for Ghostlang built-in functions
        if (std.mem.eql(u8, func_name, "print")) {
            const label = try self.allocator.dupe(u8, "print(value: any)");
            var params = try self.allocator.alloc(ParameterInformation, 1);
            params[0] = .{
                .label = try self.allocator.dupe(u8, "value"),
                .documentation = try self.allocator.dupe(u8, "The value to print"),
            };
            return SignatureInformation{
                .label = label,
                .documentation = try self.allocator.dupe(u8, "Print a value to the console"),
                .parameters = params,
            };
        } else if (std.mem.eql(u8, func_name, "arrayPush")) {
            const label = try self.allocator.dupe(u8, "arrayPush(array: array, value: any)");
            var params = try self.allocator.alloc(ParameterInformation, 2);
            params[0] = .{
                .label = try self.allocator.dupe(u8, "array"),
                .documentation = try self.allocator.dupe(u8, "The array to push to"),
            };
            params[1] = .{
                .label = try self.allocator.dupe(u8, "value"),
                .documentation = try self.allocator.dupe(u8, "The value to push"),
            };
            return SignatureInformation{
                .label = label,
                .documentation = try self.allocator.dupe(u8, "Push a value onto an array"),
                .parameters = params,
            };
        }

        return null;
    }

    pub fn freeSignatureHelp(self: *SignatureHelpProvider, help: *SignatureHelp) void {
        help.deinit(self.allocator);
    }
};

/// Find the call expression node containing the position
fn findCallExpression(node: grove.Node, position: protocol.Position) ?grove.Node {
    const kind = node.kind();

    // Check if this is a call_expression
    if (std.mem.eql(u8, kind, "call_expression") or
        std.mem.eql(u8, kind, "call")) {

        const start_pos = node.startPosition();
        const end_pos = node.endPosition();

        if (positionInRange(position, start_pos, end_pos)) {
            return node;
        }
    }

    // Recursively search children
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            if (findCallExpression(child, position)) |found| {
                return found;
            }
        }
    }

    return null;
}

fn positionInRange(pos: protocol.Position, start: grove.Point, end: grove.Point) bool {
    if (pos.line < start.row) return false;
    if (pos.line == start.row and pos.character < start.column) return false;
    if (pos.line > end.row) return false;
    if (pos.line == end.row and pos.character > end.column) return false;
    return true;
}
