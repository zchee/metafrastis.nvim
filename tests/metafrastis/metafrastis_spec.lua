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

  it("uses provider-specific config during validation", function()
    registry.register("needs_secret", {
      validate = function(cfg)
        if cfg.secret ~= "ok" then
          return false, "secret missing"
        end
        return true
      end,
      translate = function(_, payload)
        local cfg = payload.config.providers.needs_secret
        return string.format("%s-%s", payload.text, cfg.secret)
      end,
    })
    metafrastis.config.provider = "needs_secret"
    metafrastis.config.providers.needs_secret = { secret = "ok" }

    local out = metafrastis.translate("ping", { target_lang = "en" })
    assert.equals("ping-ok", out)
  end)

  it("falls back to echo when provider lacks credentials at call time", function()
    metafrastis.setup({
      provider = "deepl",
      providers = {
        deepl = { api_key = "" },
      },
    })

    local out, meta = metafrastis.translate("Hello", { target_lang = "ja" })
    assert.equals("Hello [echo]->ja", out)
    assert.is_table(meta)
    assert.equals("echo", meta.provider)
    assert.is_false(meta.cached)
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

  it("uses configured target_lang without prompting when args are omitted", function()
    metafrastis._reset_for_tests()
    metafrastis.setup({ provider = "echo", target_lang = "fr", source_lang = "en" })
    vim.cmd("runtime plugin/metafrastis.lua")

    package.loaded["snacks"] = false
    local ui = require("metafrastis.ui")
    ui._reset_for_tests()
    local original_prompt = ui.prompt_target
    local original_progress = ui.progress
    local original_notify = ui.notify
    local prompted = false
    local done = false
    ui.prompt_target = function()
      prompted = true
    end
    ui.progress = function()
      return function()
        done = true
      end
    end
    ui.notify = function() end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello world" })

    vim.cmd("1,1MetafrastisTranslateUI!")

    vim.wait(1000, function()
      return done
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("Hello world [echo]->fr", lines[1])
    assert.is_false(prompted)

    ui.prompt_target = original_prompt
    ui.progress = original_progress
    ui.notify = original_notify
  end)

  it("prefers explicit args over configured languages", function()
    metafrastis._reset_for_tests()
    metafrastis.setup({ provider = "echo", target_lang = "fr", source_lang = "en" })
    vim.cmd("runtime plugin/metafrastis.lua")

    package.loaded["snacks"] = false
    local ui = require("metafrastis.ui")
    ui._reset_for_tests()
    local original_progress = ui.progress
    local original_notify = ui.notify
    local done = false
    ui.progress = function()
      return function()
        done = true
      end
    end
    ui.notify = function() end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello world" })

    vim.cmd("1,1MetafrastisTranslateUI! es")

    vim.wait(1000, function()
      return done
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("Hello world [echo]->es", lines[1])

    ui.progress = original_progress
    ui.notify = original_notify
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

describe("Snacks.win result window", function()
  after_each(function()
    package.loaded["snacks"] = nil
    require("metafrastis.ui")._reset_for_tests()
  end)

  it("uses snacks.win when show_window is enabled", function()
    metafrastis._reset_for_tests()
    metafrastis.setup({ provider = "echo" })

    local win_opts
    package.loaded["snacks"] = {
      notify = {
        info = function() end,
        warn = function() end,
        notify = function() end,
      },
      win = function(opts)
        win_opts = opts
        return { show = function() end }
      end,
    }
    require("metafrastis.ui")._reset_for_tests()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello world" })

    local echoed = false
    local original_echo = vim.api.nvim_echo
    vim.api.nvim_echo = function()
      echoed = true
    end

    local done = false
    metafrastis.translate_range_async(bufnr, 0, 1, {
      target_lang = "es",
      show_window = true,
      replace = false,
    }, {
      on_success = function()
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

    vim.api.nvim_echo = original_echo

    assert.is_true(done)
    assert.truthy(win_opts)
    assert.equals("Hello world [echo]->es", win_opts.text[1])
    assert.equals("cursor", win_opts.relative)
    assert.equals(1, win_opts.row)
    assert.equals(0, win_opts.col)
    assert.equals("rounded", win_opts.border)
    assert.equals("center", win_opts.title_pos)
    assert.equals("q: close · move cursor to dismiss", win_opts.footer)
    assert.equals("left", win_opts.footer_pos)
    assert.is_true(win_opts.wo.wrap)
    assert.is_false(echoed)
  end)

  it("closes snacks.win on CursorMoved", function()
    metafrastis._reset_for_tests()
    metafrastis.setup({ provider = "echo" })

    local closed = 0
    local win_opts
    package.loaded["snacks"] = {
      notify = {
        info = function() end,
        warn = function() end,
        notify = function() end,
      },
      win = function(opts)
        win_opts = opts
        return {
          win = 1000,
          show = function() end,
          close = function()
            closed = closed + 1
          end,
        }
      end,
    }
    require("metafrastis.ui")._reset_for_tests()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello world" })

    local done = false
    metafrastis.translate_range_async(bufnr, 0, 1, {
      target_lang = "es",
      show_window = true,
      replace = false,
    }, {
      on_success = function()
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

    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })

    assert.is_true(done)
    assert.equals(1, closed)
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
    package.loaded["snacks"] = false
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

  it("renders translation in snacks.win when available", function()
    local win_opts
    package.loaded["snacks"] = {
      notify = {
        info = function() end,
        warn = function() end,
        notify = function() end,
      },
      win = function(opts)
        win_opts = opts
        return { show = function() end }
      end,
    }
    local ui = require("metafrastis.ui")
    ui._reset_for_tests()
    ui.show_window("ciao", { provider = "echo", cached = true }, { target_lang = "es" })
    assert.truthy(win_opts)
    assert.equals("Metafrastis · es · echo · cache", win_opts.title)
    assert.equals("ciao", win_opts.text[1])
    assert.equals("cursor", win_opts.relative)
    assert.equals(1, win_opts.row)
    assert.equals(0, win_opts.col)
    assert.equals("rounded", win_opts.border)
    assert.equals("center", win_opts.title_pos)
    assert.equals("q: close · move cursor to dismiss", win_opts.footer)
    assert.equals("left", win_opts.footer_pos)
    assert.is_true(win_opts.wo.wrap)
  end)

  it("falls back to vim.echo when snacks missing", function()
    package.loaded["snacks"] = nil
    local ui = require("metafrastis.ui")
    ui._reset_for_tests()
    local original_echo = vim.api.nvim_echo
    local echoed
    vim.api.nvim_echo = function(chunks)
      echoed = chunks
    end
    ui.show_window("hello", nil, { target_lang = "fr" })
    vim.api.nvim_echo = original_echo
    assert.truthy(echoed)
    assert.equals("hello", echoed[1][1])
  end)

  it("allows overriding cursor positioning defaults", function()
    local win_opts
    package.loaded["snacks"] = {
      notify = {
        info = function() end,
        warn = function() end,
        notify = function() end,
      },
      win = function(opts)
        win_opts = opts
        return { show = function() end }
      end,
    }
    local ui = require("metafrastis.ui")
    ui._reset_for_tests()
    ui.show_window(
      "hola",
      nil,
      { win = { relative = "editor", row = 5, col = 10, border = "double", wo = { wrap = false } } }
    )
    assert.truthy(win_opts)
    assert.equals("editor", win_opts.relative)
    assert.equals(5, win_opts.row)
    assert.equals(10, win_opts.col)
    assert.equals("double", win_opts.border)
    assert.is_false(win_opts.wo.wrap)
  end)
end)
