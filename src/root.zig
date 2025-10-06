//! ghostls - LSP server for ghostlang
//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Export LSP namespace for library consumers and tests
pub const lsp = struct {
    pub const protocol = @import("lsp/protocol.zig");
    pub const ReferencesProvider = @import("lsp/references_provider.zig").ReferencesProvider;
    pub const WorkspaceSymbolProvider = @import("lsp/workspace_symbol_provider.zig").WorkspaceSymbolProvider;
    pub const CompletionProvider = @import("lsp/completion_provider.zig").CompletionProvider;
};
