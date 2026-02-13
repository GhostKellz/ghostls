# Neovim Integration for ghostls

This guide covers setting up the Ghostlang Language Server (ghostls) in Neovim.

## Prerequisites

- Neovim 0.8+ (for native LSP support)
- ghostls binary installed and in PATH
- nvim-lspconfig (recommended)

## Installation

### Build from Source

```bash
git clone https://github.com/ghostkellz/ghostls
cd ghostls
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/ghostls /usr/local/bin/
```

### Verify Installation

```bash
ghostls --version
# Should output: ghostls 0.7.0
```

## Neovim Configuration

### With nvim-lspconfig (Recommended)

Add to your Neovim config:

```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- Define ghostls configuration
if not configs.ghostls then
  configs.ghostls = {
    default_config = {
      cmd = { 'ghostls' },
      filetypes = { 'ghostlang' },
      root_dir = lspconfig.util.root_pattern('.git', 'ghostlang.toml'),
      settings = {},
    },
  }
end

-- Setup ghostls
lspconfig.ghostls.setup({
  on_attach = function(client, bufnr)
    -- Enable completion triggered by <c-x><c-o>
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Mappings
    local opts = { noremap=true, silent=true, buffer=bufnr }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', '<space>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set('n', '<space>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<space>f', function() vim.lsp.buf.format { async = true } end, opts)
  end,
  capabilities = require('cmp_nvim_lsp').default_capabilities(),
})
```

### Manual Configuration (Without lspconfig)

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'ghostlang',
  callback = function()
    vim.lsp.start({
      name = 'ghostls',
      cmd = { 'ghostls' },
      root_dir = vim.fs.dirname(vim.fs.find({ '.git', 'ghostlang.toml' }, { upward = true })[1]),
    })
  end,
})
```

### File Type Detection

Ensure Neovim recognizes Ghostlang files:

```lua
vim.filetype.add({
  extension = {
    ghost = 'ghostlang',
    gza = 'ghostlang',
  },
})
```

## Features

ghostls provides the following LSP features:

| Feature | Status | Description |
|---------|--------|-------------|
| Diagnostics | Full | Syntax errors and warnings |
| Hover | Full | Documentation on hover |
| Completion | Full | Context-aware completions |
| Go to Definition | Full | Jump to function/variable definition |
| Find References | Full | Find all references |
| Document Symbols | Full | Outline view |
| Workspace Symbols | Full | Project-wide symbol search |
| Rename | Full | Rename symbol across files |
| Code Actions | Partial | Quick fixes (expanding) |
| Semantic Tokens | Full | Enhanced highlighting |
| Folding | Full | Code folding ranges |

### v0.7.0 Features

- **Optional Chaining Support**: Hover and completions for `?.` syntax
- **Nullish Coalescing Support**: Hover and completions for `??` syntax
- **New Built-ins**: `map`, `filter`, `sort`, `keys`, `values`, `type`, `tostring`, `tonumber`

## Debugging

### Enable Debug Logging

```bash
ghostls --log-level=debug
```

Or in Neovim:

```lua
vim.lsp.set_log_level('debug')
-- Log file: ~/.local/state/nvim/lsp.log
```

### Check LSP Status

```vim
:LspInfo
:LspLog
```

## Integration with Tree-sitter

For best results, use ghostls alongside nvim-treesitter with the Ghostlang grammar:

```lua
-- Install tree-sitter-ghostlang (see docs/NEOVIM.md in tree-sitter-ghostlang)
-- Then enable tree-sitter highlighting

require('nvim-treesitter.configs').setup({
  highlight = { enable = true },
  indent = { enable = true },
})
```

This provides:
- Faster, more accurate highlighting (tree-sitter)
- Full IDE features (ghostls LSP)

## Troubleshooting

### Server Not Starting

1. Verify ghostls is in PATH: `which ghostls`
2. Check permissions: `ghostls --version`
3. Look at LSP logs: `:LspLog`

### No Completions

1. Ensure file type is correct: `:set filetype?`
2. Check if LSP is attached: `:LspInfo`
3. Verify trigger characters (`.`, `:`)

### Hover Not Working

1. Check cursor is on identifier
2. Verify LSP attachment: `:LspInfo`
3. Try `:lua vim.lsp.buf.hover()`

## Resources

- [ghostls GitHub](https://github.com/ghostkellz/ghostls)
- [Ghostlang](https://github.com/ghostlang/ghostlang)
- [tree-sitter-ghostlang](https://github.com/ghostkellz/tree-sitter-ghostlang)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
