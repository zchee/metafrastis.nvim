local M = {}

M.name = "openrouter"

function M.validate(cfg)
  if not cfg.api_key or cfg.api_key == "" then
    return false, "openrouter provider requires api_key"
  end
  return true
end

---@param _http fun(method: string, url: string, opts: table): table
---@param payload table
---@return string
function M.translate(_http, payload)
  local cfg = payload.config.providers.openrouter
  local user_prompt = string.format(
    "Translate from %s to %s. Return only the translated text.\n\n%s",
    payload.source_lang or "auto",
    payload.target_lang or "en",
    payload.text
  )
  local body = {
    model = cfg.model,
    messages = {
      { role = "system", content = "You are a careful translator. Preserve markup and code fences." },
      { role = "user", content = user_prompt },
    },
    temperature = 0,
  }
  local headers = {
    "Content-Type: application/json",
    "Authorization: Bearer " .. cfg.api_key,
  }
  if cfg.referer then
    table.insert(headers, "HTTP-Referer: " .. cfg.referer)
  end
  local res = _http("POST", cfg.base_url, {
    headers = headers,
    data = vim.json.encode(body),
  })
  if res.code ~= 0 then
    error("openrouter translate failed: " .. (res.stderr or "curl error code " .. res.code))
  end
  if res.http_status and res.http_status >= 400 then
    error("openrouter translate failed (HTTP " .. res.http_status .. "): " .. (res.stdout or ""))
  end
  local parsed = vim.json.decode(res.stdout)
  local choice = parsed and parsed.choices and parsed.choices[1]
  if not choice or not choice.message or not choice.message.content then
    error("openrouter translate returned unexpected payload")
  end
  return choice.message.content
end

function M.estimate_cost(payload)
  local cfg = payload.config.providers.openrouter
  local chars = #payload.text
  local tokens = chars / 4
  local cost_in = (tokens / 1e6) * (cfg.input_per_million or 0.15)
  local cost_out = (tokens / 1e6) * (cfg.output_per_million or 0.60)
  return cost_in + cost_out
end

return M
