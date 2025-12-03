# Metafrastis.nvim

Translate text inside Neovim through multiple backends (Google Translate/Cloud, DeepL, OpenAI, Google Gemini, OpenRouter) with caching and simple cost guards. Designed to stay cheap at scale: default settings favor low-cost models, reuse cached results, and block unusually expensive calls.

## Features

- Range-aware command `:MetafrastisTranslate` with optional bang to replace buffer text.
- Pluggable providers with shared HTTP abstraction; drop in your own provider if needed.
- File-backed cache under `stdpath('cache')/metafrastis` to avoid paying twice.
- Cost estimation per provider with a configurable safety ceiling.
- Minimal dependencies: uses `curl` and Neovim's standard Lua APIs.

## Installation

Use your preferred plugin manager; examples:

```lua
-- lazy.nvim
{
  "zchee/metafrastis.nvim",
  config = function()
    require("metafrastis").setup()
  end,
}
```

## Configuration

```lua
require("metafrastis").setup({
  provider = "openai", -- auto-falls back to echo if missing API key
  target_lang = "en",
  max_chars = 8000,
  cache = {
    enabled = true,
    ttl = 7 * 24 * 3600,
    max_estimated_cost = 1.0, -- USD per call guard
  },
  http = {
    backend = "curl", -- set to "plenary" to use plenary.curl if curl is unavailable
  },
  providers = {
    openai = {
      api_key = os.getenv("OPENAI_API_KEY"),
      model = "gpt-4o-mini",
    },
    google = {
      api_key = os.getenv("GOOGLE_API_KEY") or os.getenv("GOOGLE_TRANSLATE_KEY"),
    },
    deepl = {
      api_key = os.getenv("DEEPL_API_KEY"),
    },
    gemini = {
      api_key = os.getenv("GOOGLE_GENAI_KEY"),
      model = "gemini-2.5-flash",
    },
    openrouter = {
      api_key = os.getenv("OPENROUTER_API_KEY"),
      model = "openrouter/auto",
    },
    echo = {
      suffix = "[echo]",
    },
  },
})
```

If a configured provider is missing credentials, Metafrastis falls back to the built-in `echo` provider so you can test locally without making paid calls.

## Commands

- `:MetafrastisTranslate [source] [target]`  
  - Operates on the given range (default current line).  
  - Use `!` to replace buffer text; otherwise it echoes the translation.  
  - Examples:  
    - `:'<,'>MetafrastisTranslate en es!` (replace visual selection)  
    - `:MetafrastisTranslate es` (auto-detect source, echo Spanish translation)
- `:MetafrastisCacheClear` — purge on-disk cache.

## Cost guidance (2025-12)

- Google Cloud Translate v2 text: ~$20 per million chars (first 500k chars/month free).  
- DeepL API Pro: ~$25 per million chars (+base fee).  
- OpenAI gpt-4o-mini: ~$0.15/M input tokens + $0.60/M output tokens (≈0.00075 USD per ~1k chars round trip).  
- Gemini 2.5 Flash: ~$0.30/M input tokens + $2.50/M output tokens.  
- OpenRouter adds ~5% platform fee on top of model rates.  
Use caching and the `max_estimated_cost` guard to stay within budget; at ~50 tokens/request and 50k requests, gpt-4o-mini stays well under $50/month with caching.

### Refreshing prices
- Edit `lua/metafrastis/config.lua` `pricing_last_review` and provider price fields when rates change.  
- Adjust `cache.max_estimated_cost` to your comfort ceiling; example for small snippets: `0.25` (25¢ per request), for large documents raise accordingly.  
- Tune `max_chars` to match typical request size; smaller values reduce worst-case cost and latency.

## Testing

```
make test
```

Tests run in headless Neovim with Plenary and use the built-in `echo` provider to avoid external network calls.
