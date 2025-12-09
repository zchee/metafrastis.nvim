local metafrastis = require("metafrastis")
local ui = require("metafrastis.ui")

local function parse_lang_args(args)
  local source
  local target
  if #args == 1 then
    target = args[1]
  elseif #args >= 2 then
    source = args[1]
    target = args[2]
  end
  return source, target
end

vim.api.nvim_create_user_command("MetafrastisTranslate", function(opts)
  metafrastis.command(opts)
end, {
  range = true,
  nargs = "*",
  bang = true,
  desc = "Translate selection or buffer text using configured provider",
  complete = function()
    return { "en", "es", "fr", "de", "ja", "ko", "zh" }
  end,
})

vim.api.nvim_create_user_command("MetafrastisCacheClear", function()
  metafrastis.clear_cache()
  vim.notify("metafrastis: cache cleared", vim.log.levels.INFO)
end, { desc = "Clear translation cache" })

vim.api.nvim_create_user_command("MetafrastisTranslateUI", function(opts)
  local args = opts.fargs or {}
  local source, target = parse_lang_args(args)
  local replace = opts.bang or metafrastis.config.replace
  local start_line = (opts.line1 or 1) - 1
  local end_line = opts.line2 or vim.api.nvim_buf_line_count(0)

  local function run_with_target(target_lang)
    if not target_lang or target_lang == "" then
      ui.notify("metafrastis: target language required", "warn", { title = "Metafrastis" })
      return
    end
    local done = ui.progress("Translating...", { title = "Metafrastis" })
    metafrastis.translate_range_async(0, start_line, end_line, {
      source_lang = source,
      target_lang = target_lang,
      replace = replace,
      show_window = not replace,
    }, {
      on_success = function(_, meta)
        local provider = meta and meta.provider or metafrastis.config.provider
        local suffix = meta and meta.cached and " (cache)" or ""
        done(string.format("Translated via %s%s", provider, suffix), "info")
      end,
      on_error = function(err)
        done("Translation failed: " .. tostring(err), "error")
      end,
    })
  end

  if target and target ~= "" then
    run_with_target(target)
    return
  end

  ui.prompt_target(metafrastis.config.target_lang, function(value)
    if value and value ~= "" then
      run_with_target(value)
    else
      ui.notify("metafrastis: target language required", "warn", { title = "Metafrastis" })
    end
  end)
end, {
  range = true,
  nargs = "*",
  bang = true,
  desc = "Translate selection or buffer using Snacks UI and async backend",
  complete = function()
    return { "en", "es", "fr", "de", "ja", "ko", "zh" }
  end,
})
