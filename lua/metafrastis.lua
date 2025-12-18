local cfg = require("metafrastis.config")
local cache = require("metafrastis.cache")
local http_builder = require("metafrastis.http")
local registry = require("metafrastis.providers")
local util = require("metafrastis.util")
local comment = require("metafrastis.comment")
local ui = require("metafrastis.ui")

local provider_google = require("metafrastis.providers.google")
local provider_deepl = require("metafrastis.providers.deepl")
local provider_openai = require("metafrastis.providers.openai")
local provider_gemini = require("metafrastis.providers.gemini")
local provider_openrouter = require("metafrastis.providers.openrouter")
local provider_echo = require("metafrastis.providers.echo")

---@class Metafrastis
---@field config MetafrastisConfig
---@field http fun(method: string, url: string, opts: table): table
---@field http_async fun(method: string, url: string, opts: table): table
local M = {
  config = cfg.defaults(),
}

M.http = http_builder.build(M.config.http)
M.http_async = http_builder.build_async(M.config.http)

local function register_builtin()
  registry.reset()
  registry.register(provider_echo.name, provider_echo)
  registry.register(provider_google.name, provider_google)
  registry.register(provider_deepl.name, provider_deepl)
  registry.register(provider_openai.name, provider_openai)
  registry.register(provider_gemini.name, provider_gemini)
  registry.register(provider_openrouter.name, provider_openrouter)
end

local function validate_provider(name, config_table)
  local provider = registry.get(name)
  if not provider then
    return false, "provider not found: " .. name
  end
  if provider.validate then
    return provider.validate(config_table.providers[name] or {})
  end
  return true
end

---@param opts table|nil
function M.setup(opts)
  register_builtin()
  local merged = cfg.merge(opts)
  local ok, err = validate_provider(merged.provider, merged)
  if not ok then
    vim.notify(string.format("metafrastis: %s; falling back to echo provider", err), vim.log.levels.WARN)
    merged.provider = "echo"
  end
  M.config = merged
  M.http = http_builder.build(merged.http)
  M.http_async = http_builder.build_async(merged.http)
  ui.set_defaults(merged.ui and merged.ui.win or {})
end

local function perform_translate(http_fn, text, opts)
  assert(type(text) == "string", "text must be a string")
  if text == "" then
    return "", { cached = false, provider = M.config.provider }
  end
  local options = opts or {}
  local config_table = M.config
  local provider_name = options.provider or config_table.provider
  local ok, err = validate_provider(provider_name, config_table)
  if not ok then
    vim.notify(string.format("metafrastis: %s; using echo provider", err), vim.log.levels.WARN)
    provider_name = "echo"
    config_table.provider = provider_name
  end
  local target_lang = options.target_lang or config_table.target_lang
  local source_lang = options.source_lang or config_table.source_lang
  local max_chars = config_table.max_chars or 8000
  if #text > max_chars then
    error(string.format("text too long (%d chars > %d)", #text, max_chars))
  end
  local payload = {
    text = text,
    target_lang = target_lang,
    source_lang = source_lang,
    config = config_table,
  }
  local estimated = registry.estimate_cost(provider_name, payload)
  if estimated and config_table.cache.max_estimated_cost and estimated > config_table.cache.max_estimated_cost then
    error(
      string.format(
        "estimated cost %.4f USD exceeds limit %.2f; shorten text or adjust config.cache.max_estimated_cost",
        estimated,
        config_table.cache.max_estimated_cost
      )
    )
  end

  local key = cache.make_key(provider_name, source_lang, target_lang, text)
  local cached = cache.get(config_table.cache, key)
  if cached then
    local cleaned_cached = util.normalize_newlines(cached)
    if cleaned_cached ~= cached then
      cache.put(config_table.cache, key, cleaned_cached)
    end
    return cleaned_cached, { cached = true, provider = provider_name }
  end

  local translated = registry.translate(provider_name, http_fn, payload)
  translated = util.normalize_newlines(translated)
  cache.put(config_table.cache, key, translated)
  return translated, { cached = false, provider = provider_name }
end

local function apply_translation_output(buffer, start_line, end_line, translated, opts, meta, info, parts, original_lines)
  local should_replace = opts and opts.replace or M.config.replace
  local translated_lines
  if original_lines and #original_lines > 0 then
    translated_lines = util.reflow_lines(translated, original_lines)
  else
    translated_lines = util.split_lines(translated)
  end
  local rendered = table.concat(translated_lines, "\n")
  local config_win = (M.config.ui and M.config.ui.win) or {}
  local user_win = (opts and opts.win) or {}
  local merged_win = vim.tbl_deep_extend("force", {}, config_win, user_win)

  if should_replace then
    if parts and info then
      translated_lines = comment.reapply(translated_lines, info, parts)
    end
    local new_lines = translated_lines
    if #new_lines == 0 then
      new_lines = { "" }
    end
    vim.api.nvim_buf_set_lines(buffer, start_line, end_line, false, new_lines)
    return rendered
  end

  if opts and opts.show_window then
    ui.show_window(rendered, meta, {
      target_lang = opts.target_lang or M.config.target_lang,
      source_lang = opts.source_lang or M.config.source_lang,
      win = merged_win,
      padding = merged_win and merged_win.padding or nil,
    })
    return rendered
  end

  vim.api.nvim_echo({ { rendered, "Normal" } }, false, {})
  return rendered
end

---@param text string
---@param opts table|nil
---@return string, table|nil
function M.translate(text, opts)
  local translated, meta = perform_translate(M.http, text, opts)
  return translated, meta
end

---@param bufnr integer|nil
---@param start_line integer
---@param end_line integer
---@param opts table|nil
---@return string
function M.translate_range(bufnr, start_line, end_line, opts)
  local buffer = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buffer, start_line, end_line, false)
  local stripped, info, parts = comment.strip_lines(lines, vim.bo[buffer] and vim.bo[buffer].commentstring or nil)
  local joined = table.concat(stripped, "\n")
  local translated, meta = M.translate(joined, opts)
  local rendered = apply_translation_output(
    buffer,
    start_line,
    end_line,
    translated,
    opts,
    meta,
    info,
    parts,
    stripped
  )
  return rendered or translated
end

---@param opts table command opts
function M.command(opts)
  local args = opts.fargs or {}
  local source
  local target
  if #args == 1 then
    target = args[1]
  elseif #args >= 2 then
    source = args[1]
    target = args[2]
  end
  local command_opts = {
    source_lang = source,
    target_lang = target,
    replace = opts.bang or M.config.replace,
  }
  local start_line = (opts.line1 or 1) - 1
  local end_line = opts.line2 or vim.api.nvim_buf_line_count(0)
  return M.translate_range(0, start_line, end_line, command_opts)
end

---@param text string
---@param opts table|nil
---@param callbacks {on_success?:fun(result:string, meta:table), on_error?:fun(err:any)}|nil
function M.translate_async(text, opts, callbacks)
  local cb = callbacks or {}
  local ok_async, async = pcall(require, "plenary.async")
  if not ok_async then
    local ok_sync, res, meta = pcall(perform_translate, M.http, text, opts)
    if ok_sync then
      if cb.on_success then
        vim.schedule(function()
          cb.on_success(res, meta)
        end)
      end
    elseif cb.on_error then
      vim.schedule(function()
        cb.on_error(res)
      end)
    end
    return
  end
  local http_fn = M.http_async or M.http
  async.void(function()
    local ok, result_or_err, meta = pcall(perform_translate, http_fn, text, opts)
    if ok then
      if cb.on_success then
        vim.schedule(function()
          cb.on_success(result_or_err, meta)
        end)
      end
    else
      if cb.on_error then
        vim.schedule(function()
          cb.on_error(result_or_err)
        end)
      end
    end
  end)()
end

---@param bufnr integer|nil
---@param start_line integer
---@param end_line integer
---@param opts table|nil
---@param callbacks {on_success?:fun(result:string, meta:table), on_error?:fun(err:any)}|nil
function M.translate_range_async(bufnr, start_line, end_line, opts, callbacks)
  local buffer = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buffer, start_line, end_line, false)
  local stripped, info, parts = comment.strip_lines(lines, vim.bo[buffer] and vim.bo[buffer].commentstring or nil)
  local joined = table.concat(stripped, "\n")
  local cb = callbacks or {}
  M.translate_async(joined, opts, {
    on_success = function(translated, meta)
      local rendered = apply_translation_output(
        buffer,
        start_line,
        end_line,
        translated,
        opts,
        meta,
        info,
        parts,
        stripped
      )
      if cb.on_success then
        cb.on_success(rendered or translated, meta)
      end
    end,
    on_error = function(err)
      if cb.on_error then
        cb.on_error(err)
      end
    end,
  })
end

---@param name string
---@param provider table
function M.register_provider(name, provider)
  registry.register(name, provider)
end

function M.clear_cache()
  cache.clear(M.config.cache)
end

-- Test helper
function M._reset_for_tests()
  M.config = cfg.defaults()
  register_builtin()
  M.http = http_builder.build(M.config.http)
  M.http_async = http_builder.build_async(M.config.http)
  cache.clear(M.config.cache)
end

return M
