local M = {}

M.name = "google"

function M.validate(cfg)
  if not cfg.api_key or cfg.api_key == "" then
    return false, "google provider requires api_key"
  end
  return true
end

---@param _http fun(method: string, url: string, opts: table): table
---@param payload table
---@return string
function M.translate(_http, payload)
  local cfg = payload.config.providers.google
  local url = cfg.base_url .. "?key=" .. cfg.api_key
  local body = {
    q = payload.text,
    target = payload.target_lang,
    format = "text",
  }
  if payload.source_lang and payload.source_lang ~= "" then
    body.source = payload.source_lang
  end
  local res = _http("POST", url, {
    headers = { "Content-Type: application/json" },
    data = vim.json.encode(body),
  })
  if res.code ~= 0 then
    error("google translate failed: " .. (res.stderr or res.stdout or "unknown error"))
  end
  local parsed = vim.json.decode(res.stdout)
  local translations = parsed and parsed.data and parsed.data.translations
  if not translations or not translations[1] or not translations[1].translatedText then
    error("google translate returned unexpected payload")
  end
  return translations[1].translatedText
end

function M.estimate_cost(payload)
  local cfg = payload.config.providers.google
  local chars = #payload.text
  local price = cfg.price_per_million_chars or 20
  return (chars / 1e6) * price
end

return M
