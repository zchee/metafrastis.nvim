---@class MetafrastisHttp
---@field timeout integer
---@field backend string

local M = {}

local util = require("metafrastis.util")

---@param args string[]
---@param timeout integer
---@return table
local function run(args, timeout)
  if vim.system then
    local handle = vim.system(args, { text = true, timeout = timeout })
    local result = handle:wait()
    return {
      code = result.code,
      stdout = result.stdout or "",
      stderr = result.stderr or "",
    }
  end

  local joined = table.concat(args, " ")
  local output = vim.fn.systemlist(joined)
  local code = vim.v.shell_error
  return {
    code = code,
    stdout = table.concat(output, "\n"),
    stderr = "",
  }
end

local function build_plenary_runner(cfg)
  local ok, pcurl = pcall(require, "plenary.curl")
  if not ok or not pcurl then
    return nil
  end

  return function(method, url, opts)
    local request_url = url
    if opts and opts.query then
      local qs = {}
      for k, v in pairs(opts.query) do
        table.insert(qs, string.format("%s=%s", util.urlencode(k), util.urlencode(v)))
      end
      if #qs > 0 then
        request_url = request_url .. "?" .. table.concat(qs, "&")
      end
    end
    local headers_tbl = {}
    if opts and opts.headers then
      for _, h in ipairs(opts.headers) do
        local k, v = h:match("^(.-):%s*(.*)$")
        if k and v then
          headers_tbl[k] = v
        end
      end
    end
    local res = pcurl.request({
      method = method,
      url = request_url,
      headers = headers_tbl,
      body = opts and opts.data or nil,
      timeout = (cfg.timeout or 20000) / 1000,
    })
    return {
      code = res and res.status or 1,
      stdout = res and res.body or "",
      stderr = res and res.err or "",
    }
  end
end

---@param cfg MetafrastisHttp
---@return fun(method: string, url: string, opts: table): table
function M.build(cfg)
  if cfg.backend == "plenary" then
    local runner = build_plenary_runner(cfg)
    if runner then
      return runner
    end
    vim.notify("metafrastis: plenary.curl not available, falling back to curl", vim.log.levels.WARN)
  end

  return function(method, url, opts)
    local args = { "curl", "-sSf", "-X", method }
    local request_url = url
    if opts and opts.query then
      local qs = {}
      for k, v in pairs(opts.query) do
        table.insert(qs, string.format("%s=%s", util.urlencode(k), util.urlencode(v)))
      end
      if #qs > 0 then
        request_url = request_url .. "?" .. table.concat(qs, "&")
      end
    end
    if opts and opts.headers then
      for _, h in ipairs(opts.headers) do
        table.insert(args, "-H")
        table.insert(args, h)
      end
    end
    if opts and opts.data then
      table.insert(args, "-d")
      table.insert(args, opts.data)
    end
    table.insert(args, request_url)
    return run(args, cfg.timeout or 20000)
  end
end

return M
