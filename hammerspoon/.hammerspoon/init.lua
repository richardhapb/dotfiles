hs.loadSpoon("EmmyLua")

hs.alert.show("Hammerspoon loaded 🤘")

hs.hotkey.bind({ "alt", "shift" }, "r", function()
  hs.reload()
end)

local currentWorkspace = 1 -- must be initialized explicitly
local workspaceDataFile = os.getenv("HOME") .. "/.hammerspoon/workspaces.json"
local json = hs.json

-- Load saved workspace data
local function loadWorkspaceData()
  local file = io.open(workspaceDataFile, "r")
  if not file then return {} end
  local content = file:read("*a")
  file:close()
  return json.decode(content) or {}
end

-- Pseudo workspace manager
local workspaces = loadWorkspaceData()
local maxWorkspaces = 9
local windowsPosition = {}
local focusedWindow = {}

windowsPosition = setmetatable(windowsPosition, {
  __index = function(t, k)
    local v = rawget(t, k)
    if v ~= nil then
      return v
    end

    -- If not found, try to get window frame
    for _, win in ipairs(hs.window.allWindows()) do
      if tostring(win:id()) == k then
        -- Full screen by default
        local frame = win:frame()
        local screen = win:screen()
        local max = screen:frame()
        frame.x = max.x
        frame.y = max.y
        frame.w = max.w
        frame.h = max.h
        rawset(t, k, frame) -- Use rawset to avoid triggering __index
        return frame
      end
    end

    print("Window not found for id:", k)
    return nil
  end
})

focusedWindow = setmetatable(focusedWindow, {
  __index = function(t, k)
    local v = rawget(t, k)
    if v then
      return v
    end

    return hs.window.focusedWindow()
  end
})

-- Save current workspace mapping to file
local function saveWorkspaceData(data)
  local encoded = hs.json.encode(data)
  if not encoded then
    hs.alert.show("⚠️ JSON encoding failed")
    print("⚠️ Failed to encode workspace data")
    print(hs.inspect(data)) -- pretty-print for inspection
    return
  end

  local file, err = io.open(workspaceDataFile, "w+")
  if not file then
    hs.alert.show("⚠️ File write failed")
    print("⚠️ Failed to open file: " .. (err or "unknown error"))
    return
  end

  file:write(encoded)
  file:close()
end

--- Hide the window
---@param win hs.window
local function moveOffscreen(win)
  if not win then return end
  local f = win:frame()

  if f.x < 0 then
    return
  end

  local id = tostring(win:id())
  windowsPosition[id] = win:frame()
  f.x = -5000
  win:setFrame(f)
end

--- Hide all windows of an app if the app is not focused
---@param appName string
local function forceHideApp(appName)
  local script = string.format([[
    tell application "System Events"
      set visible of process "%s" to false
    end tell
  ]], appName)
  hs.osascript.applescript(script)
end

local function hideObstinateWindows(n)
  local appsToHide = { "Spotify", "Finder", "Brave", "ChatGPT" }

  for _, appName in ipairs(appsToHide) do
    local hide = true

    local app = hs.application.get(appName)
    if not app then goto continue end

    for _, win in ipairs(app:visibleWindows() or {}) do
      if workspaces[tostring(win:id())] == n then
        hide = false
        break
      end
    end
    if hide then forceHideApp(appName) end
    ::continue::
  end
end

-- Move the windows to the current workspace
local function showWorkspace(n)
  focusedWindow[currentWorkspace] = hs.window.focusedWindow()

  currentWorkspace = n
  hs.alert.show("Workspace " .. n)

  -- Show all windows in the workspace
  for _, win in ipairs(hs.window.allWindows()) do
    local id = tostring(win:id())
    if workspaces[id] == n then
      local app = win:application()
      local savedFrame = windowsPosition[id]

      if app then
        app:activate()
      end
      win:setFrame(savedFrame)
    else
      moveOffscreen(win)
    end
  end

  -- hideObstinateWindows(n)
  focusedWindow[n]:focus()
end

-- Move the window to workspace n
local function assignWindowToWorkspace(n)
  local win = hs.window.focusedWindow()
  if win then
    local id = tostring(win:id())
    workspaces[id] = n
    hs.alert.show("Window assigned to Workspace " .. n)
    saveWorkspaceData(workspaces)
    windowsPosition[id] = win:frame()
    moveOffscreen(win)
  end
end

-- Move all visible windows to the center of the screen
hs.hotkey.bind({ "alt", "cmd" }, "r", function()
  local screen = hs.screen.mainScreen()
  local frame = screen:frame()

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

-- Change the workspace using Alt + Number
for i = 1, maxWorkspaces do
  hs.hotkey.bind({ "alt" }, tostring(i), function()
    showWorkspace(i)
  end)

  -- Send the window to the workspace using Alt + Shift + Number
  hs.hotkey.bind({ "alt", "shift" }, tostring(i), function()
    assignWindowToWorkspace(i)
  end)
end

hs.hotkey.bind({ "alt" }, "h", function()
  hs.window.focusedWindow():moveOneScreenWest()
end)

hs.hotkey.bind({ "alt" }, "l", function()
  hs.window.focusedWindow():moveOneScreenEast()
end)

hs.hotkey.bind({ "alt" }, "k", function()
  hs.window.focusedWindow():moveOneScreenNorth()
end)

hs.hotkey.bind({ "alt" }, "j", function()
  hs.window.focusedWindow():moveOneScreenSouth()
end)

--- Send the window in a specified direction
---@param position "l" | "r" | "t" | "b" | "f"
local function resize_window(position)
  local win = hs.window.focusedWindow()
  local screen = win:screen()
  local max = screen:frame()
  local f = win:frame()

  if position == "l" then
    f.x = max.x
    f.y = max.y
    f.w = max.w / 2
    f.h = max.h
  elseif position == "r" then
    f.x = max.x + (max.w / 2)
    f.y = max.y
    f.w = max.w / 2
    f.h = max.h
  elseif position == "t" then
    f.x = max.x
    f.y = max.y
    f.w = max.w
    f.h = max.h / 2
  elseif position == "b" then
    f.x = max.x
    f.y = max.y + (max.h / 2)
    f.w = max.w
    f.h = max.h / 2
  elseif position == "f" then
    f.x = max.x
    f.y = max.y
    f.w = max.w
    f.h = max.h
  else
    hs.alert.show("Incorrect direction: " .. position)
    return
  end

  win:setFrame(f)
end

-- Snap the window to the left half of the screen
hs.hotkey.bind({ "alt", "shift" }, "h", function() resize_window("l") end)
hs.hotkey.bind({ "alt", "shift" }, "l", function() resize_window("r") end)
hs.hotkey.bind({ "alt", "shift" }, "k", function() resize_window("t") end)
hs.hotkey.bind({ "alt", "shift" }, "j", function() resize_window("b") end)
hs.hotkey.bind({ "alt" }, "f", function() resize_window("f") end)

local mouseCircle = nil
local mouseCircleTimer = nil

local function mouseHighlight()
  -- Delete an existing highlight if it exists
  if mouseCircle then
    mouseCircle:delete()
    if mouseCircleTimer then
      mouseCircleTimer:stop()
    end
  end
  -- Get the current co-ordinates of the mouse pointer
  local mousepoint = hs.mouse.absolutePosition()
  -- Prepare a big red circle around the mouse pointer
  mouseCircle = hs.drawing.circle(hs.geometry.rect(mousepoint.x - 40, mousepoint.y - 40, 80, 80))
  if not mouseCircle then
    return
  end
  mouseCircle:setStrokeColor({ ["red"] = 1, ["blue"] = 0, ["green"] = 0, ["alpha"] = 1 })
  mouseCircle:setFill(false)
  mouseCircle:setStrokeWidth(5)
  mouseCircle:show()

  -- Set a timer to delete the circle after 2 seconds
  mouseCircleTimer = hs.timer.doAfter(2, function()
    mouseCircle:delete()
    mouseCircle = nil
  end)
end

hs.hotkey.bind({ "cmd", "ctrl", "shift" }, "D", mouseHighlight)

hs.hotkey.bind({ "alt" }, "space", function()
  local state = hs.spotify.getPlaybackState()

  if state == hs.spotify.state_paused or state == hs.spotify.state_stopped then
    hs.spotify.play()
    hs.alert.show("Playback resumed")
    hs.spotify.displayCurrentTrack()
  elseif state == hs.spotify.state_playing then
    hs.spotify.pause()
    hs.alert.show("Playback paused")
  end
end)

hs.hotkey.bind({ "alt" }, "[", function()
  if hs.spotify.isPlaying() then
    hs.spotify.next()
  end
end)

hs.hotkey.bind({ "alt" }, "]", function()
  if hs.spotify.isPlaying() then
    hs.spotify.next()
  end
end)

hs.hotkey.bind({ "alt" }, "down", function()
  if hs.spotify.isPlaying() then
    hs.spotify.volumeDown()
  end
end)

hs.hotkey.bind({ "alt" }, "up", function()
  if hs.spotify.isPlaying() then
    hs.spotify.volumeUp()
  end
end)

-- Restore visible windows for the current workspace after reload
hs.timer.doAfter(0.5, function()
  showWorkspace(currentWorkspace)
end)

hs.application.enableSpotlightForNameSearches(true)

---Init a just-notify instance associated to category
---@param category string
local function initJn(category)
  local b, description = hs.dialog.textPrompt("[" .. category .. "] Insert the description", "Task to do it", "", "OK",
    "Cancel")
  if b == "Cancel" or not description then
    focusedWindow[currentWorkspace]:focus()
    return
  end

  local jnPath = "/Users/richard/.local/bin/jn"

  -- Show initial notification through Hammerspoon
  hs.alert.show("Starting timer for: " .. category)

  local cmd = string.format("nohup %s -t 1h -c %q -n break -d -l %q > /tmp/jn.log 2>&1 &", jnPath, category, description)

  local ok = hs.task.new("/bin/sleep", function(exitCode, _, _)
    -- Show completion notification through Hammerspoon only when sleep completes
    if exitCode == 0 then
      hs.notify.show(
        "Time has been finalized",
        description,
        "Task completed"
      )
    end
  end, { "3600" }):start()

  if not ok then
    hs.alert.show("Error starting sleep command")
  end

  -- Execute the command - detached execution returns immediately
  local _, status = hs.execute(cmd)
  if not status then
    hs.alert.show("Failed to start detached task")
  end

  focusedWindow[currentWorkspace]:focus()
end

hs.hotkey.bind({ "alt" }, "/", function()
  initJn("programming")
end)

hs.hotkey.bind({ "alt" }, ".", function()
  initJn("work")
end)

hs.hotkey.bind({ "alt" }, ",", function()
  local b, category = hs.dialog.textPrompt("Insert category", "Indicate topic", "work", "OK", "Cancel")

  if b == "Cancel" or not category then
    focusedWindow[currentWorkspace]:focus()
    return
  end

  initJn(category)
end)
