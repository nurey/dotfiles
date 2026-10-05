-- Network Location follows Wi-Fi: "Home" on the home SSID, "Automatic" elsewhere.
-- The two Locations differ only in DNS (Home pins an internal resolver on Wi-Fi).
--
-- Reading the SSID at all requires Location Services authorization on macOS 14+;
-- init.lua calls hs.location.start() to register Hammerspoon with locationd.
-- Without it hs.wifi.currentNetwork() returns nil and nothing here works.
--
-- Switching Locations needs root, which a watcher callback cannot prompt for, so
-- it goes through /etc/sudoers.d/wifi-location (two literal commands, no wildcards).
--
-- The home SSID lives in ~/.hammerspoon/wifi-location.local.lua, deliberately
-- outside this public repo.
--
-- Locations are system-wide, so on logout, shutdown, or fast-user-switching away
-- it drops back to "Automatic"; other accounts on the machine never inherit Home.

local M = {}

local HOME_LOCATION, AWAY_LOCATION = "Home", "Automatic"
local NETSETUP     = "/usr/sbin/networksetup"
local COOLDOWN     = 45    -- min seconds between switches; backstop against flapping
local SETTLE       = 30    -- how long an unassociated radio counts as "still settling"
local POLL         = 120   -- safety net, so a missed event still converges
local LOCAL_CONFIG = os.getenv("HOME") .. "/.hammerspoon/wifi-location.local.lua"

local log        = hs.logger.new("wifiloc", "info")
local lastSwitch = 0
local nilSince   = nil
local retries    = {}
local homeNet    = nil
local paused     = false  -- true while our session is inactive or logging out
local resumer    = nil

local function currentLocation()
  return (hs.execute(NETSETUP .. " -getcurrentlocation") or ""):gsub("%s+$", "")
end

-- The Location we ought to be in, or nil when we genuinely can't tell yet.
local function desiredLocation()
  local d = hs.wifi.interfaceDetails() or {}

  if d.ssid then
    nilSince = nil
    local home = d.ssid == homeNet.ssid
                 and (homeNet.bssid == nil or d.bssid == homeNet.bssid)
    return home and HOME_LOCATION or AWAY_LOCATION
  end

  if d.power == false then   -- radio off: definitively not on the home network
    nilSince = nil
    return AWAY_LOCATION
  end

  -- Powered on but unassociated: either mid-association (normal right after a
  -- Location switch, a wake, or a reconnect) or genuinely nothing in range.
  -- Calling this "away" too eagerly is exactly what causes flapping, so wait.
  nilSince = nilSince or os.time()
  if os.time() - nilSince >= SETTLE then return AWAY_LOCATION end
  return nil
end

local function switchTo(want, cur, notify)
  lastSwitch = os.time()
  local _, ok = hs.execute("sudo -n " .. NETSETUP .. " -switchtolocation " .. want)
  if ok then
    log.f("network location %s -> %s", cur, want)
    if notify then
      hs.notify.new({ title = "Network location",
                      informativeText = cur .. " → " .. want }):send()
    end
  else
    log.ef("switch %s -> %s failed; check /etc/sudoers.d/wifi-location", cur, want)
  end
end

local function reconcile()
  if not homeNet or paused then return end

  local want = desiredLocation()
  if not want then return end

  local cur = currentLocation()
  -- Idempotence also breaks the feedback loop: switching Locations rewrites
  -- preferences.plist and reconfigures Wi-Fi, which fires a fresh event at us.
  if cur == want then return end

  if os.time() - lastSwitch < COOLDOWN then
    log.f("cooldown active: want %s, have %s", want, cur)
    return
  end

  switchTo(want, cur, true)
end

-- Locations are system-wide, so hand the machine back on "Automatic" whenever
-- this session stops being the one in front: other users must not inherit Home.
-- Bypasses the cooldown, and pauses reconcile() so the poll can't flip it back.
local function relinquish(why)
  paused = true
  local cur = currentLocation()
  if cur ~= AWAY_LOCATION then
    log.f("%s: relinquishing %s", why, cur)
    switchTo(AWAY_LOCATION, cur, false)
  end
end

-- Staggered non-blocking retries cover the association settle window.
-- Hammerspoon is single-threaded, so a sleep loop would freeze the UI. Extra
-- calls cost nothing because reconcile() is idempotent.
local function reconcileSoon()
  for _, delay in ipairs({ 0, 3, 8, 15 }) do
    retries[#retries + 1] = hs.timer.doAfter(delay, reconcile)
  end
  for i = #retries, 1, -1 do          -- prune fired timers so this can't grow
    if not retries[i]:running() then table.remove(retries, i) end
  end
end

--- Reconcile the current network Location against the current Wi-Fi network.
--- Exposed so it can be triggered by hand: require("wifi-location").sync()
function M.sync()
  reconcile()
  return M
end

function M.start()
  local ok, cfg = pcall(dofile, LOCAL_CONFIG)
  if not ok or type(cfg) ~= "table" or not cfg.ssid then
    log.w("no readable " .. LOCAL_CONFIG .. "; Location switching disabled")
    return M
  end
  homeNet = cfg

  -- powerChange and linkChange matter as much as SSIDChange here: the radio going
  -- down is what distinguishes "away" from "still associating".
  M.watcher = hs.wifi.watcher.new(function() reconcileSoon() end)
                             :watchingFor({ "SSIDChange", "powerChange", "linkChange" })
                             :start()

  -- systemWillPowerOff fires on logout as well as shutdown/restart (not on a
  -- Hammerspoon reload). If the logout is cancelled we are still alive a minute
  -- later, so resume. Fast user switching keeps this process running in the
  -- background, hence pausing for the whole time the session is inactive.
  local cw = hs.caffeinate.watcher
  M.session = cw.new(function(event)
    if event == cw.systemWillPowerOff then
      relinquish("logout/shutdown")
      if resumer then resumer:stop() end
      resumer = hs.timer.doAfter(60, function() paused = false ; reconcileSoon() end)
    elseif event == cw.sessionDidResignActive then
      if resumer then resumer:stop() ; resumer = nil end
      relinquish("session switched away")
    elseif event == cw.sessionDidBecomeActive then
      paused = false
      reconcileSoon()
    end
  end):start()

  reconcileSoon()                             -- converge at load, not only on events
  M.timer = hs.timer.doEvery(POLL, reconcile)  -- retained on M so it isn't collected
  return M
end

function M.stop()
  if M.watcher then M.watcher:stop() ; M.watcher = nil end
  if M.timer then M.timer:stop() ; M.timer = nil end
  if M.session then M.session:stop() ; M.session = nil end
  if resumer then resumer:stop() ; resumer = nil end
  return M
end

return M
