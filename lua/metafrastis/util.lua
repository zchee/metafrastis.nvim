local M = {}

---@param s string
---@return string
function M.urlencode(s)
  if not s then
    return ""
  end
  s = s:gsub("\n", "\r\n")
  s = s:gsub("([^%w%-%.%_%~ ])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return s:gsub(" ", "+")
end

---@param lines string
---@return string[]
function M.split_lines(lines)
  local result = {}
  local text = lines or ""
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(result, line)
  end
  return result
end

return M
