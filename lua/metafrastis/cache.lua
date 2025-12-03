local uv = vim.loop

---@class MetafrastisCache
---@field dir string
---@field ttl integer

local M = {}

---@param dir string
---@return boolean
local function ensure_dir(dir)
  local ok = vim.fn.isdirectory(dir) == 1
  if not ok then
    vim.fn.mkdir(dir, "p")
    ok = vim.fn.isdirectory(dir) == 1
  end
  return ok
end

---@param provider string
---@param source string|nil
---@param target string|nil
---@param text string
---@return string
function M.make_key(provider, source, target, text)
  local raw = table.concat({ provider or "?", source or "", target or "", text }, "\n")
  return vim.fn.sha256(raw)
end

---@param cache MetafrastisCache
---@param key string
---@return string|nil
function M.get(cache, key)
  if not cache or not cache.enabled then
    return nil
  end
  if not ensure_dir(cache.dir) then
    return nil
  end
  local path = cache.dir .. "/" .. key .. ".json"
  local stat = uv.fs_stat(path)
  if not stat then
    return nil
  end
  local now = os.time()
  if cache.ttl > 0 and now - stat.mtime.sec > cache.ttl then
    uv.fs_unlink(path)
    return nil
  end
  local ok, data = pcall(vim.fn.readfile, path, "b")
  if not ok or not data or #data == 0 then
    return nil
  end
  local joined = table.concat(data, "\n")
  local decoded = vim.json.decode(joined)
  if not decoded or not decoded.value then
    return nil
  end
  return decoded.value
end

---@param cache MetafrastisCache
---@param key string
---@param value string
function M.put(cache, key, value)
  if not cache or not cache.enabled then
    return
  end
  if not ensure_dir(cache.dir) then
    return
  end
  local tmp = string.format("%s/%s.tmp", cache.dir, key)
  local path = string.format("%s/%s.json", cache.dir, key)
  local payload = vim.json.encode({ value = value, saved_at = os.time() })
  vim.fn.writefile({ payload }, tmp, "b")
  uv.fs_rename(tmp, path)
end

---@param cache MetafrastisCache
function M.clear(cache)
  if not cache or not cache.enabled then
    return
  end
  local dir = cache.dir
  local handle = uv.fs_scandir(dir)
  if not handle then
    return
  end
  while true do
    local name = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    uv.fs_unlink(dir .. "/" .. name)
  end
end

return M
