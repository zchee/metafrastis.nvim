---@class MetafrastisHttp
---@field timeout integer
---@field backend string

local M = {}

local util = require("metafrastis.util")
local uv = vim.loop

local function build_request_url(url, query)
  if not query then
    return url
  end
  local qs = {}
  for k, v in pairs(query) do
    table.insert(qs, string.format("%s=%s", util.urlencode(k), util.urlencode(v)))
  end
  if #qs == 0 then
    return url
  end
  return url .. "?" .. table.concat(qs, "&")
end

---@param method string
---@param url string
---@param opts table|nil
---@return string[]
local function build_args(method, url, opts)
  local args = { "-sSf", "-X", method }
  local request_url = build_request_url(url, opts and opts.query or nil)
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
  return args
end

---@param args string[]
---@param timeout integer
---@return table|nil
local function run_with_job(args, timeout)
  local ok, Job = pcall(require, "plenary.job")
  if not ok then
    return nil
  end
  local job = Job:new({
    command = "curl",
    args = args,
  })
  local stdout, code = job:sync(timeout or 20000)
  local stderr = job:stderr_result()
  return {
    code = code or 0,
    stdout = stdout and table.concat(stdout, "\n") or "",
    stderr = stderr and table.concat(stderr, "\n") or "",
  }
end

---@param args string[]
---@param timeout integer
---@return table
local function run_with_system(args, timeout)
  if vim.system then
    local handle = vim.system(vim.list_extend({ "curl" }, args), { text = true, timeout = timeout })
    local result = handle:wait()
    return {
      code = result.code,
      stdout = result.stdout or "",
      stderr = result.stderr or "",
    }
  end

  local joined = "curl " .. table.concat(args, " ")
  local output = vim.fn.systemlist(joined)
  local code = vim.v.shell_error
  return {
    code = code,
    stdout = table.concat(output, "\n"),
    stderr = "",
  }
end

---@param cfg MetafrastisHttp
---@return fun(method: string, url: string, opts: table): table
function M.build(cfg)
  return function(method, url, opts)
    local args = build_args(method, url, opts)
    if cfg.backend == "plenary" then
      local res = run_with_job(args, cfg.timeout or 20000)
      if res then
        return res
      end
      vim.notify("metafrastis: plenary.job unavailable, falling back to curl", vim.log.levels.WARN)
    end
    return run_with_system(args, cfg.timeout or 20000)
  end
end

---@param cfg MetafrastisHttp
---@return fun(method: string, url: string, opts: table): table
function M.build_async(cfg)
  local ok_job, Job = pcall(require, "plenary.job")
  local ok_async, async = pcall(require, "plenary.async")
  if not (ok_job and ok_async) then
    local sync = M.build(cfg)
    return function(method, url, opts)
      return sync(method, url, opts)
    end
  end

  local wrap = async.wrap

  return wrap(function(method, url, opts, cb)
    local args = build_args(method, url, opts)
    local timer
    local job
    job = Job:new({
      command = "curl",
      args = args,
      enable_recording = true,
      on_exit = function(j, code, signal)
        if timer then
          timer:stop()
          timer:close()
        end
        cb({
          code = code or signal or 0,
          stdout = j:result() and table.concat(j:result(), "\n") or "",
          stderr = j:stderr_result() and table.concat(j:stderr_result(), "\n") or "",
        })
      end,
    })
    local timeout = cfg.timeout or 20000
    if timeout and timeout > 0 then
      timer = uv.new_timer()
      timer:start(timeout, 0, function()
        if job and not job.is_shutdown then
          job:shutdown(1, 9)
        end
        if timer then
          timer:stop()
          timer:close()
        end
      end)
    end
    job:start()
  end, 4)
end

return M
