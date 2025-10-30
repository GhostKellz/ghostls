const std = @import("std");

// LSP Position (zero-indexed)
pub const Position = struct {
    line: u32,
    character: u32,
};

// LSP Range
pub const Range = struct {
    start: Position,
    end: Position,
};

// LSP Location
pub const Location = struct {
    uri: []const u8,
    range: Range,
};

// Diagnostic severity
pub const DiagnosticSeverity = enum(u32) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
};

// Diagnostic
pub const Diagnostic = struct {
    range: Range,
    severity: ?DiagnosticSeverity = null,
    code: ?[]const u8 = null,
    source: ?[]const u8 = null,
    message: []const u8,
    relatedInformation: ?[]DiagnosticRelatedInformation = null,

    pub const DiagnosticRelatedInformation = struct {
        location: Location,
        message: []const u8,
    };
};

// Text document identifier
pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

// Versioned text document identifier
pub const VersionedTextDocumentIdentifier = struct {
    uri: []const u8,
    version: i32,
};

// Text document item
pub const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i32,
    text: []const u8,
};

// Text document content change event
pub const TextDocumentContentChangeEvent = struct {
    range: ?Range = null,
    rangeLength: ?u32 = null,
    text: []const u8,
};

// Server capabilities
pub const ServerCapabilities = struct {
    positionEncoding: ?[]const u8 = "utf-16",
    textDocumentSync: ?TextDocumentSyncOptions = null,
    hoverProvider: ?bool = null,
    completionProvider: ?CompletionOptions = null,
    definitionProvider: ?bool = null,
    referencesProvider: ?bool = null,
    documentSymbolProvider: ?bool = null,
    workspaceSymbolProvider: ?bool = null,
    semanticTokensProvider: ?SemanticTokensOptions = null,
    codeActionProvider: ?bool = null,
    renameProvider: ?RenameOptions = null,
    signatureHelpProvider: ?SignatureHelpOptions = null,
    inlayHintProvider: ?bool = null,
    selectionRangeProvider: ?bool = null,
    documentHighlightProvider: ?bool = null,
    foldingRangeProvider: ?bool = null,

    pub const TextDocumentSyncOptions = struct {
        openClose: ?bool = null,
        change: ?u8 = null, // TextDocumentSyncKind: None=0, Full=1, Incremental=2
        save: ?SaveOptions = null,

        pub const SaveOptions = struct {
            includeText: ?bool = null,
        };
    };

    pub const CompletionOptions = struct {
        triggerCharacters: ?[]const []const u8 = null,
        resolveProvider: ?bool = null,
    };

    pub const SemanticTokensOptions = struct {
        legend: SemanticTokensLegend,
        range: ?bool = null,
        full: ?bool = null,

        pub const SemanticTokensLegend = struct {
            tokenTypes: []const []const u8,
            tokenModifiers: []const []const u8,
        };
    };

    pub const RenameOptions = struct {
        prepareProvider: ?bool = null,
    };

    pub const SignatureHelpOptions = struct {
        triggerCharacters: ?[]const []const u8 = null,
        retriggerCharacters: ?[]const []const u8 = null,
    };
};

// Initialize params
pub const InitializeParams = struct {
    processId: ?i32 = null,
    clientInfo: ?ClientInfo = null,
    locale: ?[]const u8 = null,
    rootPath: ?[]const u8 = null,
    rootUri: ?[]const u8 = null,
    capabilities: ClientCapabilities,
    trace: ?[]const u8 = null,
    workspaceFolders: ?[]WorkspaceFolder = null,

    pub const ClientInfo = struct {
        name: []const u8,
        version: ?[]const u8 = null,
    };

    pub const WorkspaceFolder = struct {
        uri: []const u8,
        name: []const u8,
    };
};

// Client capabilities (simplified)
pub const ClientCapabilities = struct {
    workspace: ?struct {} = null,
    textDocument: ?struct {} = null,
    experimental: ?std.json.Value = null,
};

// Initialize result
pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ?ServerInfo = null,

    pub const ServerInfo = struct {
        name: []const u8,
        version: ?[]const u8 = null,
    };
};

// JSON-RPC message types
pub const RequestMessage = struct {
    jsonrpc: []const u8 = "2.0",
    id: Id,
    method: []const u8,
    params: ?std.json.Value = null,

    pub const Id = union(enum) {
        integer: i64,
        string: []const u8,
    };
};

pub const ResponseMessage = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?RequestMessage.Id,
    result: ?std.json.Value = null,
    @"error": ?ResponseError = null,

    pub const ResponseError = struct {
        code: i32,
        message: []const u8,
        data: ?std.json.Value = null,
    };
};

pub const NotificationMessage = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?std.json.Value = null,
};

// LSP method names
pub const Methods = struct {
    pub const initialize = "initialize";
    pub const initialized = "initialized";
    pub const shutdown = "shutdown";
    pub const exit = "exit";
    pub const text_document_did_open = "textDocument/didOpen";
    pub const text_document_did_change = "textDocument/didChange";
    pub const text_document_did_save = "textDocument/didSave";
    pub const text_document_did_close = "textDocument/didClose";
    pub const text_document_hover = "textDocument/hover";
    pub const text_document_definition = "textDocument/definition";
    pub const text_document_references = "textDocument/references";
    pub const text_document_document_symbol = "textDocument/documentSymbol";
    pub const text_document_completion = "textDocument/completion";
    pub const text_document_semantic_tokens_full = "textDocument/semanticTokens/full";
    pub const text_document_code_action = "textDocument/codeAction";
    pub const text_document_rename = "textDocument/rename";
    pub const text_document_prepare_rename = "textDocument/prepareRename";
    pub const text_document_signature_help = "textDocument/signatureHelp";
    pub const text_document_inlay_hint = "textDocument/inlayHint";
    pub const text_document_selection_range = "textDocument/selectionRange";
    pub const text_document_document_highlight = "textDocument/documentHighlight";
    pub const text_document_folding_range = "textDocument/foldingRange";
    pub const workspace_symbol = "workspace/symbol";
    pub const workspace_did_change_configuration = "workspace/didChangeConfiguration";
    pub const workspace_did_change_watched_files = "workspace/didChangeWatchedFiles";
};

// Hover
pub const HoverParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

pub const MarkupContent = struct {
    kind: []const u8, // "plaintext" or "markdown"
    value: []const u8,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

// Document Symbol
pub const DocumentSymbolParams = struct {
    textDocument: TextDocumentIdentifier,
};

pub const SymbolKind = enum(u32) {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26,
};

pub const DocumentSymbol = struct {
    name: []const u8,
    detail: ?[]const u8 = null,
    kind: SymbolKind,
    range: Range,
    selectionRange: Range,
    children: ?[]DocumentSymbol = null,
};

pub const SymbolInformation = struct {
    name: []const u8,
    kind: SymbolKind,
    location: Location,
    containerName: ?[]const u8 = null,
};

// Definition
pub const DefinitionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

// TextDocumentPositionParams (used by hover, definition, etc.)
pub const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

// Document Highlight
pub const DocumentHighlightKind = enum(u32) {
    Text = 1,
    Read = 2,
    Write = 3,
};

pub const DocumentHighlight = struct {
    range: Range,
    kind: ?DocumentHighlightKind = null,
};

// Folding Range
pub const FoldingRangeKind = enum {
    comment,
    imports,
    region,
};

pub const FoldingRange = struct {
    startLine: u32,
    startCharacter: ?u32 = null,
    endLine: u32,
    endCharacter: ?u32 = null,
    kind: ?FoldingRangeKind = null,
};
