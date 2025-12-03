local util = require("metafrastis.util")

local M = {}

M.name = "deepl"

function M.validate(cfg)
  if not cfg.api_key or cfg.api_key == "" then
    return false, "deepl provider requires api_key"
  end
  return true
end

---@param _http fun(method: string, url: string, opts: table): table
---@param payload table
---@return string
function M.translate(_http, payload)
  local cfg = payload.config.providers.deepl
  local params = {
    "auth_key=" .. util.urlencode(cfg.api_key),
    "text=" .. util.urlencode(payload.text),
    "target_lang=" .. util.urlencode((payload.target_lang or ""):upper()),
  }
  if payload.source_lang then
    table.insert(params, "source_lang=" .. util.urlencode(payload.source_lang:upper()))
  end
  local body = table.concat(params, "&")
  local res = _http("POST", cfg.base_url, {
    headers = { "Content-Type: application/x-www-form-urlencoded" },
    data = body,
  })
  if res.code ~= 0 then
    error("deepl translate failed: " .. (res.stderr or res.stdout or "unknown error"))
  end
  local parsed = vim.json.decode(res.stdout)
  if not parsed or not parsed.translations or not parsed.translations[1] then
    error("deepl translate returned unexpected payload")
  end
  return parsed.translations[1].text
end

function M.estimate_cost(payload)
  local cfg = payload.config.providers.deepl
  local chars = #payload.text
  local price = cfg.price_per_million_chars or 25
  return (chars / 1e6) * price
end

return M
