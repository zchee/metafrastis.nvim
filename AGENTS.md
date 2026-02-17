# Repository Guidelines

This document provides essential information for contributing to **metafrastis.nvim**, a Neovim plugin for translating text using multiple translation providers (Google, DeepL, OpenAI, Gemini, OpenRouter).

## Important

- This codebase is in early development. Large-scale refactoring is acceptable when necessary.
- **MUST READ** the following files for context on Neovim Lua plugin development:
  - `.agent/llms/neovim.io.xml`
  - `.agent/llms/snacks.nvim.xml`
  - `.agent/llms/plenary.nvim.xml`

## Project Structure & Module Organization

```
.
├── lua/
│   ├── metafrastis.lua              # Main plugin entry point with public API
│   └── metafrastis/
│       ├── cache.lua                # Disk and memory caching
│       ├── comment.lua              # Comment stripping/reapplication
│       ├── config.lua               # Configuration schema and defaults
│       ├── http.lua                 # HTTP client (curl/plenary.job)
│       ├── ui.lua                   # Snacks.win integration and fallbacks
│       ├── util.lua                 # Utility functions
│       └── providers/
│           ├── init.lua             # Provider registry
│           ├── echo.lua             # Echo provider (testing)
│           ├── google.lua           # Google Translate API
│           ├── deepl.lua            # DeepL API
│           ├── openai.lua           # OpenAI Chat API
│           ├── gemini.lua           # Google Gemini API
│           └── openrouter.lua       # OpenRouter API
├── plugin/
│   └── metafrastis.lua              # Neovim autoload (creates user commands)
├── tests/
│   ├── minimal_init.lua             # Test environment setup
│   └── metafrastis/
│       ├── metafrastis_spec.lua     # Core functionality tests
│       └── cache_spec.lua           # Cache tests
├── .github/workflows/
│   ├── lint-test.yaml               # CI: StyLua check + tests
│   ├── release.yaml                 # Release automation
│   └── docs.yaml                    # Documentation generation
├── .agent/
│   └── llms/                        # LLM context files for dependencies
├── Makefile                         # Build/test commands
└── .stylua.toml                     # StyLua configuration
```

**Key Architecture Patterns:**

- `lua/metafrastis.lua`: Public API (`setup()`, `translate()`, `translate_async()`, `translate_range()`)
- `lua/metafrastis/providers/`: Provider implementations with `translate()`, `validate()`, and `estimate_cost()` functions
- `plugin/metafrastis.lua`: User commands (`MetafrastisTranslate`, `MetafrastisTranslateUI`, `MetafrastisCacheClear`)

## Build, Test, and Development Commands

```bash
# Run all tests (headless Neovim with Plenary.nvim)
make test

# Format code with StyLua
stylua lua/

# Check formatting (CI mode)
stylua --check lua/

# Run tests manually with verbose output
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

**Notes:**

- Tests require Plenary.nvim (auto-cloned to `/tmp/plenary.nvim` by `minimal_init.lua`)
- Tests mock `snacks` module for UI testing without runtime dependency
- Use `_reset_for_tests()` helper on modules when writing tests

## Coding Style & Naming Conventions

**Formatting (enforced by StyLua - `.stylua.toml`):**

| Rule | Value |
|------|-------|
| Indentation | 2 spaces |
| Line width | 120 characters |
| Line endings | Unix (LF) |
| Quote style | Auto-prefer double quotes |
| Call parentheses | Always required |

**Lua Conventions:**

- Use LuaLS type annotations: `---@class`, `---@param`, `---@return`, `---@field`
- Module pattern: `local M = {} ... return M`
- Config tables: Define with `---@class` for type safety
- All public functions must have parameter and return type annotations
- End godoc-style comments with a period

**Naming Patterns:**

- Functions: `snake_case` (e.g., `translate_async`, `estimate_cost`)
- Local variables: `snake_case`
- Module tables: `M` for the returned module
- Test files: `<module_name>_spec.lua`
- Private/internal: Prefix with underscore (e.g., `_reset_for_tests`)

**Example Module:**

```lua
---@class MyModule
local M = {}

---Translates text to the target language.
---@param text string The text to translate.
---@param opts table|nil Optional configuration.
---@return string translated The translated text.
function M.translate(text, opts)
  -- implementation
end

return M
```

## Provider Implementation

When adding a new translation provider:

1. Create `lua/metafrastis/providers/<name>.lua`
2. Implement required interface:

```lua
local M = {}

M.name = "provider_name"

---Validates provider configuration.
---@param cfg table Provider-specific config from config.providers.<name>.
---@return boolean, string|nil
function M.validate(cfg)
  if not cfg.api_key or cfg.api_key == "" then
    return false, "provider requires api_key"
  end
  return true
end

---Performs translation.
---@param _http fun(method: string, url: string, opts: table): table
---@param payload table Contains text, target_lang, source_lang, config.
---@return string
function M.translate(_http, payload)
  -- Implementation
end

---Estimates cost in USD.
---@param payload table
---@return number|nil
function M.estimate_cost(payload)
  -- Implementation
end

return M
```

3. Register in `lua/metafrastis.lua` `register_builtin()`
4. Add default config in `lua/metafrastis/config.lua`

## Testing Guidelines

**Framework:** [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) with Busted-style syntax

**File Location:** `tests/metafrastis/<module_name>_spec.lua`

**Test Structure:**

```lua
local metafrastis = require("metafrastis")
local registry = require("metafrastis.providers")

describe("feature name", function()
  before_each(function()
    metafrastis._reset_for_tests()
  end)

  after_each(function()
    -- Cleanup mocks
    package.loaded["snacks"] = nil
  end)

  it("does something specific", function()
    -- Arrange
    metafrastis.setup({ provider = "echo" })

    -- Act
    local result = metafrastis.translate("Hello", { target_lang = "es" })

    -- Assert
    assert.equals("Hello [echo]->es", result)
  end)
end)
```

**Testing Patterns:**

- Use `metafrastis._reset_for_tests()` in `before_each` to reset state
- Mock external modules via `package.loaded["module"] = { ... }`
- Use `vim.wait()` for async tests
- Register test providers via `registry.register("name", { translate = ..., estimate_cost = ... })`
- Clean up mocks in `after_each`

**Running Tests:**

- Local: `make test`
- CI: Runs on push/PR for `stable` and `nightly` Neovim on Ubuntu, macOS, and Windows

## Commit & Pull Request Guidelines

**Commit Message Format (Conventional Commits):**

```
type(scope): description

[optional body]
```

**Types:**

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code restructuring |
| `test` | Adding/updating tests |
| `chore` | Maintenance tasks |

**Examples from repository history:**

```
feat(ui): show icon to title
fix(config): change gemini api_key to GOOGLE_API_KEY and GEMINI_API_KEY
feat(core): add async translate and UI command
test(ui): cover Snacks.win rendering and fallbacks
docs: document async UI workflow
```

**Pull Request Requirements:**

1. All tests pass (`make test`)
2. Code formatted with StyLua
3. LuaLS annotations for new/changed functions
4. Reference related issues with `#issue-number`

**Pre-commit Checklist:**

- [ ] Code formatted with `stylua lua/`
- [ ] Tests added/updated for changes
- [ ] All tests passing locally (`make test`)
- [ ] LuaLS annotations added for new functions
- [ ] No breaking changes to public API without discussion

**CI Checks:**

- StyLua formatting verification
- Tests on Ubuntu, macOS, Windows (stable + nightly Neovim)

## Architecture Overview

**Translation Flow:**

```
User Command → translate_range[_async] → comment.strip_lines
                                      → cache.get (check cache)
                                      → registry.translate (call provider)
                                      → cache.put (store result)
                                      → apply_translation_output
                                          ├→ replace buffer lines
                                          ├→ ui.show_window (Snacks.win)
                                          └→ vim.api.nvim_echo (fallback)
```

**Key Dependencies:**

| Module | Purpose | Optional |
|--------|---------|----------|
| plenary.nvim | HTTP, async, testing | Required for tests, optional at runtime |
| snacks.nvim | UI windows, notifications, input | Optional (fallback to vim.ui) |

**Configuration Resolution:**

1. `config.lua:defaults()` provides base configuration
2. User calls `setup(opts)` which merges via `vim.tbl_deep_extend`
3. Provider validation runs; invalid providers fall back to `echo`
4. Per-call options override config at translate time

## Environment Variables

| Variable | Provider | Description |
|----------|----------|-------------|
| `GOOGLE_API_KEY` | google, gemini | Google Cloud API key |
| `GOOGLE_TRANSLATE_KEY` | google | Alternative for Google Translate |
| `GEMINI_API_KEY` | gemini | Alternative for Gemini API |
| `DEEPL_AUTH_KEY` | deepl | DeepL authentication key |
| `OPENAI_API_KEY` | openai | OpenAI API key |
| `OPENROUTER_API_KEY` | openrouter | OpenRouter API key |
