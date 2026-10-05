-- Wi-Fi DNS toggle: Pi-hole <-> DHCP
--
-- The Pi-hole address lives in ~/.hammerspoon/pihole_dns.local.lua, deliberately
-- outside this public repo. It returns a table: return { ip = "x.x.x.x" }

local LOCAL_CONFIG = os.getenv("HOME") .. "/.hammerspoon/pihole_dns.local.lua"

local ok, cfg = pcall(dofile, LOCAL_CONFIG)
if not ok or type(cfg) ~= "table" or not cfg.ip then
  hs.logger.new("piholedns"):w("no readable " .. LOCAL_CONFIG .. "; DNS toggle disabled")
  return
end

local PIHOLE = cfg.ip
local SERVICE = "Wi-Fi"
local NS = "/usr/sbin/networksetup"

-- globals so they aren't garbage-collected after init.lua finishes
dnsMenu = hs.menubar.new()
dnsNetConf = hs.network.configuration.open()

local function currentDNS()
  local out = hs.execute(NS .. " -getdnsservers " .. SERVICE)
  return out:find(PIHOLE, 1, true) and "pihole" or "dhcp"
end

local function refresh()
  local mode = currentDNS()
  -- same glyph both states (narrow enough to survive the notch); dimmed when on DHCP
  dnsMenu:setTitle(hs.styledtext.new("π", {
    font = { size = 15 },
    color = { list = "System", name = mode == "pihole" and "labelColor" or "tertiaryLabelColor" },
  }))
  dnsMenu:setTooltip("Wi-Fi DNS: " .. (mode == "pihole" and PIHOLE or "DHCP"))
end

local function toggle()
  local target = currentDNS() == "pihole" and "empty" or PIHOLE
  hs.execute(NS .. " -setdnsservers " .. SERVICE .. " " .. target)
  hs.execute("dscacheutil -flushcache; killall -HUP mDNSResponder")
  refresh()
  hs.alert.show("DNS → " .. (target == "empty" and "DHCP" or "Pi-hole"))
end

dnsMenu:setClickCallback(toggle)
hs.hotkey.bind(hyper, "D", toggle)

-- keep the icon accurate if DNS changes elsewhere
dnsNetConf:monitorKeys("State:/Network/Global/DNS")
dnsNetConf:setCallback(refresh)
dnsNetConf:start()

refresh()
