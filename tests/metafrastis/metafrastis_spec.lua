local metafrastis = require("metafrastis")
local registry = require("metafrastis.providers")

describe("setup", function()
  before_each(function()
    metafrastis._reset_for_tests()
  end)

  it("falls back to echo when provider credentials are missing", function()
    metafrastis.setup({
      provider = "openai",
      providers = {
        openai = { api_key = "" },
      },
    })
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

describe("async translation", function()
  before_each(function()
    metafrastis._reset_for_tests()
    metafrastis.setup({ provider = "echo" })
  end)

  it("translates via async path", function()
    local result
    local done = false
    metafrastis.translate_async("Hello", { target_lang = "fr" }, {
      on_success = function(out)
        result = out
        done = true
      end,
      on_error = function(err)
        done = true
        error(err)
      end,
    })
    vim.wait(1000, function()
      return done
    end)
    assert.equals("Hello [echo]->fr", result)
  end)

  it("caches in async path", function()
    local calls = 0
    registry.register("count_async", {
      translate = function(_, payload)
        calls = calls + 1
        return payload.text .. "#" .. calls
      end,
      estimate_cost = function()
        return 0
      end,
    })
    metafrastis.config.provider = "count_async"
    local results = {}
    local done = 0
    for i = 1, 2 do
      metafrastis.translate_async("ping", { target_lang = "en" }, {
        on_success = function(out)
          results[i] = out
          done = done + 1
        end,
      })
      vim.wait(1000, function()
        return done >= i
      end)
    end
    assert.equals("ping#1", results[1])
    assert.equals("ping#1", results[2])
    assert.equals(1, calls)
  end)
end)

describe("ui helper", function()
  local original_notify

  before_each(function()
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
    package.loaded["snacks"] = nil
    package.loaded["metafrastis.ui"] = nil
  end)

  it("falls back to vim.notify when snacks missing", function()
    local messages = {}
    vim.notify = function(msg, level)
      table.insert(messages, { msg = msg, level = level })
    end
    local ui = require("metafrastis.ui")
    ui.notify("hello", "info", { title = "t" })
    assert.equals("hello", messages[1].msg)
  end)

  it("uses snacks when available", function()
    local notified = {}
    package.loaded["snacks"] = {
      notify = {
        info = function(msg, opts)
          table.insert(notified, { msg = msg, opts = opts, level = "info" })
        end,
        warn = function(msg, opts)
          table.insert(notified, { msg = msg, opts = opts, level = "warn" })
        end,
        notify = function(msg, opts)
          table.insert(notified, { msg = msg, opts = opts, level = "notify" })
        end,
      },
    }
    local ui = require("metafrastis.ui")
    ui.notify("hi", "warn", { title = "x" })
    assert.equals("hi", notified[1].msg)
    assert.equals("warn", notified[1].level)
  end)

  it("prompts with snacks input when available", function()
    local received_default
    local confirmed
    package.loaded["snacks"] = {
      notify = {
        info = function() end,
      },
      input = function(opts, cb)
        received_default = opts.default
        cb("ja")
      end,
    }
    local ui = require("metafrastis.ui")
    ui.prompt_target("es", function(value)
      confirmed = value
    end)
    assert.equals("es", received_default)
    assert.equals("ja", confirmed)
  end)
end)
