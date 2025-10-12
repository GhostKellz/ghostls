# 👻 ghostls Wishlist for GShell Integration

<div align="center">
  <strong>What GShell needs from ghostls for intelligent shell scripting</strong>
</div>

---

## 📋 Current Status

✅ **Already Have:**
- v0.2.0 complete with all core LSP features
- Find references, workspace symbols, context-aware completions
- Go-to-definition, hover, diagnostics
- Document symbols, incremental parsing
- Tree-sitter powered by Grove
- Grim, Neovim, VSCode integration ready

⏳ **Supported Languages:**
- ✅ Ghostlang (.gza, .ghost files)

---

## 🎯 What GShell Needs

### **P0: Critical Path** (Needed for GShell v0.2.0 - Next 4 weeks)

#### 1. **Shell Script Language Support**

ghostls should recognize and support GShell configuration files:

**File Types to Support:**
- `.gshrc.gza` - GShell startup script (Ghostlang)
- `.gshrc` - Traditional shell config (if we support it)
- `*.gsh` - GShell script files
- Inline Ghostlang in shell commands (`$(...)`)

**What This Means:**
```lua
-- ~/.gshrc.gza
-- This is a Ghostlang script, but with shell-specific FFI

-- Shell-specific global variables
print(SHELL_VERSION)  -- "GShell 0.2.0"
print(SHELL_PID)      -- Current shell process ID

-- Shell FFI functions (exposed by GShell)
shell.alias("ll", "ls -la")
shell.setenv("EDITOR", "grim")
shell.prompt_format("[%u@%h %w]$ ")

-- Git-aware prompt
shell.on_prompt(function()
  local branch = git.current_branch()
  if branch then
    return "[" .. branch .. "]$ "
  end
  return "$ "
end)

-- Auto-completion hooks
shell.register_completer("git", function(args)
  return {"add", "commit", "push", "pull", "status"}
end)
```

**LSP Features Needed:**
```lua
-- 1. Completions for shell-specific FFI
shell.|
      ^ Suggest: alias, setenv, prompt_format, on_prompt, register_completer

-- 2. Hover documentation
shell.alias(...)
^^^^^^^^^^^^^
Shows: shell.alias(name: string, command: string)
       Create a shell alias

-- 3. Go-to-definition for aliases
alias("ll", "ls -la")
      ^^
Go to: Definition of 'll' alias

-- 4. Diagnostics for invalid shell commands
shell.alias("ls", "nonexistent_command")
                  ^^^^^^^^^^^^^^^^^^^^
Warning: Command 'nonexistent_command' not found in PATH

-- 5. Signature help
shell.on_prompt(|
                ^ Show function signature: (callback: function(): string)
```

#### 2. **Shell FFI Definitions** (`shell_ffi.lua` or `shell_ffi.json`)

Provide type definitions for GShell's exposed FFI functions:

**Format (JSON for LSP):**
```json
{
  "shell": {
    "functions": {
      "alias": {
        "signature": "(name: string, command: string) -> void",
        "description": "Create a shell alias",
        "example": "shell.alias('ll', 'ls -la')"
      },
      "setenv": {
        "signature": "(key: string, value: string) -> void",
        "description": "Set environment variable",
        "example": "shell.setenv('EDITOR', 'grim')"
      },
      "prompt_format": {
        "signature": "(format: string) -> void",
        "description": "Set shell prompt format\n\nFormat codes:\n  %u - username\n  %h - hostname\n  %w - working directory\n  %t - time",
        "example": "shell.prompt_format('[%u@%h %w]$ ')"
      },
      "on_prompt": {
        "signature": "(callback: function(): string) -> void",
        "description": "Register prompt callback for dynamic prompts",
        "example": "shell.on_prompt(function() return git.branch() .. '$ ' end)"
      },
      "register_completer": {
        "signature": "(command: string, completer: function(args: string[]): string[]) -> void",
        "description": "Register custom tab completion for command",
        "example": "shell.register_completer('git', function(args) return {'add', 'commit'} end)"
      }
    },
    "globals": {
      "SHELL_VERSION": {
        "type": "string",
        "description": "GShell version (e.g., '0.2.0')"
      },
      "SHELL_PID": {
        "type": "number",
        "description": "Current shell process ID"
      },
      "HOME": {
        "type": "string",
        "description": "User home directory"
      },
      "PWD": {
        "type": "string",
        "description": "Current working directory"
      },
      "PATH": {
        "type": "string",
        "description": "Executable search path"
      }
    }
  },
  "git": {
    "functions": {
      "current_branch": {
        "signature": "() -> string | nil",
        "description": "Get current git branch name, or nil if not in git repo",
        "example": "local branch = git.current_branch()"
      },
      "is_dirty": {
        "signature": "() -> boolean",
        "description": "Check if git repo has uncommitted changes",
        "example": "if git.is_dirty() then print('*') end"
      },
      "ahead_behind": {
        "signature": "() -> {ahead: number, behind: number} | nil",
        "description": "Get commits ahead/behind remote",
        "example": "local status = git.ahead_behind()"
      }
    }
  }
}
```

**Use Case:**
```lua
-- User edits ~/.gshrc.gza in Grim
shell.ali|
         ^ Completions: alias, (nothing else)

shell.alias("ll", |
                  ^ Signature help shows: (name: string, command: string)

git.curr|
        ^ Completions: current_branch

local branch = git.current_branch()
               ^^^^^^^^^^^^^^^^^^^
               Hover: () -> string | nil
                      Get current git branch name
```

#### 3. **Diagnostics for Shell Scripts**

Validate shell scripts for common errors:

```lua
-- 1. Invalid FFI calls
shell.nonexistent()
      ^^^^^^^^^^^^
Error: Unknown function 'shell.nonexistent'
Available: alias, setenv, prompt_format, ...

-- 2. Wrong argument types
shell.alias(123, "ls -la")  -- name should be string
            ^^^
Error: Expected string, got number

-- 3. Undefined variables
print(UNDEFINED_VAR)
      ^^^^^^^^^^^^^
Warning: Undefined variable 'UNDEFINED_VAR'

-- 4. Syntax errors
shell.alias("ll", "ls -la"  -- Missing closing paren
                          ^
Error: Expected ')' but found end of file
```

---

### **P1: Important** (Needed for GShell v0.3.0 - 4-8 weeks)

#### 4. **Workspace-wide Symbol Search for Shell Functions**

Find shell functions across all .gshrc.gza files:

```lua
-- In ~/.gshrc.gza
function my_custom_prompt()
  return "[" .. os.date("%H:%M") .. "]$ "
end

-- In ~/dotfiles/gshell/functions.gza
function git_prompt()
  return "[" .. git.current_branch() .. "]$ "
end

-- Workspace symbol search:
Ctrl+T -> "prompt"
Results:
  - my_custom_prompt (file:///home/user/.gshrc.gza:3)
  - git_prompt (file:///home/user/dotfiles/gshell/functions.gza:12)
```

#### 5. **Code Actions for Common Shell Tasks**

Provide quick fixes and refactorings:

```lua
-- 1. Quick fix: Add missing shell import
print(SHELL_VERSION)
      ^^^^^^^^^^^^^
💡 Code action: Import shell module

-- 2. Refactor: Extract to function
shell.alias("ll", "ls -la")
shell.alias("la", "ls -A")
shell.alias("l", "ls -CF")
💡 Code action: Extract to setup_aliases()

-- 3. Quick fix: Correct typo
shell.alais("ll", "ls -la")
      ^^^^^
💡 Code action: Did you mean 'alias'?
```

#### 6. **Documentation Hover for Built-in Commands**

Provide help for shell built-ins:

```lua
shell.cd("/tmp")
      ^^
Hover: cd(path: string) -> boolean
       Change current directory
       Returns true on success, false on failure

       Example:
         if shell.cd("/tmp") then
           print("Changed to /tmp")
         end
```

---

### **P2: Nice to Have** (Needed for GShell v0.4.0+ - 8+ weeks)

#### 7. **Inlay Hints for Shell FFI**

Show inferred types inline:

```lua
local branch = git.current_branch()
      ^^^^^^ : string | nil

local status = git.ahead_behind()
      ^^^^^^ : {ahead: number, behind: number} | nil

shell.on_prompt(function()
                ^^^^^^^^ : () -> string
  return "$ "
end)
```

#### 8. **Call Hierarchy for Shell Functions**

See where shell functions are called:

```lua
-- Define
function my_prompt()
  return "$ "
end

-- Call 1
shell.on_prompt(my_prompt)

-- Call 2
local p = my_prompt()

-- Call hierarchy view:
my_prompt
├── shell.on_prompt (line 15)
└── local p = my_prompt() (line 23)
```

#### 9. **Semantic Tokens for Shell Variables**

Highlight environment variables differently:

```lua
print(PATH)      -- Highlight as environment variable (green)
print(HOME)      -- Highlight as environment variable (green)
print(my_var)    -- Highlight as local variable (white)
```

---

### **P3: Future Vision** (Nice to have, no timeline)

#### 10. **Shell Script Debugger Integration**

Support debugging .gshrc.gza:

```lua
-- Set breakpoint
function my_function()
  local x = 10  -- <-- Breakpoint here
  print(x)
end

-- Debug session:
Breakpoint hit at ~/.gshrc.gza:12
Variables:
  x = 10
  SHELL_VERSION = "0.2.0"
```

#### 11. **Performance Profiling**

Show slow functions in shell startup:

```lua
function slow_function()  -- ⚠️ Takes 250ms (shown in editor)
  -- Expensive operation
end
```

---

## 🔧 API Design Preferences

### **What GShell Prefers:**

1. **File Type Detection**: Auto-detect `.gshrc.gza` and `*.gsh` files
2. **Dynamic FFI Loading**: Load shell FFI definitions from JSON/Lua file
3. **Graceful Degradation**: Work even without FFI definitions (basic Ghostlang support)
4. **Fast Response**: <100ms for completions, <50ms for hover
5. **Offline Support**: Don't require network for FFI definitions

### **Configuration:**

```lua
-- In Grim's LSP config
lsp.setup("ghostls", {
  cmd = { "ghostls" },
  filetypes = { "ghostlang", "gza", "gsh", "gshrc" },
  settings = {
    ghostls = {
      shell_ffi = "~/.config/gshell/ffi.json",  -- Load GShell FFI definitions
      enable_shell_diagnostics = true,
    }
  }
})
```

---

## 📊 Integration Success Metrics

When ghostls integration is complete, GShell users editing `.gshrc.gza` should have:

- ✅ Completions for `shell.*` FFI functions
- ✅ Hover documentation for shell builtins
- ✅ Diagnostics for invalid FFI calls
- ✅ Go-to-definition for shell functions
- ✅ Find references for shell aliases
- ✅ Workspace symbol search across shell configs
- ✅ Signature help for shell FFI functions
- ✅ <100ms response time for completions

---

## 🤝 Collaboration

GShell is happy to:
- Provide shell FFI definitions in JSON format
- Test ghostls with real `.gshrc.gza` files
- Contribute PRs for shell-specific features
- Write integration tests

ghostls can prioritize:
- P0: Shell script support + FFI definitions (next 4 weeks)
- P1: Diagnostics + code actions (4-8 weeks)
- P2: Advanced features (8+ weeks)

**Let's build the best shell scripting experience ever!** 🚀

---

## 📞 Contact

For questions or coordination:
- Open an issue in GShell repo: [ghostkellz/gshell](https://github.com/ghostkellz/gshell)
- Reference this wishlist in ghostls issues/PRs
- Coordinate timelines in DRAFT_DISCOVERY.md

**Thank you for building ghostls!** 👻
