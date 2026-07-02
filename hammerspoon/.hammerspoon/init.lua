hs.loadSpoon("EmmyLua")
require("hs.ipc")

-- ISO keyboard fix: put backtick/tilde (`/~) under Escape.
-- On a Spanish (ISO) Apple keyboard with the US layout, the key below Escape
-- (HID 0x35) emits §/± and the key next to left Shift (HID 0x64) emits `/~.
-- Swap them so ` is where it belongs (under Escape) and the useless §/± moves
-- next to Shift. Scope the swap to the built-in keyboard so external US
-- keyboards keep their normal key positions. Clear the old global mapping
-- first when migrating from the previous config.
hs.execute(
  [[hidutil property --set '{"UserKeyMapping":[]}' && ]] ..
  [[hidutil property --matching '{"Transport":"FIFO","PrimaryUsagePage":1,"PrimaryUsage":6}' --set '{"UserKeyMapping":[]] ..
  [[{"HIDKeyboardModifierMappingSrc":0x700000035,"HIDKeyboardModifierMappingDst":0x700000064},]] ..
  [[{"HIDKeyboardModifierMappingSrc":0x700000064,"HIDKeyboardModifierMappingDst":0x700000035}]] ..
  [[]}']]
)

hs.alert.show("Hammerspoon loaded 🤘")

hs.hotkey.bind({ "alt", "shift" }, "r", function()
  hs.reload()
end)

hs.window.animationDuration = 0

-- App focus/launch bindings (alt+1..9, alt+letter, alt+tab) live in apps.lua.
require("apps")

-- Recover all visible windows to center
hs.hotkey.bind({ "alt", "cmd" }, "r", function()
  local screen = hs.screen.mainScreen()
  local frame  = screen:frame()
  for _, win in ipairs(hs.window.allWindows()) do
    if win:isStandard() then
      local f = win:frame()
      f.x = frame.x + (frame.w / 2) - (f.w / 2)
      f.y = frame.y + (frame.h / 2) - (f.h / 2)
      win:setFrame(f)
    end
  end
  hs.alert.show("Windows recovered 🔥")
end)

-- EarPods / media keys: handled natively by macOS (MediaRemote does its own
-- tap counting and delivers play-pause/next/previous to the now-playing app).
-- Don't intercept them: an eventtap can't block that delivery, so any handling
-- here double-acts on playback (verified empirically 2026-07).

-- Neospeller
hs.hotkey.bind({ "alt" }, "g", function()
  hs.execute("~/.local/bin/ns-clip", true)
end)

hs.application.enableSpotlightForNameSearches(true)
hs.loadSpoon('ControlEscape'):start()

-- Route http(s) URLs to Brave profiles (see brouter.lua + ~/.config/brouter/rules.json).
-- Portable: this only installs the URL handler. Making Hammerspoon the *default*
-- browser is a per-machine, one-time step:
--   hs -c 'hs.urlevent.setDefaultHandler("http")'
require("brouter")
