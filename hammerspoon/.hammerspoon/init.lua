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

-- Window snapping (alt+shift+h/j/k/l move, alt+f fullscreen) is delegated to
-- AeroSpace, which owns those chords.

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

-- Drawing tool: alt+p normally belongs to AeroSpace (switch to workspace P),
-- but Hammerspoon claims the chord here to bootstrap the tool on first use.
-- If the drawing window doesn't exist yet, launch it and drop it into
-- workspace P; if it's already running, just fall back to AeroSpace's
-- ordinary workspace-switch behavior.
local AEROSPACE = "/opt/homebrew/bin/aerospace"

local function findDrawingWindow()
  for _, win in ipairs(hs.window.allWindows()) do
    if win:title():find("JUST%sDRAW") then return win end
  end
  return nil
end

hs.hotkey.bind({ "alt" }, "p", function()
  if findDrawingWindow() then
    hs.execute(AEROSPACE .. " workspace P")
    return
  end

  local drawing_path = os.getenv("HOME") .. "/.local/bin/just_draw"
  local task = hs.task.new(drawing_path, function(code, _, stderr)
    if code ~= 0 then hs.notify.show("Just Draw", stderr) end
  end)

  if task then
    task:start()
    local attempt = 0
    while true do
      hs.execute("sleep 0.2")
      if findDrawingWindow() then break end
      if attempt >= 5 then
        hs.notify.show("Error", "Cannot find drawing window", "")
        task:terminate()
        return
      end
      attempt = attempt + 1
    end
    hs.execute(AEROSPACE .. " move-node-to-workspace --focus-follows-window P")
  end
end)

-- Spotify controls (spotify_player CLI)
local SPOTIFY_PLAYER = os.getenv("HOME") .. "/.local/bin/spotify_player"

-- Run spotify_player with arbitrary args. cb(code, stdout, stderr) is optional;
-- without it, a non-zero exit raises a notification.
local function spRun(args, cb)
  hs.task.new(SPOTIFY_PLAYER, function(code, out, err)
    if cb then
      cb(code, out, err)
    elseif code ~= 0 then
      hs.notify.show("spotify_player", "", err or "")
    end
  end, args):start()
end

-- Shorthand for `playback` subcommands.
local function spotify(...)
  spRun({ "playback", ... })
end

hs.hotkey.bind({ "alt" }, "space", function() spotify("play-pause") end)
hs.hotkey.bind({ "alt" }, "[", function() spotify("previous") end)
hs.hotkey.bind({ "alt" }, "]", function() spotify("next") end)
hs.hotkey.bind({ "alt" }, "down", function() spotify("volume", "--offset", "--", "-5") end)
hs.hotkey.bind({ "alt" }, "up", function() spotify("volume", "--offset", "5") end)
hs.hotkey.bind({ "alt", "shift" }, "[", function()
  spRun({ "like" }, function(code, _, err)
    if code == 0 then hs.alert.show("Liked") else hs.alert.show("Like error: " .. (err or "")) end
  end)
end)
-- Spotify has no "dislike"; closest to the old Apple Music behaviour is unlike.
hs.hotkey.bind({ "alt", "shift" }, "\\", function()
  spRun({ "like", "--unlike" }, function(code, _, err)
    if code == 0 then hs.alert.show("Unliked") else hs.alert.show("Unlike error: " .. (err or "")) end
  end)
end)
hs.hotkey.bind({ "alt", "shift" }, "]", function()
  local prev = hs.window.focusedWindow()

  spRun({ "playlist", "list" }, function(code, out)
    if code ~= 0 or not out then
      hs.alert.show("Could not fetch playlists")
      return
    end

    -- Each line is "<playlist_id>: <name>".
    local choices = {}
    for line in out:gmatch("[^\n]+") do
      local id, name = line:match("^(%S+):%s*(.+)$")
      if id and name then
        table.insert(choices, { text = name, subText = id, playlistId = id })
      end
    end

    local chooser = hs.chooser.new(function(choice)
      if prev then prev:focus() end
      if not choice then return end

      -- Resolve the currently playing track, then add it to the chosen playlist.
      spRun({ "get", "key", "playback" }, function(c2, out2)
        local data = out2 and hs.json.decode(out2)
        local trackId = data and data.item and data.item.id
        if not trackId then
          hs.alert.show("No current track")
          return
        end
        spRun({ "playlist", "edit", "--track-id", trackId, "add", choice.playlistId }, function(c3, _, err3)
          if c3 == 0 then
            hs.alert.show("Added to " .. choice.text)
          else
            hs.alert.show("Playlist error: " .. (err3 or ""))
          end
        end)
      end)
    end)

    chooser:choices(choices)
    chooser:show()
  end)
end)

-- EarPods / media-key remap -> spotify_player
-- The EarPods center button (and the keyboard media keys) emit system-defined
-- media events, not keystrokes. macOS maps the center button as:
--   single press -> PLAY, double -> NEXT, triple -> PREVIOUS.
-- We swallow those events so Apple Music never reacts, and drive spotify_player
-- instead. Note: there is no way to tell EarPods apart from the keyboard media
-- keys -- both send the identical events, so this captures both.
-- (SPOTIFY_PLAYER / spotify() are defined in the Spotify controls block above.)
-- The EarPods center button is a single physical button: it only ever emits
-- PLAY. macOS normally derives next/previous from the tap count via MediaRemote
-- (1 tap = play/pause, 2 = next, 3 = previous), but since we swallow those
-- events that translation never runs -- so we count the taps ourselves.
-- We also distinguish a hold (press > HOLD_THRESHOLD) and use it to mute the mic.
local TAP_WINDOW     = 0.4 -- seconds to wait for further taps before acting
local HOLD_THRESHOLD = 0.6 -- press held longer than this = mic mute toggle
local playTapCount   = 0
local playTapTimer   = nil
local holdTimer      = nil
local heldFired      = false

-- Toggle the default input device's mute state.
local function toggleMicMute()
  local dev = hs.audiodevice.defaultInputDevice()
  if not dev then hs.alert.show("No input device"); return end

  local muted = dev:inputMuted()
  if muted ~= nil then
    dev:setInputMuted(not muted)
    hs.alert.show(not muted and "Mic muted 🔇" or "Mic unmuted 🎙️")
  else
    -- Device doesn't report mute support; fall back to zeroing input volume.
    local vol = dev:inputVolume() or 0
    dev:setInputVolume(vol > 0 and 0 or 100)
    hs.alert.show(vol > 0 and "Mic muted 🔇" or "Mic unmuted 🎙️")
  end
end

local function handlePlayTaps()
  local n = playTapCount
  playTapCount = 0
  if n >= 3 then
    spotify("previous")
  elseif n == 2 then
    spotify("next")
  else
    spotify("play-pause")
  end
end

-- PLAY key-down: arm the hold timer (ignore auto-repeat presses).
local function onPlayDown()
  heldFired = false
  if holdTimer then holdTimer:stop() end
  holdTimer = hs.timer.doAfter(HOLD_THRESHOLD, function()
    heldFired = true
    toggleMicMute()
  end)
end

-- PLAY key-up: if the hold already fired, swallow the release; otherwise it was
-- a discrete tap, so feed the tap counter.
local function onPlayUp()
  if holdTimer then holdTimer:stop(); holdTimer = nil end
  if heldFired then
    heldFired = false
    return
  end
  playTapCount = playTapCount + 1
  if playTapTimer then playTapTimer:stop() end
  playTapTimer = hs.timer.doAfter(TAP_WINDOW, handlePlayTaps)
end

local mediaKeyActions = {
  -- Kept in case a keyboard/other device emits these directly.
  NEXT     = function() spotify("next") end,
  PREVIOUS = function() spotify("previous") end,
}

mediaKeyTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(event)
  local d = event:systemKey()
  if not d then return false end
  -- PLAY needs both edges: down arms the hold timer, up decides tap vs hold.
  if d.key == "PLAY" then
    if d.down then
      if not d.repeated then onPlayDown() end
    else
      onPlayUp()
    end
    return true
  end
  local action = mediaKeyActions[d.key]
  -- Fire once, on key-down only (system events send both down and up).
  if action and d.down then action() end
  -- Swallow PLAY/NEXT/PREVIOUS entirely; let everything else (volume, etc.) pass.
  return action ~= nil
end)
mediaKeyTap:start()

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
