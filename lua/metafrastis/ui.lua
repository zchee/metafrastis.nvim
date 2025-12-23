local util = require("metafrastis.util")

local M = {}

local snacks_cache = nil
local autoclose_group = vim.api.nvim_create_augroup("MetafrastisSnacksWin", { clear = false })
local default_win_opts = {}

local function get_snacks()
  if snacks_cache ~= nil then
    return snacks_cache
  end
  local ok, mod = pcall(require, "snacks")
  snacks_cache = ok and mod or false
  return snacks_cache
end

local function close_snacks_win(win)
  if not win then
    return
  end
  local closed = false
  if type(win.close) == "function" then
    local ok = pcall(win.close, win)
    closed = ok or closed
  end
  local winid
  if type(win.win) == "number" then
    winid = win.win
  elseif type(win.winid) == "number" then
    winid = win.winid
  elseif type(win.id) == "number" then
    winid = win.id
  end
  if winid and vim.api.nvim_win_is_valid(winid) then
    local ok = pcall(vim.api.nvim_win_close, winid, true)
    closed = ok or closed
  end
  return closed
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
  local base = (opts and opts.title)
  local parts = { base }
  if opts and opts.target_lang then
    table.insert(parts, opts.target_lang)
  end
  if meta and meta.provider then
    table.insert(parts, meta.provider)
  end
  if meta and meta.icon then
    table.insert(parts, meta.icon)
  end
  if meta and meta.cached then
    table.insert(parts, "cache")
  end
  return table.concat(parts, " · ")
end

function M.set_defaults(win_opts)
  default_win_opts = win_opts or {}
end

local function apply_padding(lines, padding)
  if not padding then
    return lines
  end
  local top = padding.top or 0
  local bottom = padding.bottom or 0
  local left = padding.left or 0
  local right = padding.right or 0
  local pad_left = left > 0 and string.rep(" ", left) or ""
  local pad_right = right > 0 and string.rep(" ", right) or ""

  local padded = {}
  for _ = 1, top do
    table.insert(padded, pad_left .. pad_right)
  end
  for _, line in ipairs(lines) do
    table.insert(padded, pad_left .. line .. pad_right)
  end
  for _ = 1, bottom do
    table.insert(padded, pad_left .. pad_right)
  end
  return padded
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
  local merged_win = vim.tbl_deep_extend("force", {}, default_win_opts or {}, opts and opts.win or {})
  local padding = merged_win.padding or (opts and opts.padding) or nil
  if not padding then
    local ok, core = pcall(require, "metafrastis")
    if ok and core.config and core.config.ui and core.config.ui.win then
      padding = core.config.ui.win.padding
    end
  end

  lines = apply_padding(lines, padding)

  local title = make_title(meta, opts)

  if snacks and snacks.win then
    local win_opts = vim.tbl_deep_extend("force", {
      text = lines,
      title = title,
      minimal = true,
      enter = false,
      keys = { q = "close" },
      border = "rounded",
      title_pos = "center",
      footer = "q: close · move cursor to dismiss",
      footer_pos = "left",
      wo = { wrap = true },
      relative = "cursor",
    }, merged_win)

    if win_opts.relative == "cursor" then
      win_opts.row = win_opts.row or 1
      win_opts.col = win_opts.col or 0
    end

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
    local already_closed = false
    if win then
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = autoclose_group,
        once = true,
        desc = "metafrastis: close Snacks window after cursor move",
        callback = function()
          if already_closed then
            return
          end
          already_closed = true
          close_snacks_win(win)
        end,
      })
    end
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
  default_win_opts = {}
end

return M
