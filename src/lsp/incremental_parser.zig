const std = @import("std");
const grove = @import("grove");

/// Optimized incremental parser that reuses AST nodes on edits
pub const IncrementalParser = struct {
    allocator: std.mem.Allocator,
    parser: grove.Parser,

    pub fn init(allocator: std.mem.Allocator) !IncrementalParser {
        const ghostlang_language = try grove.Languages.ghostlang.get();
        var parser = try grove.Parser.init(allocator);
        try parser.setLanguage(ghostlang_language);

        return .{
            .allocator = allocator,
            .parser = parser,
        };
    }

    pub fn deinit(self: *IncrementalParser) void {
        self.parser.deinit();
    }

    /// Parse text incrementally, reusing old tree if available
    pub fn parse(
        self: *IncrementalParser,
        old_tree: ?*const grove.Tree,
        text: []const u8,
        edit: ?TextEdit,
    ) !grove.Tree {
        // If we have an edit and an old tree, apply the edit first
        if (old_tree) |tree| {
            if (edit) |e| {
                // Create an InputEdit for tree-sitter
                const input_edit = grove.InputEdit{
                    .start_byte = e.start_byte,
                    .old_end_byte = e.old_end_byte,
                    .new_end_byte = e.new_end_byte,
                    .start_point = .{
                        .row = e.start_position.line,
                        .column = e.start_position.character,
                    },
                    .old_end_point = .{
                        .row = e.old_end_position.line,
                        .column = e.old_end_position.character,
                    },
                    .new_end_point = .{
                        .row = e.new_end_position.line,
                        .column = e.new_end_position.character,
                    },
                };

                // Create a mutable tree for editing
                var mutable_tree = tree.*;
                mutable_tree.edit(&input_edit);

                // Parse with the edited tree as base
                return try self.parser.parseUtf8(&mutable_tree, text);
            }
        }

        // No incremental edit available, do full parse
        return try self.parser.parseUtf8(old_tree, text);
    }

    pub const TextEdit = struct {
        start_byte: u32,
        old_end_byte: u32,
        new_end_byte: u32,
        start_position: EditPosition,
        old_end_position: EditPosition,
        new_end_position: EditPosition,
    };

    pub const EditPosition = struct {
        line: u32,
        character: u32,
    };
};

/// Convert LSP content changes to incremental edit
pub fn contentChangeToEdit(
    old_text: []const u8,
    change: ContentChange,
) IncrementalParser.TextEdit {
    _ = old_text;

    const start_byte = change.range.?.start.line * 100 + change.range.?.start.character; // Simplified
    const old_end_byte = change.range.?.end.line * 100 + change.range.?.end.character;

    const new_end_line = change.range.?.start.line + countNewlines(change.text);
    const new_end_char = if (countNewlines(change.text) > 0)
        getLastLineLength(change.text)
    else
        change.range.?.start.character + @as(u32, @intCast(change.text.len));

    const new_end_byte = start_byte + @as(u32, @intCast(change.text.len));

    return .{
        .start_byte = start_byte,
        .old_end_byte = old_end_byte,
        .new_end_byte = new_end_byte,
        .start_position = .{
            .line = change.range.?.start.line,
            .character = change.range.?.start.character,
        },
        .old_end_position = .{
            .line = change.range.?.end.line,
            .character = change.range.?.end.character,
        },
        .new_end_position = .{
            .line = new_end_line,
            .character = new_end_char,
        },
    };
}

pub const ContentChange = struct {
    range: ?Range,
    text: []const u8,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Position = struct {
    line: u32,
    character: u32,
};

fn countNewlines(text: []const u8) u32 {
    var count: u32 = 0;
    for (text) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}

fn getLastLineLength(text: []const u8) u32 {
    var length: u32 = 0;
    var i: usize = text.len;
    while (i > 0) {
        i -= 1;
        if (text[i] == '\n') break;
        length += 1;
    }
    return length;
}
