hs.loadSpoon("EmmyLua")

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

-- Apple Music controls
hs.hotkey.bind({ "alt" }, "space", function() hs.itunes.playpause() end)
hs.hotkey.bind({ "alt" }, "[", function() hs.itunes.previous() end)
hs.hotkey.bind({ "alt" }, "]", function() hs.itunes.next() end)
hs.hotkey.bind({ "alt" }, "-", function() hs.itunes.setVolume(math.max(0, hs.itunes.getVolume() - 5)) end)
hs.hotkey.bind({ "alt" }, "=", function() hs.itunes.setVolume(math.min(100, hs.itunes.getVolume() + 5)) end)
hs.hotkey.bind({ "alt", "shift" }, "[", function()
  local ok, _, err = hs.osascript.applescript([[
    tell application "Music"
      set favorited of current track to true
    end tell
  ]])
  if ok then hs.alert.show("Liked") else hs.alert.show("Like error: " .. (err or "")) end
end)
hs.hotkey.bind({ "alt", "shift" }, "\\", function()
  local ok, _, err = hs.osascript.applescript([[
    tell application "Music"
      set disliked of current track to true
    end tell
  ]])
  if ok then hs.alert.show("Disliked") else hs.alert.show("Dislike error: " .. (err or "")) end
end)
hs.hotkey.bind({ "alt", "shift" }, "]", function()
  local prev = hs.window.focusedWindow()

  local ok, playlists = hs.osascript.applescript([[
    tell application "Music" to return name of every user playlist
  ]])
  if not ok or not playlists then
    hs.alert.show("Could not fetch playlists")
    return
  end

  local choices = {}
  for _, name in ipairs(playlists) do
    table.insert(choices, { text = name })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then
      if prev then prev:focus() end
      return
    end
    local playlist = choice.text
    local ok2, _, err = hs.osascript.applescript(string.format([[
      tell application "Music" to activate
      tell application "System Events"
        tell process "Music"
          set sg to splitter group 1 of window 1
          set playbackBtns to every button of group 1 of group 2 of sg
          set moreBtn to missing value
          repeat with b in playbackBtns
            if description of b is "More" then
              set moreBtn to b
              exit repeat
            end if
          end repeat
          if moreBtn is missing value then error "More button not found"
          click moreBtn
          delay 0.2
          set m to menu 1 of moreBtn
          click menu item "%s" of menu 1 of menu item "Add to Playlist" of m
        end tell
      end tell
    ]], playlist))
    if prev then prev:focus() end
    if ok2 then hs.alert.show("Added to " .. playlist) else hs.alert.show("Playlist error: " .. (err or "")) end
  end)

  chooser:choices(choices)
  chooser:show()
end)

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
hs.hotkey.bind({ "alt" }, "n", function()
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
