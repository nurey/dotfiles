hs.logger.defaultLogLevel="info"

hyper       = {"cmd","alt","ctrl"}
shift_hyper = {"cmd","alt","ctrl","shift"}
ctrl_cmd    = {"cmd","ctrl"}

col = hs.drawing.color.x11

hs.loadSpoon("SpoonInstall")

spoon.SpoonInstall.use_syncinstall = true

Install=spoon.SpoonInstall

Install:andUse("EjectMenu", {
  config = {
    eject_on_lid_close = true,
    eject_on_sleep = true,
    show_in_menubar = false,
    notify = true,
  },
  hotkeys = { ejectAll = { hyper, "=" } },
  start = true,
--                 loglevel = 'debug'
})

Install:andUse("MenubarFlag",
               {
                 config = {
                   colors = {
                     ["Canadian"] = { },
                     Spanish = {col.green, col.white, col.red},
                     ["Russian - QWERTY"] = {col.black, col.red, col.yellow},
                   }
                 },
                 start = true
               }
)
