local util = require("metafrastis.util")

local M = {}

local snacks_cache = nil

local function get_snacks()
  if snacks_cache ~= nil then
    return snacks_cache
  end
  local ok, mod = pcall(require, "snacks")
  snacks_cache = ok and mod or false
  return snacks_cache
end

function M.has_snacks()
  return get_snacks() ~= false
end

local function to_log_level(level)
  if type(level) == "number" then
    return level
  end
  if not level then
    return vim.log.levels.INFO
  end
  local upper = string.upper(level)
  return vim.log.levels[upper] or vim.log.levels.INFO
end

---@param msg string|string[]
---@param level string|number|nil
---@param opts table|nil
function M.notify(msg, level, opts)
  local snacks = get_snacks()
  if snacks and snacks.notify then
    local lower = type(level) == "string" and string.lower(level) or "info"
    local fn = snacks.notify[lower] or snacks.notify.notify or snacks.notify.info
    fn(msg, opts)
    return
  end
  vim.notify(msg, to_log_level(level), opts)
end

---@param msg string
---@param opts table|nil
---@return fun(done_msg?:string, level?:string|number)
function M.progress(msg, opts)
  M.notify(msg, "info", opts)
  local finished = false
  return function(done_msg, level)
    if finished then
      return
    end
    finished = true
    if done_msg then
      M.notify(done_msg, level or "info", opts)
    end
  end
end

local function make_title(meta, opts)
  local base = (opts and opts.title) or "Metafrastis"
  local parts = { base }
  if opts and opts.target_lang then
    table.insert(parts, opts.target_lang)
  end
  if meta and meta.provider then
    table.insert(parts, meta.provider)
  end
  if meta and meta.cached then
    table.insert(parts, "cache")
  end
  return table.concat(parts, " · ")
end

---@param text string|string[]
---@param meta table|nil
---@param opts table|nil
function M.show_window(text, meta, opts)
  local snacks = get_snacks()
  local lines = type(text) == "table" and text or util.split_lines(text or "")
  if #lines == 0 then
    lines = { "" }
  end

  local title = make_title(meta, opts)

  if snacks and snacks.win then
    local win_opts = vim.tbl_deep_extend("force", {
      text = lines,
      title = title,
      minimal = true,
      enter = false,
      keys = { q = "close" },
    }, opts and opts.win or {})

    if not win_opts.width then
      local max_len = 0
      for _, line in ipairs(lines) do
        max_len = math.max(max_len, #line)
      end
      win_opts.width = math.min(120, math.max(20, max_len + 4))
    end
    if not win_opts.height then
      win_opts.height = math.min(#lines + 2, 20)
    end

    local win = snacks.win(win_opts)
    if win and win.show then
      win:show()
    end
    return win
  end

  vim.api.nvim_echo({ { table.concat(lines, "\n"), "Normal" } }, false, {})
end

---@param default string|nil
---@param on_confirm fun(value?:string)
function M.prompt_target(default, on_confirm)
  local cb = on_confirm or function() end
  local snacks = get_snacks()
  if snacks and snacks.input then
    snacks.input({ prompt = "Target language", default = default }, cb)
    return
  end
  vim.ui.input({ prompt = "Target language: ", default = default }, cb)
end

-- Test helper
function M._reset_for_tests()
  snacks_cache = nil
end

return M
