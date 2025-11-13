const std = @import("std");
const protocol = @import("protocol.zig");
const grove = @import("grove");

/// Severity level for blockchain diagnostics
pub const Severity = enum {
    @"error",
    warning,
    info,
    hint,

    pub fn toLSP(self: Severity) protocol.DiagnosticSeverity {
        return switch (self) {
            .@"error" => .Error,
            .warning => .Warning,
            .info => .Information,
            .hint => .Hint,
        };
    }
};

/// Blockchain-specific diagnostic
pub const BlockchainDiagnostic = struct {
    range: protocol.Range,
    severity: Severity,
    message: []const u8,
    code: []const u8,
    source: []const u8 = "ghostls-blockchain",
};

/// Gas cost estimates for different operations
pub const GasCosts = struct {
    pub const STORAGE_SET: u64 = 20000;
    pub const STORAGE_READ: u64 = 200;
    pub const STORAGE_CLEAR: u64 = 5000;
    pub const CALL_BASE: u64 = 700;
    pub const TRANSFER: u64 = 9000;
    pub const HASH: u64 = 30;
    pub const SIGNATURE_VERIFY: u64 = 3000;
    pub const EMIT_EVENT: u64 = 375;
    pub const MEMORY_WORD: u64 = 3;
    pub const SSTORE_REFUND: u64 = 15000;
};

/// Blockchain security analyzer
pub const BlockchainAnalyzer = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayList(BlockchainDiagnostic),
    gas_estimates: std.StringHashMap(u64),

    pub fn init(allocator: std.mem.Allocator) BlockchainAnalyzer {
        return .{
            .allocator = allocator,
            .diagnostics = .empty,
            .gas_estimates = std.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *BlockchainAnalyzer) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
            self.allocator.free(diag.code);
        }
        self.diagnostics.deinit(self.allocator);
        self.gas_estimates.deinit();
    }

    /// Analyze a smart contract for vulnerabilities and inefficiencies
    pub fn analyze(self: *BlockchainAnalyzer, tree: *const grove.Tree, source: []const u8) ![]BlockchainDiagnostic {
        // Clear previous diagnostics
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
            self.allocator.free(diag.code);
        }
        self.diagnostics.clearRetainingCapacity();
        self.gas_estimates.clearRetainingCapacity();

        const root = tree.rootNode() orelse return &[_]BlockchainDiagnostic{};

        // Run all analysis passes
        try self.detectReentrancy(root, source);
        try self.analyzeStoragePatterns(root, source);
        try self.validateEvents(root, source);
        try self.detectIntegerOverflow(root, source);
        try self.checkAccessControl(root, source);
        try self.analyzeCryptoPatterns(root, source);
        try self.checkTimestampDependence(root, source);

        return try self.diagnostics.toOwnedSlice(self.allocator);
    }

    /// Detect reentrancy vulnerabilities
    fn detectReentrancy(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        var in_function = false;
        var has_external_call = false;
        var has_state_change_after_call = false;
        var external_call_line: ?u32 = null;

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                if (std.mem.eql(u8, node_type, "function_declaration") or
                    std.mem.eql(u8, node_type, "local_function_declaration"))
                {
                    in_function = true;
                    has_external_call = false;
                    has_state_change_after_call = false;
                    external_call_line = null;

                    // Check function body for reentrancy pattern
                    try self.checkFunctionReentrancy(node, source);
                }

                // Detect external calls (web3.call, web3.transfer, web3.delegateCall)
                if (in_function and std.mem.eql(u8, node_type, "call_expression")) {
                    if (self.isExternalCall(node, source)) {
                        has_external_call = true;
                        external_call_line = node.startPosition().row;
                    }
                }

                // Detect state changes after external call
                if (in_function and has_external_call and std.mem.eql(u8, node_type, "assignment_expression")) {
                    if (self.isStateChange(node, source)) {
                        has_state_change_after_call = true;

                        // Report reentrancy vulnerability
                        const range = self.nodeToRange(node);
                        const message = try std.fmt.allocPrint(
                            self.allocator,
                            "Potential reentrancy vulnerability: state change after external call on line {d}. Consider moving state updates before external calls or using a reentrancy guard.",
                            .{external_call_line.? + 1},
                        );

                        try self.diagnostics.append(self.allocator, .{
                            .range = range,
                            .severity = .@"error",
                            .message = message,
                            .code = try self.allocator.dupe(u8, "reentrancy"),
                        });
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Check a specific function for reentrancy patterns
    fn checkFunctionReentrancy(self: *BlockchainAnalyzer, func_node: grove.Node, source: []const u8) !void {
        // Look for missing reentrancy guard pattern
        var has_guard = false;
        var cursor = try func_node.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const text = self.getNodeText(node, source);

                // Check for common reentrancy guard patterns
                if (std.mem.indexOf(u8, text, "locked") != null or
                    std.mem.indexOf(u8, text, "reentrancy") != null or
                    std.mem.indexOf(u8, text, "guard") != null)
                {
                    has_guard = true;
                    break;
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }

        // If function has external calls but no guard, suggest adding one
        if (!has_guard and self.functionHasExternalCalls(func_node, source)) {
            const range = self.nodeToRange(func_node);
            const message = try self.allocator.dupe(u8, "Function makes external calls but has no reentrancy guard. Consider adding a mutex lock pattern.");

            try self.diagnostics.append(self.allocator, .{
                .range = range,
                .severity = .warning,
                .message = message,
                .code = try self.allocator.dupe(u8, "missing-reentrancy-guard"),
            });
        }
    }

    /// Analyze storage access patterns for efficiency
    fn analyzeStoragePatterns(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var storage_reads = std.StringHashMap(u32).init(self.allocator);
        defer storage_reads.deinit();

        var cursor = try root.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Detect redundant storage reads (same key accessed multiple times)
                if (std.mem.eql(u8, node_type, "subscript_expression")) {
                    const text = self.getNodeText(node, source);

                    const result = try storage_reads.getOrPut(text);
                    if (result.found_existing) {
                        result.value_ptr.* += 1;

                        // Warn about redundant reads (cost: 200 gas each)
                        if (result.value_ptr.* >= 3) {
                            const range = self.nodeToRange(node);
                            const message = try std.fmt.allocPrint(
                                self.allocator,
                                "Storage variable '{s}' read {d} times. Consider caching in a local variable to save ~{d} gas.",
                                .{ text, result.value_ptr.*, (result.value_ptr.* - 1) * GasCosts.STORAGE_READ },
                            );

                            try self.diagnostics.append(self.allocator, .{
                                .range = range,
                                .severity = .hint,
                                .message = message,
                                .code = try self.allocator.dupe(u8, "redundant-storage-read"),
                            });
                        }
                    } else {
                        result.value_ptr.* = 1;
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Validate event emissions
    fn validateEvents(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Find emit() calls
                if (std.mem.eql(u8, node_type, "call_expression")) {
                    if (node.childByFieldName("function")) |func_node| {
                        const func_name = self.getNodeText(func_node, source);

                        if (std.mem.eql(u8, func_name, "emit")) {
                            // Validate emit call structure
                            if (node.childByFieldName("arguments")) |args_node| {
                                const arg_count = args_node.namedChildCount();

                                if (arg_count < 1) {
                                    const range = self.nodeToRange(node);
                                    const message = try self.allocator.dupe(u8, "emit() requires at least an event name. Usage: emit(\"EventName\", {data})");

                                    try self.diagnostics.append(self.allocator, .{
                                        .range = range,
                                        .severity = .@"error",
                                        .message = message,
                                        .code = try self.allocator.dupe(u8, "invalid-emit"),
                                    });
                                } else if (arg_count > 2) {
                                    const range = self.nodeToRange(node);
                                    const message = try self.allocator.dupe(u8, "emit() accepts at most 2 arguments: event name and optional data table.");

                                    try self.diagnostics.append(self.allocator, .{
                                        .range = range,
                                        .severity = .warning,
                                        .message = message,
                                        .code = try self.allocator.dupe(u8, "emit-too-many-args"),
                                    });
                                }

                                // Check event name is a string literal
                                if (arg_count >= 1) {
                                    if (args_node.namedChild(0)) |event_name_node| {
                                        if (!std.mem.eql(u8, event_name_node.kind(), "string_literal")) {
                                            const range = self.nodeToRange(event_name_node);
                                            const message = try self.allocator.dupe(u8, "Event name should be a string literal for better tooling support.");

                                            try self.diagnostics.append(self.allocator, .{
                                                .range = range,
                                                .severity = .hint,
                                                .message = message,
                                                .code = try self.allocator.dupe(u8, "emit-name-not-literal"),
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Detect potential integer overflow/underflow
    fn detectIntegerOverflow(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Detect unchecked arithmetic
                if (std.mem.eql(u8, node_type, "additive_expression") or
                    std.mem.eql(u8, node_type, "multiplicative_expression"))
                {
                    const text = self.getNodeText(node, source);

                    // Check if in an assignment without bounds checking
                    if (node.parent()) |parent| {
                        if (std.mem.eql(u8, parent.kind(), "assignment_expression")) {
                            // Look for web3.require check nearby
                            if (!self.hasNearbyRequireCheck(parent, source)) {
                                const range = self.nodeToRange(node);
                                const message = try std.fmt.allocPrint(
                                    self.allocator,
                                    "Arithmetic operation '{s}' without overflow check. Consider using web3.require() to validate bounds.",
                                    .{text},
                                );

                                try self.diagnostics.append(self.allocator, .{
                                    .range = range,
                                    .severity = .warning,
                                    .message = message,
                                    .code = try self.allocator.dupe(u8, "unchecked-arithmetic"),
                                });
                            }
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Check for missing access control
    fn checkAccessControl(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Check public functions for access control
                if (std.mem.eql(u8, node_type, "function_declaration")) {
                    if (node.childByFieldName("name")) |name_node| {
                        const func_name = self.getNodeText(name_node, source);

                        // Skip view functions (balanceOf, totalSupply, etc.)
                        if (self.isViewFunction(func_name)) {
                            if (!cursor.gotoNextSibling()) break;
                            continue;
                        }

                        // Check if function modifies state without access control
                        if (self.modifiesState(node, source) and !self.hasAccessControl(node, source)) {
                            const range = self.nodeToRange(node);
                            const message = try std.fmt.allocPrint(
                                self.allocator,
                                "Function '{s}' modifies state but has no access control. Consider adding owner/role checks with web3.require().",
                                .{func_name},
                            );

                            try self.diagnostics.append(self.allocator, .{
                                .range = range,
                                .severity = .warning,
                                .message = message,
                                .code = try self.allocator.dupe(u8, "missing-access-control"),
                            });
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Analyze cryptographic patterns
    fn analyzeCryptoPatterns(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Check signature verification patterns
                if (std.mem.eql(u8, node_type, "call_expression")) {
                    if (node.childByFieldName("function")) |func_node| {
                        const func_text = self.getNodeText(func_node, source);

                        if (std.mem.indexOf(u8, func_text, "verifySignature") != null) {
                            // Suggest hashing before signature verification
                            const range = self.nodeToRange(node);
                            const message = try self.allocator.dupe(u8, "Signature verification detected. Ensure the message is hashed with web3.hash() before verification for security.");

                            try self.diagnostics.append(self.allocator, .{
                                .range = range,
                                .severity = .info,
                                .message = message,
                                .code = try self.allocator.dupe(u8, "crypto-hash-before-verify"),
                            });
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Check for timestamp dependence vulnerabilities
    fn checkTimestampDependence(self: *BlockchainAnalyzer, root: grove.Node, source: []const u8) !void {
        var cursor = try root.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const text = self.getNodeText(node, source);

                // Detect timestamp usage in critical logic
                if (std.mem.indexOf(u8, text, "getTimestamp") != null) {
                    if (node.parent()) |parent| {
                        // Check if used in conditionals for critical decisions
                        if (std.mem.eql(u8, parent.kind(), "relational_expression") or
                            std.mem.eql(u8, parent.kind(), "equality_expression"))
                        {
                            const range = self.nodeToRange(node);
                            const message = try self.allocator.dupe(u8, "Timestamp dependence detected. Block timestamps can be manipulated by miners within ~15 seconds. Avoid using for critical randomness or time-sensitive logic.");

                            try self.diagnostics.append(self.allocator, .{
                                .range = range,
                                .severity = .warning,
                                .message = message,
                                .code = try self.allocator.dupe(u8, "timestamp-dependence"),
                            });
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
    }

    /// Estimate gas cost for a function
    pub fn estimateGas(self: *BlockchainAnalyzer, func_node: grove.Node, source: []const u8) !u64 {
        var total_gas: u64 = GasCosts.CALL_BASE;
        var cursor = try func_node.treeWalk();
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const node_type = node.kind();

                // Storage operations
                if (std.mem.eql(u8, node_type, "assignment_expression")) {
                    if (node.childByFieldName("left")) |left| {
                        if (std.mem.eql(u8, left.kind(), "subscript_expression")) {
                            total_gas += GasCosts.STORAGE_SET;
                        }
                    }
                }

                // Storage reads
                if (std.mem.eql(u8, node_type, "subscript_expression")) {
                    total_gas += GasCosts.STORAGE_READ;
                }

                // Hash operations
                if (std.mem.eql(u8, node_type, "call_expression")) {
                    if (node.childByFieldName("function")) |func| {
                        const func_text = self.getNodeText(func, source);
                        if (std.mem.indexOf(u8, func_text, "hash") != null) {
                            total_gas += GasCosts.HASH;
                        } else if (std.mem.indexOf(u8, func_text, "verifySignature") != null) {
                            total_gas += GasCosts.SIGNATURE_VERIFY;
                        } else if (std.mem.indexOf(u8, func_text, "emit") != null) {
                            total_gas += GasCosts.EMIT_EVENT;
                        } else if (std.mem.indexOf(u8, func_text, "transfer") != null) {
                            total_gas += GasCosts.TRANSFER;
                        }
                    }
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }

        return total_gas;
    }

    // Helper functions

    fn isExternalCall(self: *BlockchainAnalyzer, node: grove.Node, source: []const u8) bool {
        if (node.childByFieldName("function")) |func_node| {
            const func_text = self.getNodeText(func_node, source);
            return std.mem.indexOf(u8, func_text, "web3.call") != null or
                std.mem.indexOf(u8, func_text, "web3.transfer") != null or
                std.mem.indexOf(u8, func_text, "web3.delegateCall") != null;
        }
        return false;
    }

    fn isStateChange(self: *BlockchainAnalyzer, node: grove.Node, source: []const u8) bool {
        _ = self;
        _ = source;
        if (node.childByFieldName("left")) |left| {
            // State change if assigning to storage (table access)
            return std.mem.eql(u8, left.kind(), "subscript_expression");
        }
        return false;
    }

    fn functionHasExternalCalls(self: *BlockchainAnalyzer, func_node: grove.Node, source: []const u8) bool {
        var cursor = func_node.treeWalk() catch return false;
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                if (std.mem.eql(u8, node.kind(), "call_expression")) {
                    if (self.isExternalCall(node, source)) {
                        return true;
                    }
                }
                if (!cursor.gotoNextSibling()) break;
            }
        }
        return false;
    }

    fn hasNearbyRequireCheck(self: *BlockchainAnalyzer, node: grove.Node, source: []const u8) bool {
        // Check siblings and parent for web3.require calls
        if (node.parent()) |parent| {
            var cursor = parent.treeWalk() catch return false;
            defer cursor.deinit();

            if (cursor.gotoFirstChild()) {
                while (true) {
                    const sibling = cursor.currentNode();
                    const text = self.getNodeText(sibling, source);
                    if (std.mem.indexOf(u8, text, "web3.require") != null or
                        std.mem.indexOf(u8, text, "web3.assert") != null)
                    {
                        return true;
                    }
                    if (!cursor.gotoNextSibling()) break;
                }
            }
        }
        return false;
    }

    fn isViewFunction(self: *BlockchainAnalyzer, name: []const u8) bool {
        _ = self;
        const view_functions = [_][]const u8{
            "balanceOf", "totalSupply", "getOwner", "get",
            "view", "read", "query", "check", "is", "has",
        };

        for (view_functions) |vf| {
            if (std.mem.indexOf(u8, name, vf) != null) {
                return true;
            }
        }
        return false;
    }

    fn modifiesState(self: *BlockchainAnalyzer, func_node: grove.Node, source: []const u8) bool {
        var cursor = func_node.treeWalk() catch return false;
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                if (std.mem.eql(u8, node.kind(), "assignment_expression")) {
                    if (self.isStateChange(node, source)) {
                        return true;
                    }
                }
                if (!cursor.gotoNextSibling()) break;
            }
        }
        return false;
    }

    fn hasAccessControl(self: *BlockchainAnalyzer, func_node: grove.Node, source: []const u8) bool {
        var cursor = func_node.treeWalk() catch return false;
        defer cursor.deinit();

        if (cursor.gotoFirstChild()) {
            while (true) {
                const node = cursor.currentNode();
                const text = self.getNodeText(node, source);

                // Check for common access control patterns
                if (std.mem.indexOf(u8, text, "owner") != null and
                    std.mem.indexOf(u8, text, "web3.getCaller") != null)
                {
                    return true;
                }
                if (std.mem.indexOf(u8, text, "onlyOwner") != null or
                    std.mem.indexOf(u8, text, "onlyAdmin") != null or
                    std.mem.indexOf(u8, text, "authorized") != null)
                {
                    return true;
                }

                if (!cursor.gotoNextSibling()) break;
            }
        }
        return false;
    }

    fn getNodeText(self: *BlockchainAnalyzer, node: grove.Node, source: []const u8) []const u8 {
        _ = self;
        const start = node.startByte();
        const end = node.endByte();
        if (end > source.len) return "";
        return source[start..end];
    }

    fn nodeToRange(self: *BlockchainAnalyzer, node: grove.Node) protocol.Range {
        _ = self;
        const start = node.startPosition();
        const end = node.endPosition();

        return .{
            .start = .{ .line = start.row, .character = start.column },
            .end = .{ .line = end.row, .character = end.column },
        };
    }
};
