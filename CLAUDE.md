# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Reference

```bash
make test                    # Run all tests (headless Neovim + Plenary)
stylua lua/ plugin/          # Format all Lua code
stylua --check lua/          # Check formatting (CI mode)
```

Tests auto-clone plenary.nvim to `/tmp/plenary.nvim`. No other setup needed.

## What This Plugin Does

**metafrastis.nvim** translates text in Neovim via pluggable backends (Google Translate, DeepL, OpenAI, Gemini, OpenRouter) with two-tier caching (memory + disk), cost guards, and optional Snacks.nvim UI.

## Architecture

Entry points:
- `lua/metafrastis.lua` — public API: `setup()`, `translate()`, `translate_async()`, `translate_range()`, `register_provider()`
- `plugin/metafrastis.lua` — user commands: `MetafrastisTranslate`, `MetafrastisTranslateUI`, `MetafrastisCacheClear`

Translation flow: `command → comment.strip_lines → cache.get → registry.translate → cache.put → apply output (buffer replace / ui.show_window / echo)`

Key modules under `lua/metafrastis/`:
- `providers/` — each provider exports `translate()`, `validate()`, `estimate_cost()`; registry in `providers/init.lua`
- `http.lua` — curl abstraction with plenary.job (async) or vim.system (sync) backends
- `cache.lua` — FIFO memory tier + disk files under `stdpath('cache')/metafrastis`; TTL-aware
- `ui.lua` — Snacks.win integration with fallbacks to `vim.notify`/`vim.ui.input`/echo
- `comment.lua` — strips and reapplies comment leaders based on buffer `commentstring`
- `config.lua` — defaults with env-var resolution for API keys; pricing data

## Coding Conventions

- **See AGENTS.md** for full style guide, provider implementation template, and testing patterns
- StyLua enforced: 2-space indent, 120-char lines, double quotes, Unix line endings (`.stylua.toml`)
- Module pattern: `local M = {} ... return M`
- All public functions require LuaLS annotations (`---@param`, `---@return`, `---@class`)
- Naming: `snake_case` everywhere; prefix internal helpers with `_`
- Commit style: Conventional Commits — `type(scope): description`

## Testing

- Framework: Plenary.nvim Busted (`describe`/`it`/`before_each`)
- Test files: `tests/metafrastis/<module>_spec.lua`
- Use `_reset_for_tests()` in `before_each` to clear module state
- Mock snacks via `package.loaded["snacks"]`; clean in `after_each`
- Use `echo` provider to avoid network calls
- CI runs on Ubuntu/macOS/Windows × Neovim stable/nightly

## Dependencies

| Module | Required | Notes |
|--------|----------|-------|
| plenary.nvim | For tests; optional at runtime | HTTP backend, test framework |
| snacks.nvim | Optional | UI windows/notifications; graceful fallback when absent |

## Context Files

Read `.agents/llms/*.xml` for Neovim/Snacks/Plenary API context when working on this codebase.
