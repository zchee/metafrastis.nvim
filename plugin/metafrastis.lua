local metafrastis = require("metafrastis")

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
