---@class MetafrastisCacheConfig
---@field enabled boolean
---@field ttl number
---@field dir string
---@field max_estimated_cost number
---@field memory_enabled boolean
---@field memory_max_entries integer
---@field memory_skip_disk_ttl integer

---@class MetafrastisHttpConfig
---@field timeout integer
---@field backend string? "curl"|"plenary"

---@class MetafrastisProviderConfig
---@field api_key string?
---@field model string?
---@field base_url string?
---@field glossary_id string?
---@field referer string?

---@class MetafrastisConfig
---@field provider string
---@field target_lang string
---@field source_lang string|nil
---@field replace boolean
---@field max_chars integer
---@field cache MetafrastisCacheConfig
---@field http MetafrastisHttpConfig
---@field providers table<string, MetafrastisProviderConfig>
---@field pricing_last_review string

local M = {}

local function default_cache_dir()
  return vim.fn.stdpath("cache") .. "/metafrastis"
end

---@return MetafrastisConfig
function M.defaults()
  return {
    provider = "openai",
    target_lang = "en",
    source_lang = nil,
    replace = false,
    max_chars = 8000,
    cache = {
      enabled = true,
      ttl = 7 * 24 * 3600,
      dir = default_cache_dir(),
      max_estimated_cost = 1.0,
      memory_enabled = true,
      memory_max_entries = 512,
      memory_skip_disk_ttl = 5,
    },
    pricing_last_review = "2025-12-03",
    http = {
      timeout = 20000, -- milliseconds
      backend = "plenary",
    },
    providers = {
      echo = {
        suffix = "[echo]",
      },
      google = {
        api_key = vim.env.GOOGLE_API_KEY or vim.env.GOOGLE_TRANSLATE_KEY,
        model = "v2",
        base_url = "https://translation.googleapis.com/language/translate/v2",
        price_per_million_chars = 20.0,
      },
      deepl = {
        api_key = vim.env.DEEPL_API_KEY,
        base_url = "https://api-free.deepl.com/v2/translate",
        price_per_million_chars = 25.0,
      },
      openai = {
        api_key = vim.env.OPENAI_API_KEY,
        model = "gpt-4o-mini",
        base_url = "https://api.openai.com/v1/chat/completions",
        input_per_million = 0.15,
        output_per_million = 0.60,
      },
      gemini = {
        api_key = vim.env.GOOGLE_GENAI_KEY or vim.env.GOOGLE_API_KEY,
        model = "gemini-2.5-flash",
        base_url = "https://generativelanguage.googleapis.com/v1beta/models",
        input_per_million = 0.30,
        output_per_million = 2.50,
      },
      openrouter = {
        api_key = vim.env.OPENROUTER_API_KEY,
        model = "openrouter/auto",
        base_url = "https://openrouter.ai/api/v1/chat/completions",
        input_per_million = 0.15,
        output_per_million = 0.60,
        referer = "https://github.com/zchee/metafrastis.nvim",
      },
    },
  }
end

---@param opts table|nil
---@return MetafrastisConfig
function M.merge(opts)
  return vim.tbl_deep_extend("force", M.defaults(), opts or {})
end

return M
