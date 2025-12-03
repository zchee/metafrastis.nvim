# metafrastis.nvim Contributor Guide

This document provides essential information for contributing to metafrastis.nvim, a Neovim plugin built with Lua.

## Project Structure & Module Organization

```
.
├── lua/
│   ├── metafrastis/           # Plugin modules
│   │   └── module.lua          # Internal module files
│   └── metafrastis.lua         # Main plugin entry point
├── plugin/
│   └── metafrastis.lua         # Vim plugin loader (creates commands)
├── tests/
│   ├── metafrastis/
│   │   └── metafrastis_spec.lua  # Test files (_spec.lua suffix)
│   └── minimal_init.lua        # Test environment setup
├── doc/                        # Auto-generated vimdocs
├── .github/workflows/          # CI/CD automation
├── Makefile                    # Build and test commands
└── .stylua.toml               # Code formatter configuration
```

**Module Organization:**
- `lua/metafrastis/`: Internal modules and utilities
- `lua/metafrastis.lua`: Main API with `setup()` function and public interface
- `plugin/metafrastis.lua`: Neovim autoload entry point for commands/autocommands

## Build, Test, and Development Commands

```bash
# Run all tests using Plenary.nvim
make test

# Format code with StyLua
stylua lua/

# Check formatting (CI)
stylua --check lua/
```

Tests run in headless Neovim with Plenary.nvim. The Makefile handles test initialization automatically.

## Coding Style & Naming Conventions

**Formatting Rules (enforced by StyLua):**
- **Indentation:** 2 spaces
- **Line width:** 120 characters
- **Line endings:** Unix (LF)
- **Quote style:** Auto-prefer double quotes
- **Call parentheses:** Always required

**Lua Conventions:**
- Use LuaLS annotations (`---@class`, `---@param`, `---@return`)
- Module pattern: Return table assigned to local `M`
- Config tables: Use `---@class Config` for type definitions
- Function signatures: Document all parameters and return types

**Example:**
```lua
---@class CustomModule
local M = {}

---@param greeting string
---@return string
M.my_function = function(greeting)
  return greeting
end

return M
```

## Testing Guidelines

**Framework:** [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) with Busted-style tests

**File Naming:**
- Test files: `tests/metafrastis/<module_name>_spec.lua`
- Use `_spec.lua` suffix for all test files

**Test Structure:**
```lua
local plugin = require("metafrastis")

describe("feature name", function()
  it("does something specific", function()
    assert(plugin.hello() == "expected", "descriptive failure message")
  end)
end)
```

**Running Tests:**
- Locally: `make test`
- CI: Automatically runs on push/PR for `stable` and `nightly` Neovim on Ubuntu, macOS, and Windows

## Commit & Pull Request Guidelines

**Commit Messages:**
- Use conventional commits format: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
- Examples:
  - `feat(core): add translation cache support`
  - `fix(api): handle nil config values`
  - `docs: update installation instructions`

**Pull Requests:**
- Ensure all tests pass (`make test`)
- Format code with StyLua before committing
- Update documentation if adding/changing APIs
- Reference related issues with `#issue-number`
- CI must pass:
  - StyLua formatting check
  - Tests on Ubuntu, macOS, Windows (stable + nightly Neovim)

**Pre-commit Checklist:**
- [ ] Code formatted with StyLua
- [ ] Tests added/updated for changes
- [ ] All tests passing locally
- [ ] LuaLS annotations added for new functions
- [ ] Documentation updated if needed
