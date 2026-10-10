--- claudeusage.lua
--- A minimal Claude usage-limit indicator for the macOS menu bar, in Hammerspoon.
---
--- Reads the Claude Code OAuth token (Keychain, or ~/.claude/.credentials.json)
--- and polls https://api.anthropic.com/api/oauth/usage.
---
--- Install: symlink into ~/.hammerspoon/, then in init.lua:
---   claudeUsage = require("claudeusage").start()

local M = {}

-- ── config ────────────────────────────────────────────────────────────────────

M.refreshInterval = 300 -- seconds
M.warnAt = 50           -- amber above this %
M.alertAt = 80          -- red above this %
M.showIconOnly = false  -- true = just the Claude icon, no number

-- ── state ─────────────────────────────────────────────────────────────────────

local bar, timer
local raw, err = nil, nil

-- ── credentials ───────────────────────────────────────────────────────────────

local function readCredentialBlob()
  -- macOS: Claude Code stores creds in the login Keychain.
  -- First run will prompt for access; choose "Always Allow".
  local out = hs.execute(
    [[security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null]]
  )
  if out and out ~= "" then return out end

  -- Fallback: file-based credentials.
  local f = io.open(os.getenv("HOME") .. "/.claude/.credentials.json", "r")
  if f then
    local contents = f:read("*a")
    f:close()
    if contents and contents ~= "" then return contents end
  end
  return nil
end

local function readToken()
  local blob = readCredentialBlob()
  if not blob then
    return nil, "no Claude credentials found"
  end

  local ok, decoded = pcall(hs.json.decode, blob)
  if not ok or type(decoded) ~= "table" then
    return nil, "credentials are not valid JSON"
  end

  local oauth = decoded.claudeAiOauth
  if not oauth or not oauth.accessToken then
    -- Some Claude Code builds store only mcpOAuth state here.
    return nil, "no claudeAiOauth entry — run `claude` and re-login"
  end

  -- The usage endpoint needs user:profile; inference-only tokens get a 403.
  if oauth.scopes then
    local hasProfile = false
    for _, s in ipairs(oauth.scopes) do
      if s == "user:profile" then hasProfile = true end
    end
    if not hasProfile then
      return nil, "token lacks user:profile scope"
    end
  end

  return oauth.accessToken, nil
end

-- ── formatting helpers ────────────────────────────────────────────────────────

-- Top-level windows (five_hour, seven_day, ...) carry `utilization`.
-- Entries inside the `limits` array carry `percent`. Both are 0-100.
local function pct(entry)
  if type(entry) ~= "table" then return nil end
  local u = entry.utilization
  if type(u) ~= "number" then u = entry.percent end
  if type(u) ~= "number" then return nil end
  return math.floor(u + 0.5)
end

-- Newer per-model weekly limits (e.g. Fable) are not top-level keys. They live
-- in `limits`, scoped by scope.model.display_name. Returns {label, entry} pairs.
local function modelLimits(data)
  local found = {}
  if type(data.limits) ~= "table" then return found end
  for _, entry in ipairs(data.limits) do
    if type(entry) == "table" then
      local scope = entry.scope
      local model = type(scope) == "table" and scope.model or nil
      local name = type(model) == "table" and model.display_name or nil
      -- Skip near-zero bars; the reference app hides anything under 1%.
      if type(name) == "string" and (pct(entry) or 0) >= 1 then
        table.insert(found, { "Weekly " .. name, entry })
      end
    end
  end
  return found
end

-- ISO-8601 (UTC) -> "2h 14m"
local function resetsIn(iso)
  if type(iso) ~= "string" then return nil end
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end

  local utc = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
  })
  -- os.time() reads the table as local time, so shift by the UTC offset.
  local offset = os.difftime(os.time(), os.time(os.date("!*t", os.time())))
  local delta = (utc + offset) - os.time()

  if delta <= 0 then return "now" end
  local days = math.floor(delta / 86400)
  local hours = math.floor((delta % 86400) / 3600)
  local mins = math.floor((delta % 3600) / 60)
  if days > 0 then return string.format("%dd %dh", days, hours) end
  if hours > 0 then return string.format("%dh %dm", hours, mins) end
  return string.format("%dm", mins)
end

local function colorFor(p)
  if not p then return { white = 0.6 } end
  if p >= M.alertAt then return { red = 0.85, green = 0.20, blue = 0.20 } end
  if p >= M.warnAt then return { red = 0.90, green = 0.62, blue = 0.10 } end
  return { red = 0.851, green = 0.467, blue = 0.341 } -- Claude rust, #D97757
end

-- The Claude "spark" mark, drawn as a 12-ray asterisk and tinted per usage
-- color. Passed to setIcon with template=false, else macOS flattens the tint.
local iconCache = {}
local function claudeIcon(color)
  local key = string.format("%.2f/%.2f/%.2f/%.2f",
    color.red or 0, color.green or 0, color.blue or 0, color.white or -1)
  if iconCache[key] then return iconCache[key] end

  local size = 18
  local cx, cy = size / 2, size / 2
  local rOuter, rInner = size * 0.44, size * 0.12
  local canvas = hs.canvas.new({ x = 0, y = 0, w = size, h = size })
  for i = 0, 11 do
    local a = i * math.pi / 6
    canvas[#canvas + 1] = {
      type = "segments",
      coordinates = {
        { x = cx + rInner * math.cos(a), y = cy + rInner * math.sin(a) },
        { x = cx + rOuter * math.cos(a), y = cy + rOuter * math.sin(a) },
      },
      action = "stroke",
      strokeWidth = 1.7,
      strokeCapStyle = "round",
      strokeColor = color,
    }
  end
  local img = canvas:imageFromCanvas()
  canvas:delete()
  iconCache[key] = img
  return img
end

local function bar10(p)
  if not p then return "──────────" end
  local filled = math.floor((math.min(p, 100) / 100) * 10 + 0.5)
  return string.rep("█", filled) .. string.rep("░", 10 - filled)
end

local function row(label, entry)
  local p = pct(entry)
  if not p then return nil end
  local reset = resetsIn(entry.resets_at or entry.resetsAt)
  return string.format(
    "%-14s %s %3d%%%s",
    label, bar10(p), p, reset and ("  · " .. reset) or ""
  )
end

-- ── rendering ─────────────────────────────────────────────────────────────────

local function render()
  if not bar then return end

  if err or not raw then
    bar:setIcon(claudeIcon({ white = 0.6 }), false)
    bar:setTitle(hs.styledtext.new(" ⚠︎", {
      font = { name = "Menlo", size = 13 },
      color = { white = 0.6 },
    }))
    bar:setMenu({
      { title = "Claude usage unavailable", disabled = true },
      { title = err or "no data yet", disabled = true },
      { title = "-" },
      { title = "Refresh now", fn = function() M.refresh() end },
    })
    return
  end

  local session = pct(raw.five_hour)
  local weekly = pct(raw.seven_day)
  local headline = math.max(session or 0, weekly or 0)
  local color = colorFor(headline)

  bar:setIcon(claudeIcon(color), false)
  if M.showIconOnly then
    bar:setTitle(nil)
  else
    bar:setTitle(hs.styledtext.new(string.format(" %d%%", headline), {
      font = { name = "Menlo", size = 13 },
      color = color,
    }))
  end

  local menu = {}
  local pairsToShow = {
    { "Session (5h)", raw.five_hour },
    { "Weekly", raw.seven_day },
    { "Weekly Sonnet", raw.seven_day_sonnet },
    { "Weekly Opus", raw.seven_day_opus },
  }
  for _, extra in ipairs(modelLimits(raw)) do
    table.insert(pairsToShow, extra)
  end
  for _, pairEntry in ipairs(pairsToShow) do
    local line = row(pairEntry[1], pairEntry[2])
    if line then
      table.insert(menu, {
        title = hs.styledtext.new(line, { font = { name = "Menlo", size = 12 } }),
        disabled = true,
      })
    end
  end

  -- Extra usage: amounts are in minor units; `decimal_places` says how many.
  -- Verified OAuth payload uses `monthly_limit` (not `monthly_credit_limit`).
  if type(raw.extra_usage) == "table" then
    local e = raw.extra_usage
    local used = e.used_credits or e.used_cents
    local limit = e.monthly_credit_limit or e.monthly_limit or e.limit_cents
    local divisor = 10 ^ (type(e.decimal_places) == "number" and e.decimal_places or 2)
    local symbol = (e.currency == "EUR" and "€") or "$"
    if e.is_enabled ~= false
        and type(used) == "number" and type(limit) == "number" and limit > 0 then
      table.insert(menu, {
        title = hs.styledtext.new(
          string.format("%-14s %s%.2f of %s%.2f",
            "Extra usage", symbol, used / divisor, symbol, limit / divisor),
          { font = { name = "Menlo", size = 12 } }
        ),
        disabled = true,
      })
    end
  end

  if #menu == 0 then
    table.insert(menu, { title = "No usage windows returned", disabled = true })
  end

  table.insert(menu, { title = "-" })
  table.insert(menu, {
    title = "Refresh now",
    fn = function() M.refresh() end,
  })
  table.insert(menu, {
    title = "Open usage settings",
    fn = function() hs.urlevent.openURL("https://claude.ai/settings/usage") end,
  })
  table.insert(menu, {
    title = "Copy raw JSON",
    fn = function() hs.pasteboard.setContents(hs.json.encode(raw, true)) end,
  })

  bar:setMenu(menu)
  bar:setTooltip("Claude usage · updated " .. os.date("%H:%M"))
end

-- ── fetch ─────────────────────────────────────────────────────────────────────

function M.refresh()
  local token, terr = readToken()
  if not token then
    raw, err = nil, terr
    render()
    return
  end

  hs.http.asyncGet(
    "https://api.anthropic.com/api/oauth/usage",
    {
      ["Authorization"] = "Bearer " .. token,
      ["anthropic-beta"] = "oauth-2025-04-20",
      ["Accept"] = "application/json",
    },
    function(status, body)
      if status == 401 or status == 403 then
        raw, err = nil, "auth rejected (" .. status .. ") — run `claude` to refresh"
      elseif status ~= 200 then
        raw, err = nil, "HTTP " .. tostring(status)
      else
        local ok, decoded = pcall(hs.json.decode, body)
        if ok and type(decoded) == "table" then
          raw, err = decoded, nil
        else
          raw, err = nil, "could not parse response"
        end
      end
      render()
    end
  )
end

-- ── lifecycle ─────────────────────────────────────────────────────────────────

function M.start()
  M.stop()
  bar = hs.menubar.new()
  bar:setIcon(claudeIcon({ white = 0.6 }), false)
  bar:setTitle("…")
  M.refresh()
  timer = hs.timer.doEvery(M.refreshInterval, function() M.refresh() end)
  return M
end

function M.stop()
  if timer then timer:stop(); timer = nil end
  if bar then bar:delete(); bar = nil end
  return M
end

return M
