local metafrastis = require("metafrastis")
local registry = require("metafrastis.providers")

describe("setup", function()
  before_each(function()
    metafrastis._reset_for_tests()
  end)

  it("falls back to echo when provider credentials are missing", function()
    metafrastis.setup({ provider = "openai" })
    assert.equals("echo", metafrastis.config.provider)
  end)

  it("keeps chosen provider when valid", function()
    metafrastis.setup({ provider = "echo" })
    assert.equals("echo", metafrastis.config.provider)
  end)
end)

describe("translation core", function()
  before_each(function()
    metafrastis._reset_for_tests()
  end)

  it("translates via echo provider", function()
    metafrastis.setup({ provider = "echo" })
    local out = metafrastis.translate("Hello", { target_lang = "es" })
    assert.equals("Hello [echo]->es", out)
  end)

  it("caches repeated calls", function()
    local calls = 0
    registry.register("count", {
      translate = function(_, payload)
        calls = calls + 1
        return payload.text .. " #" .. calls
      end,
      estimate_cost = function()
        return 0
      end,
    })
    metafrastis.config.provider = "count"
    local first = metafrastis.translate("hi", { target_lang = "fr" })
    local second = metafrastis.translate("hi", { target_lang = "fr" })
    assert.equals("hi #1", first)
    assert.equals("hi #1", second)
    assert.equals(1, calls)
  end)

  it("rejects calls that exceed cost guard", function()
    registry.register("expensive", {
      estimate_cost = function()
        return 2
      end,
      translate = function()
        return "should-not-run"
      end,
    })
    metafrastis.config.provider = "expensive"
    metafrastis.config.cache.max_estimated_cost = 1
    assert.has_error(function()
      metafrastis.translate("hi", { target_lang = "fr" })
    end)
  end)
end)

describe("commands", function()
  before_each(function()
    metafrastis._reset_for_tests()
    metafrastis.setup({ provider = "echo" })
    vim.cmd("runtime plugin/metafrastis.lua")
  end)

  it("replaces selected lines when bang is used", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello world" })
    vim.cmd("1,1MetafrastisTranslate! en es")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("Hello world [echo]->es", lines[0 + 1])
  end)
end)
