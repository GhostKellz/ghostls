# Neovim Configuration for ghostls

This directory contains configuration for using **ghostls** with Neovim.

## Quick Setup

### Using nvim-lspconfig

Add to your Neovim config (`init.lua` or `~/.config/nvim/lua/lsp.lua`):

```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

-- Register ghostls if not already registered
if not configs.ghostls then
  configs.ghostls = {
    default_config = {
      cmd = { 'ghostls' }, -- Ensure ghostls is in your PATH
      filetypes = { 'ghostlang', 'ghost', 'gza' },
      root_dir = lspconfig.util.root_pattern('.git', '.ghostlang'),
      settings = {},
    },
  }
end

-- Setup ghostls
lspconfig.ghostls.setup{
  on_attach = function(client, bufnr)
    -- Enable completion
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- Key mappings
    local bufopts = { noremap=true, silent=true, buffer=bufnr }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
  end,
  capabilities = require('cmp_nvim_lsp').default_capabilities() -- If using nvim-cmp
}
```

### File type detection

Add to `~/.config/nvim/ftdetect/ghostlang.vim` or `~/.config/nvim/filetype.lua`:

**VimScript** (`ftdetect/ghostlang.vim`):
```vim
au BufRead,BufNewFile *.ghost set filetype=ghostlang
au BufRead,BufNewFile *.gza set filetype=ghostlang
```

**Lua** (`filetype.lua`):
```lua
vim.filetype.add({
  extension = {
    ghost = 'ghostlang',
    gza = 'ghostlang',
  },
})
```

## Installation

1. **Build ghostls:**
   ```bash
   cd /path/to/ghostls
   zig build -Drelease-safe
   ```

2. **Install to PATH:**
   ```bash
   sudo cp zig-out/bin/ghostls /usr/local/bin/
   # OR add to PATH
   export PATH="/path/to/ghostls/zig-out/bin:$PATH"
   ```

3. **Verify:**
   ```bash
   ghostls --version  # Should work once we add --version flag
   ```

## Features

- ✅ **Syntax diagnostics** - Real-time error detection
- ✅ **Hover** - Show type/documentation on hover
- ✅ **Go to definition** - Jump to symbol definitions
- ✅ **Document symbols** - Outline view
- ✅ **Completions** - Ghostlang keywords + built-in functions

## Troubleshooting

### LSP not starting

Check logs:
```vim
:LspInfo
:LspLog
```

### Check if ghostls is running

```bash
ps aux | grep ghostls
```

### Manual test

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}' | ghostls
```

## Advanced Configuration

### Custom settings

```lua
lspconfig.ghostls.setup{
  settings = {
    ghostls = {
      -- Future: custom settings here
    }
  }
}
```

### With nvim-cmp (autocompletion)

```lua
local cmp = require('cmp')
cmp.setup({
  sources = {
    { name = 'nvim_lsp' },
    -- other sources...
  },
})
```

## Integration with Grim

When using Grim editor (the Neovim alternative), ghostls will be integrated natively via `.gza` plugins.
