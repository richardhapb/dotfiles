
hs.alert.show("Hammerspoon loaded 🤘")

hs.hotkey.bind({"alt", "shift"}, "r", function()
  hs.reload()
end)

local currentWorkspace = 1  -- must be initialized explicitly
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


-- Save current workspace mapping to file
local function saveWorkspaceData(data)
  local encoded = hs.json.encode(data)
  if not encoded then
    hs.alert.show("⚠️ JSON encoding failed")
    print("⚠️ Failed to encode workspace data")
    print(hs.inspect(data))  -- pretty-print for inspection
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

-- Move all visible windows to the center of the screen
hs.hotkey.bind({"alt", "cmd"}, "r", function()
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

-- Hide the window
local function moveOffscreen(win)
  local f = win:frame()
  f.x = -5000
  win:setFrame(f)
end



-- Move the windows to the current workspace
local function showWorkspace(n)
  currentWorkspace = n
  hs.alert.show("Workspace " .. n)

  for _, win in ipairs(hs.window.visibleWindows()) do
    local id = tostring(win:id())
    local ws = workspaces[id]
    if ws == n then
      win:focus()
      win:application():activate()
    else
      moveOffscreen(win)
    end
  end

  -- Show all windows in the workspace
  for _, win in ipairs(hs.window.allWindows()) do
    if workspaces[tostring(win:id())] == n then
      win:application():activate()
      win:focus()
      win:centerOnScreen()
    end
  end
end

-- Move the window to workspace n
local function assignWindowToWorkspace(n)
  local win = hs.window.focusedWindow()
  if win then
    workspaces[tostring(win:id())] = n
    hs.alert.show("Window assigned to Workspace " .. n)
    saveWorkspaceData(workspaces)
    moveOffscreen(win)
  end
end

-- Change the workspace using Alt + Number
for i = 1, maxWorkspaces do
  hs.hotkey.bind({"alt"}, tostring(i), function()
    showWorkspace(i)
  end)

  -- Send the window to the workspace using Alt + Shift + Number
  hs.hotkey.bind({"alt", "shift"}, tostring(i), function()
    assignWindowToWorkspace(i)
  end)
end

hs.hotkey.bind({"alt"}, "h", function()
  hs.window.focusedWindow():moveOneScreenWest()
end)

hs.hotkey.bind({"alt"}, "l", function()
  hs.window.focusedWindow():moveOneScreenEast()
end)

hs.hotkey.bind({"alt"}, "k", function()
  hs.window.focusedWindow():moveOneScreenNorth()
end)

hs.hotkey.bind({"alt"}, "j", function()
  hs.window.focusedWindow():moveOneScreenSouth()
end)

--- Send the window in a specified direction
---@param position string
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
hs.hotkey.bind({"alt", "shift"}, "h", function() resize_window("l") end)
hs.hotkey.bind({"alt", "shift"}, "l", function() resize_window("r") end)
hs.hotkey.bind({"alt", "shift"}, "k", function() resize_window("t") end)
hs.hotkey.bind({"alt", "shift"}, "j", function() resize_window("b") end)
hs.hotkey.bind({"alt"}, "f", function() resize_window("f") end)

-- Restore visible windows for the current workspace after reload
hs.timer.doAfter(0.5, function()
  showWorkspace(currentWorkspace)
end)

