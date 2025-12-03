local cfg = require("metafrastis.config")
local cache = require("metafrastis.cache")
local http_builder = require("metafrastis.http")
local registry = require("metafrastis.providers")
local util = require("metafrastis.util")

local provider_google = require("metafrastis.providers.google")
local provider_deepl = require("metafrastis.providers.deepl")
local provider_openai = require("metafrastis.providers.openai")
local provider_gemini = require("metafrastis.providers.gemini")
local provider_openrouter = require("metafrastis.providers.openrouter")
local provider_echo = require("metafrastis.providers.echo")

---@class Metafrastis
---@field config MetafrastisConfig
---@field http fun(method: string, url: string, opts: table): table
local M = {
  config = cfg.defaults(),
}

M.http = http_builder.build(M.config.http)

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
end

---@param text string
---@param opts table|nil
---@return string
function M.translate(text, opts)
  assert(type(text) == "string", "text must be a string")
  if text == "" then
    return ""
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
    return cached
  end

  local translated = registry.translate(provider_name, M.http, payload)
  cache.put(config_table.cache, key, translated)
  return translated
end

---@param bufnr integer|nil
---@param start_line integer
---@param end_line integer
---@param opts table|nil
---@return string
function M.translate_range(bufnr, start_line, end_line, opts)
  local buffer = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buffer, start_line, end_line, false)
  local joined = table.concat(lines, "\n")
  local translated = M.translate(joined, opts)
  local should_replace = opts and opts.replace or M.config.replace
  if should_replace then
    local new_lines = util.split_lines(translated)
    if #new_lines == 0 then
      new_lines = { "" }
    end
    vim.api.nvim_buf_set_lines(buffer, start_line, end_line, false, new_lines)
  else
    vim.api.nvim_echo({ { translated, "Normal" } }, false, {})
  end
  return translated
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
  cache.clear(M.config.cache)
end

return M
