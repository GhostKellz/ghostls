const std = @import("std");
const kalix = @import("kalix");
const protocol = @import("protocol.zig");

/// Provides hover information for kalix smart contracts
pub const KalixHoverProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) KalixHoverProvider {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *KalixHoverProvider) void {
        // No resources to clean up
    }

    /// Get hover information at a position in kalix source
    pub fn hover(self: *KalixHoverProvider, source: []const u8, line: u32, character: u32) !?[]const u8 {
        _ = line;
        _ = character;

        var result = try kalix.frontend.api.analyzeSource(self.allocator, source);
        defer result.deinit();

        // If there are diagnostics, don't provide hover (file has errors)
        if (result.diagnostics.len > 0) return null;

        // For now, return basic contract info if metadata exists
        if (result.metadata.contracts.len == 0) return null;

        var info = std.ArrayList(u8) = .{};
        defer info.deinit(self.allocator);

        try info.appendSlice(self.allocator, "**Kalix Smart Contracts**\n\n");

        for (result.metadata.contracts) |contract| {
            try info.appendSlice(self.allocator, "Contract: `");
            try info.appendSlice(self.allocator, contract.name);
            try info.appendSlice(self.allocator, "`\n\n");

            if (contract.states.len > 0) {
                try info.appendSlice(self.allocator, "**State Variables:**\n");
                for (contract.states) |state| {
                    try info.appendSlice(self.allocator, "- ");
                    if (state.is_public) try info.appendSlice(self.allocator, "pub ");
                    try info.appendSlice(self.allocator, state.name);
                    try info.appendSlice(self.allocator, ": ");
                    try info.appendSlice(self.allocator, state.type_name);
                    try info.appendSlice(self.allocator, "\n");
                }
                try info.appendSlice(self.allocator, "\n");
            }

            if (contract.functions.len > 0) {
                try info.appendSlice(self.allocator, "**Functions:**\n");
                for (contract.functions) |func| {
                    try info.appendSlice(self.allocator, "- ");
                    if (func.is_public) try info.appendSlice(self.allocator, "pub ");
                    try info.appendSlice(self.allocator, "fn ");
                    try info.appendSlice(self.allocator, func.name);
                    try info.appendSlice(self.allocator, "(");

                    for (func.params, 0..) |param, i| {
                        if (i > 0) try info.appendSlice(self.allocator, ", ");
                        try info.appendSlice(self.allocator, param.name);
                        try info.appendSlice(self.allocator, ": ");
                        try info.appendSlice(self.allocator, param.type_name);
                    }

                    try info.appendSlice(self.allocator, ")");
                    if (!std.mem.eql(u8, func.return_type, "void")) {
                        try info.appendSlice(self.allocator, " -> ");
                        try info.appendSlice(self.allocator, func.return_type);
                    }

                    if (func.view) try info.appendSlice(self.allocator, " [view]");
                    if (func.payable) try info.appendSlice(self.allocator, " [payable]");

                    try info.appendSlice(self.allocator, "\n");
                }
            }
        }

        return try info.toOwnedSlice(self.allocator);
    }

    pub fn freeHover(self: *KalixHoverProvider, hover_text: []const u8) void {
        self.allocator.free(hover_text);
    }
};
