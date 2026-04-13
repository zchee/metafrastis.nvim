local config = require("metafrastis.config")

local deepl = require("metafrastis.providers.deepl")
local echo = require("metafrastis.providers.echo")
local gemini = require("metafrastis.providers.gemini")
local google = require("metafrastis.providers.google")
local openai = require("metafrastis.providers.openai")
local openrouter = require("metafrastis.providers.openrouter")

---Helper: build a payload with the given text and provider config.
---@param text string
---@param provider_name string
---@param provider_cfg table|nil
---@return table
local function make_payload(text, provider_name, provider_cfg)
  local defaults = config.defaults()
  if provider_cfg then
    defaults.providers[provider_name] =
      vim.tbl_deep_extend("force", defaults.providers[provider_name] or {}, provider_cfg)
  end
  return {
    text = text,
    target_lang = "en",
    source_lang = "ja",
    config = defaults,
  }
end

-- ── echo ────────────────────────────────────────────────────────────────

describe("echo provider", function()
  it("has correct name", function()
    assert.equals("echo", echo.name)
  end)

  it("validates always", function()
    local ok = echo.validate({})
    assert.is_true(ok)
  end)

  it("translates by appending suffix and target", function()
    local payload = make_payload("hello", "echo", { suffix = "[echo]" })
    local result = echo.translate(nil, payload)
    assert.equals("hello [echo]->en", result)
  end)

  it("uses default suffix", function()
    local payload = make_payload("hi", "echo", {})
    payload.config.providers.echo.suffix = nil
    local result = echo.translate(nil, payload)
    assert.equals("hi [echo]->en", result)
  end)

  it("estimates cost near zero", function()
    local payload = make_payload("hello", "echo")
    local cost = echo.estimate_cost(payload)
    assert.is_number(cost)
    assert.truthy(cost < 0.001)
  end)

  it("estimate_cost handles nil payload", function()
    assert.equals(0, echo.estimate_cost(nil))
  end)
end)

-- ── google ──────────────────────────────────────────────────────────────

describe("google provider", function()
  it("has correct name", function()
    assert.equals("google", google.name)
  end)

  it("rejects empty api_key", function()
    local ok, err = google.validate({ api_key = "" })
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("rejects nil api_key", function()
    local ok, err = google.validate({})
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("accepts valid api_key", function()
    local ok = google.validate({ api_key = "test-key" })
    assert.is_true(ok)
  end)

  it("estimates cost based on character count", function()
    local payload = make_payload(string.rep("a", 1000), "google", { price_per_million_chars = 20 })
    local cost = google.estimate_cost(payload)
    assert.is_number(cost)
    -- 1000 chars at $20/million = $0.02
    assert.are.near(0.02, cost, 0.001)
  end)

  it("translates with mock http", function()
    local captured_method, captured_url, captured_opts
    local mock_http = function(method, url, opts)
      captured_method = method
      captured_url = url
      captured_opts = opts
      return {
        code = 0,
        stdout = vim.json.encode({
          data = { translations = { { translatedText = "translated" } } },
        }),
      }
    end
    local payload = make_payload("hello", "google", { api_key = "k", base_url = "https://example.com" })
    local result = google.translate(mock_http, payload)
    assert.equals("translated", result)
    assert.equals("POST", captured_method)
    assert.truthy(captured_url:find("example.com"))
    assert.truthy(captured_url:find("key=k"))
  end)

  it("errors on non-zero exit code", function()
    local mock_http = function()
      return { code = 1, stderr = "timeout" }
    end
    local payload = make_payload("hi", "google", { api_key = "k", base_url = "https://x.com" })
    assert.has_error(function()
      google.translate(mock_http, payload)
    end)
  end)

  it("errors on unexpected response", function()
    local mock_http = function()
      return { code = 0, stdout = "{}" }
    end
    local payload = make_payload("hi", "google", { api_key = "k", base_url = "https://x.com" })
    assert.has_error(function()
      google.translate(mock_http, payload)
    end)
  end)
end)

-- ── deepl ───────────────────────────────────────────────────────────────

describe("deepl provider", function()
  it("has correct name", function()
    assert.equals("deepl", deepl.name)
  end)

  it("rejects empty api_key", function()
    local ok, err = deepl.validate({ api_key = "" })
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("accepts valid api_key", function()
    assert.is_true(deepl.validate({ api_key = "key" }))
  end)

  it("estimates cost based on character count", function()
    local payload = make_payload(string.rep("a", 1000), "deepl", { price_per_million_chars = 25 })
    local cost = deepl.estimate_cost(payload)
    assert.are.near(0.025, cost, 0.001)
  end)

  it("translates with mock http", function()
    local captured_opts
    local mock_http = function(_, _, opts)
      captured_opts = opts
      return {
        code = 0,
        stdout = vim.json.encode({
          translations = { { text = "hola" } },
        }),
      }
    end
    local payload = make_payload("hello", "deepl", { api_key = "dk", base_url = "https://api.deepl.test" })
    local result = deepl.translate(mock_http, payload)
    assert.equals("hola", result)
    local found_auth = false
    for _, header in ipairs(captured_opts.headers or {}) do
      if header == "Authorization: DeepL-Auth-Key dk" then
        found_auth = true
        break
      end
    end
    assert.is_true(found_auth)
    assert.falsy(captured_opts.data:find("auth_key=", 1, true))
    assert.truthy(captured_opts.data:find("text="))
    assert.truthy(captured_opts.data:find("target_lang="))
    assert.truthy(captured_opts.data:find("source_lang="))
  end)

  it("surfaces HTTP API failures with response details", function()
    local mock_http = function()
      return {
        code = 0,
        http_status = 403,
        stdout = [[{"message":"legacy auth rejected"}]],
      }
    end
    local payload = make_payload("hi", "deepl", { api_key = "k", base_url = "https://x.com" })
    local ok, err = pcall(deepl.translate, mock_http, payload)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("deepl translate failed %(HTTP 403%)", 1, false))
    assert.is_truthy(tostring(err):find("legacy auth rejected", 1, true))
  end)

  it("errors on unexpected response", function()
    local mock_http = function()
      return { code = 0, stdout = "{}" }
    end
    local payload = make_payload("hi", "deepl", { api_key = "k", base_url = "https://x.com" })
    assert.has_error(function()
      deepl.translate(mock_http, payload)
    end)
  end)
end)

-- ── openai ──────────────────────────────────────────────────────────────

describe("openai provider", function()
  it("has correct name", function()
    assert.equals("openai", openai.name)
  end)

  it("rejects empty api_key", function()
    local ok, err = openai.validate({ api_key = "" })
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("accepts valid api_key", function()
    assert.is_true(openai.validate({ api_key = "sk-test" }))
  end)

  it("estimates cost with token approximation", function()
    local payload = make_payload(string.rep("a", 400), "openai", {
      input_per_million = 0.15,
      output_per_million = 0.60,
    })
    local cost = openai.estimate_cost(payload)
    assert.is_number(cost)
    -- 400 chars / 4 = 100 tokens in+out
    -- (100/1e6)*0.15 + (100/1e6)*0.60 = 0.000075
    assert.truthy(cost > 0)
    assert.truthy(cost < 0.001)
  end)

  it("translates with mock http", function()
    local captured_opts
    local mock_http = function(_, _, opts)
      captured_opts = opts
      return {
        code = 0,
        stdout = vim.json.encode({
          choices = { { message = { content = "bonjour" } } },
        }),
      }
    end
    local payload = make_payload("hello", "openai", {
      api_key = "sk-x",
      model = "gpt-4o-mini",
      base_url = "https://api.openai.test",
    })
    local result = openai.translate(mock_http, payload)
    assert.equals("bonjour", result)
    -- Authorization header should be present.
    local found_auth = false
    for _, h in ipairs(captured_opts.headers) do
      if h:find("Authorization: Bearer sk%-x") then
        found_auth = true
      end
    end
    assert.is_true(found_auth)
  end)

  it("errors on unexpected response", function()
    local mock_http = function()
      return { code = 0, stdout = "{}" }
    end
    local payload = make_payload("hi", "openai", { api_key = "k", model = "m", base_url = "https://x.com" })
    assert.has_error(function()
      openai.translate(mock_http, payload)
    end)
  end)
end)

-- ── gemini ──────────────────────────────────────────────────────────────

describe("gemini provider", function()
  it("has correct name", function()
    assert.equals("gemini", gemini.name)
  end)

  it("rejects empty api_key", function()
    local ok, err = gemini.validate({ api_key = "" })
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("accepts valid api_key", function()
    assert.is_true(gemini.validate({ api_key = "AIza-test" }))
  end)

  it("estimates cost with token approximation", function()
    local payload = make_payload(string.rep("a", 400), "gemini", {
      input_per_million = 0.30,
      output_per_million = 2.50,
    })
    local cost = gemini.estimate_cost(payload)
    assert.is_number(cost)
    assert.truthy(cost > 0)
    assert.truthy(cost < 0.01)
  end)

  it("translates with mock http", function()
    local captured_url
    local mock_http = function(_, url)
      captured_url = url
      return {
        code = 0,
        stdout = vim.json.encode({
          candidates = { { content = { parts = { { text = "konnichiwa" } } } } },
        }),
      }
    end
    local payload = make_payload("hello", "gemini", {
      api_key = "AIza",
      model = "gemini-2.5-flash",
      base_url = "https://gen.test/v1beta/models",
    })
    local result = gemini.translate(mock_http, payload)
    assert.equals("konnichiwa", result)
    assert.truthy(captured_url:find("gemini%-2%.5%-flash:generateContent"))
  end)

  it("errors on unexpected response", function()
    local mock_http = function()
      return { code = 0, stdout = "{}" }
    end
    local payload = make_payload("hi", "gemini", { api_key = "k", model = "m", base_url = "https://x.com" })
    assert.has_error(function()
      gemini.translate(mock_http, payload)
    end)
  end)
end)

-- ── openrouter ──────────────────────────────────────────────────────────

describe("openrouter provider", function()
  it("has correct name", function()
    assert.equals("openrouter", openrouter.name)
  end)

  it("rejects empty api_key", function()
    local ok, err = openrouter.validate({ api_key = "" })
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("accepts valid api_key", function()
    assert.is_true(openrouter.validate({ api_key = "or-test" }))
  end)

  it("estimates cost with token approximation", function()
    local payload = make_payload(string.rep("a", 400), "openrouter", {
      input_per_million = 0.15,
      output_per_million = 0.60,
    })
    local cost = openrouter.estimate_cost(payload)
    assert.is_number(cost)
    assert.truthy(cost > 0)
  end)

  it("translates with mock http", function()
    local captured_headers
    local mock_http = function(_, _, opts)
      captured_headers = opts.headers
      return {
        code = 0,
        stdout = vim.json.encode({
          choices = { { message = { content = "hallo" } } },
        }),
      }
    end
    local payload = make_payload("hello", "openrouter", {
      api_key = "or-k",
      model = "openrouter/auto",
      base_url = "https://or.test",
      referer = "https://github.com/test",
    })
    local result = openrouter.translate(mock_http, payload)
    assert.equals("hallo", result)
    -- Should include HTTP-Referer header.
    local found_referer = false
    for _, h in ipairs(captured_headers) do
      if h:find("HTTP%-Referer:") then
        found_referer = true
      end
    end
    assert.is_true(found_referer)
  end)

  it("omits referer header when not configured", function()
    local captured_headers
    local mock_http = function(_, _, opts)
      captured_headers = opts.headers
      return {
        code = 0,
        stdout = vim.json.encode({
          choices = { { message = { content = "ok" } } },
        }),
      }
    end
    local payload = make_payload("hello", "openrouter", {
      api_key = "or-k",
      model = "openrouter/auto",
      base_url = "https://or.test",
      referer = nil,
    })
    -- Explicitly clear referer.
    payload.config.providers.openrouter.referer = nil
    openrouter.translate(mock_http, payload)
    for _, h in ipairs(captured_headers) do
      assert.is_falsy(h:find("HTTP%-Referer:"))
    end
  end)

  it("errors on unexpected response", function()
    local mock_http = function()
      return { code = 0, stdout = "{}" }
    end
    local payload = make_payload("hi", "openrouter", {
      api_key = "k",
      model = "m",
      base_url = "https://x.com",
    })
    assert.has_error(function()
      openrouter.translate(mock_http, payload)
    end)
  end)
end)
