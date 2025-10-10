//! ghostls - LSP server for ghostlang
//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Export LSP namespace for library consumers and tests
pub const lsp = struct {
    pub const protocol = @import("lsp/protocol.zig");
    pub const ReferencesProvider = @import("lsp/references_provider.zig").ReferencesProvider;
    pub const WorkspaceSymbolProvider = @import("lsp/workspace_symbol_provider.zig").WorkspaceSymbolProvider;
    pub const CompletionProvider = @import("lsp/completion_provider.zig").CompletionProvider;
    pub const SemanticTokensProvider = @import("lsp/semantic_tokens_provider.zig").SemanticTokensProvider;
    pub const CodeActionsProvider = @import("lsp/code_actions_provider.zig").CodeActionsProvider;
    pub const RenameProvider = @import("lsp/rename_provider.zig").RenameProvider;
    pub const SignatureHelpProvider = @import("lsp/signature_help_provider.zig").SignatureHelpProvider;
    pub const InlayHintsProvider = @import("lsp/inlay_hints_provider.zig").InlayHintsProvider;
    pub const SelectionRangeProvider = @import("lsp/selection_range_provider.zig").SelectionRangeProvider;
    pub const WorkspaceManager = @import("lsp/workspace_manager.zig").WorkspaceManager;
    pub const FilesystemWatcher = @import("lsp/filesystem_watcher.zig").FilesystemWatcher;
    pub const IncrementalParser = @import("lsp/incremental_parser.zig").IncrementalParser;
};
