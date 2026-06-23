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

-- Window snapping / resizing
local function resize_window(position)
  local win    = hs.window.focusedWindow()
  local screen = win:screen()
  local max    = screen:frame()
  local f      = win:frame()

  if position == "l" then
    f.x = max.x; f.y = max.y; f.w = max.w / 2; f.h = max.h
  elseif position == "r" then
    f.x = max.x + max.w / 2; f.y = max.y; f.w = max.w / 2; f.h = max.h
  elseif position == "t" then
    f.x = max.x; f.y = max.y; f.w = max.w; f.h = max.h / 2
  elseif position == "b" then
    f.x = max.x; f.y = max.y + max.h / 2; f.w = max.w; f.h = max.h / 2
  elseif position == "f" then
    f.x = max.x; f.y = max.y; f.w = max.w; f.h = max.h
  else
    hs.alert.show("Incorrect direction: " .. position)
    return
  end
  win:setFrame(f)
end

hs.hotkey.bind({ "alt", "shift" }, "h", function() resize_window("l") end)
hs.hotkey.bind({ "alt", "shift" }, "l", function() resize_window("r") end)
hs.hotkey.bind({ "alt", "shift" }, "k", function() resize_window("t") end)
hs.hotkey.bind({ "alt", "shift" }, "j", function() resize_window("b") end)
hs.hotkey.bind({ "alt" }, "f", function() resize_window("f") end)

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

-- Drawing tool
hs.hotkey.bind({ "alt" }, "p", function()
  local drawing_path = os.getenv("HOME") .. "/.local/bin/just_draw"
  local task = hs.task.new(drawing_path, function(code, _, stderr)
    if code ~= 0 then hs.notify.show("Just Draw", stderr) end
  end)

  if task then
    task:start()
    local attempt = 0
    while true do
      hs.execute("sleep 0.2")
      local win = hs.window.focusedWindow()
      if win and win:title():find("JUST%sDRAW") then
        break
      end
      if attempt >= 5 then
        hs.notify.show("Error", "Cannot find drawing window", "")
        task:terminate()
        return
      end
      attempt = attempt + 1
    end
  end
end)

-- Mouse highlight
local mouseCircle      = nil
local mouseCircleTimer = nil

local function mouseHighlight()
  if mouseCircle then
    mouseCircle:delete()
    if mouseCircleTimer then mouseCircleTimer:stop() end
  end
  local mousepoint = hs.mouse.absolutePosition()
  mouseCircle = hs.drawing.circle(hs.geometry.rect(mousepoint.x - 40, mousepoint.y - 40, 80, 80))
  if not mouseCircle then return end
  mouseCircle:setStrokeColor({ red = 1, blue = 0, green = 0, alpha = 1 })
  mouseCircle:setFill(false)
  mouseCircle:setStrokeWidth(5)
  mouseCircle:show()
  mouseCircleTimer = hs.timer.doAfter(2, function()
    mouseCircle:delete()
    mouseCircle = nil
  end)
end

hs.hotkey.bind({ "alt", "shift" }, "c", mouseHighlight)

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
hs.hotkey.bind({ "alt" }, "-", function() spotify("volume", "--offset", "--", "-5") end)
hs.hotkey.bind({ "alt" }, "=", function() spotify("volume", "--offset", "5") end)
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
local TAP_WINDOW   = 0.4 -- seconds to wait for further taps before acting
local playTapCount = 0
local playTapTimer = nil

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

local function onPlayPress()
  playTapCount = playTapCount + 1
  if playTapTimer then playTapTimer:stop() end
  playTapTimer = hs.timer.doAfter(TAP_WINDOW, handlePlayTaps)
end

local mediaKeyActions = {
  PLAY     = onPlayPress,
  -- Kept in case a keyboard/other device emits these directly.
  NEXT     = function() spotify("next") end,
  PREVIOUS = function() spotify("previous") end,
}

mediaKeyTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(event)
  local d = event:systemKey()
  if not d then return false end
  local action = mediaKeyActions[d.key]
  -- Fire once, on key-down only (system events send both down and up).
  if action and d.down then action() end
  -- Swallow PLAY/NEXT/PREVIOUS entirely; let everything else (volume, etc.) pass.
  return action ~= nil
end)
mediaKeyTap:start()

-- jn timer integration
local function initJn(category)
  local b, description = hs.dialog.textPrompt(
    "[" .. category .. "] Insert the description", "Task to do it", "", "OK", "Cancel"
  )
  if b == "Cancel" or not description then
    return
  end

  local jnPath = "/Users/richard/.local/bin/jn"
  hs.alert.show("Starting timer for: " .. category)

  local cmd = string.format(
    "nohup %s -t 1h -c %q -n break -d -l %q > /tmp/jn.log 2>&1 &",
    jnPath, category, description
  )

  local ok = hs.task.new("/bin/sleep", function(exitCode, _, _)
    if exitCode == 0 then
      hs.notify.show("Time has been finalized", description, "Task completed")
    end
  end, { "3600" }):start()

  if not ok then hs.alert.show("Error starting sleep command") end
  local _, status = hs.execute(cmd)
  if not status then hs.alert.show("Failed to start detached task") end
end

hs.hotkey.bind({ "alt" }, "/", function() initJn("programming") end)
hs.hotkey.bind({ "alt" }, ".", function() initJn("work") end)
hs.hotkey.bind({ "alt" }, ",", function()
  local b, category = hs.dialog.textPrompt("Insert category", "Indicate topic", "work", "OK", "Cancel")
  if b == "Cancel" or not category then
    return
  end
  initJn(category)
end)

-- Neospeller
hs.hotkey.bind({ "alt" }, "g", function()
  hs.execute("~/.local/bin/ns-clip", true)
end)

-- Quick Note: open a NEW Quick Note (alt+n)
-- Temporarily disables "resume last Quick Note" so fn+Q opens a fresh note,
-- then restores the original preference.
hs.hotkey.bind({ "alt", "shift" }, "n", function()
  local currentVal, _, _ = hs.execute("defaults read com.apple.Notes ICShouldResumeLastQuickNote 2>/dev/null")
  currentVal = currentVal:gsub("%s+", "")

  -- Disable "resume last" so Quick Note opens a new blank note
  hs.execute("defaults write com.apple.Notes ICShouldResumeLastQuickNote -bool false")

  -- Open Quick Note via fn+Q
  hs.eventtap.keyStroke({ "fn" }, "q", 0)

  -- Restore original preference after Quick Note has opened
  hs.timer.doAfter(0.5, function()
    if currentVal == "1" then
      hs.execute("defaults write com.apple.Notes ICShouldResumeLastQuickNote -bool true")
    elseif currentVal == "0" then
      -- was already false, leave it
    else
      -- key didn't exist (default = resume last), restore by deleting
      hs.execute("defaults delete com.apple.Notes ICShouldResumeLastQuickNote 2>/dev/null")
    end
  end)
end)

hs.application.enableSpotlightForNameSearches(true)
hs.loadSpoon('ControlEscape'):start()

-- Route http(s) URLs to Brave profiles (see brouter.lua + ~/.config/brouter/rules.json).
-- Portable: this only installs the URL handler. Making Hammerspoon the *default*
-- browser is a per-machine, one-time step:
--   hs -c 'hs.urlevent.setDefaultHandler("http")'
require("brouter")
