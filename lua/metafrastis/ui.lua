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

return M
