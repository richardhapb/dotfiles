hs.loadSpoon("EmmyLua")

hs.alert.show("Hammerspoon loaded 🤘")

hs.hotkey.bind({ "alt", "shift" }, "r", function()
  hs.reload()
end)

hs.window.animationDuration = 0

local workspaceDataFile     = os.getenv("HOME") .. "/.hammerspoon/workspaces.json"
local json                  = hs.json

local function loadWorkspaceData()
  local file = io.open(workspaceDataFile, "r")
  if not file then return {} end
  local content = file:read("*a")
  file:close()
  return json.decode(content) or {}
end

local workspaces    = loadWorkspaceData() -- windowId -> workspace number
local maxWorkspaces = 9

local function saveWorkspaceData(data)
  local encoded = hs.json.encode(data)
  if not encoded then
    hs.alert.show("⚠️ JSON encoding failed"); return
  end
  local file, err = io.open(workspaceDataFile, "w+")
  if not file then
    hs.alert.show("⚠️ File write failed: " .. (err or "unknown")); return
  end
  file:write(encoded)
  file:close()
end

-- ---------------------------------------------------------------------------
-- State
--
-- screenWorkspace[screenId] = workspace number currently displayed on that screen
-- workspaceScreen[wsNum]    = screenId currently displaying that workspace (nil if hidden)
-- ---------------------------------------------------------------------------

local screenWorkspace  = {}
local workspaceScreen  = {}
local lastFocused      = {}  -- workspace number -> last focused hs.window
local currentWorkspace = 1
local lastPivotScreen  = nil -- screen that was active on last showWorkspace call

local OFFSCREEN_X      = 30000
local OFFSCREEN_Y      = 30000

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function screenId(screen)
  return tostring(screen:id())
end

local function getScreenById(sid)
  for _, s in ipairs(hs.screen.allScreens() --[[@as table]]) do
    if screenId(s) == sid then return s end
  end
  return nil
end

local function focusedScreen()
  local fw = hs.window.focusedWindow()
  if fw then
    -- Only trust focusedWindow's screen when the current workspace has windows.
    -- When the current workspace is empty, macOS OS-focus drifts to a window on
    -- another screen (nothing to focus here); fall through to lastPivotScreen so
    -- the next switch stays on the screen the user was on.
    for _, win in ipairs(hs.window.allWindows() --[[@as table]]) do
      if workspaces[tostring(win:id())] == currentWorkspace then
        return fw:screen()
      end
    end
  end
  if lastPivotScreen then return lastPivotScreen end
  if fw then return fw:screen() end
  return hs.screen.primaryScreen()
end

local function bindScreenWorkspace(screen, wsNum)
  local sid = screenId(screen)
  screenWorkspace[sid] = wsNum
  workspaceScreen[wsNum] = sid
end

local function unbindWorkspace(wsNum)
  local sid = workspaceScreen[wsNum]
  if sid then
    screenWorkspace[sid] = nil
    workspaceScreen[wsNum] = nil
  end
end

-- Lazily assign an unassigned window to the workspace currently showing on its screen.
-- This ensures windows opened without explicit assignment are tracked correctly.
-- Skips windows already parked offscreen — macOS reports those as being on the
-- primary screen, which would cause them to be mis-assigned to workspace 1.
local function autoAssignWindow(win)
  local id = tostring(win:id())
  if workspaces[id] ~= nil then return end
  local f = win:frame()
  if f.x >= OFFSCREEN_X - 1000 or f.y >= OFFSCREEN_Y - 1000 then return end
  local s = win:screen()
  if not s then return end
  local ws = screenWorkspace[screenId(s)]
  if ws then
    workspaces[id] = ws
  end
end

-- Move all windows of wsNum offscreen
local function hideWorkspace(wsNum)
  for _, win in ipairs(hs.window.allWindows()) do
    autoAssignWindow(win)
    local id = tostring(win:id())
    if workspaces[id] == wsNum then
      local f = win:frame()
      f.x = OFFSCREEN_X
      f.y = OFFSCREEN_Y
      win:setFrame(f)
    end
  end
end

-- Place all windows of wsNum filling the given screen
local function showWorkspaceOnScreen(wsNum, screen)
  local max = screen:frame()
  for _, win in ipairs(hs.window.allWindows()) do
    autoAssignWindow(win)
    local id = tostring(win:id())
    if workspaces[id] == wsNum then
      local f = win:frame()
      f.x = max.x
      f.y = max.y
      f.w = max.w
      f.h = max.h
      win:setFrame(f)
    end
  end
end

-- Focus the last known window for wsNum, or any window of wsNum.
-- We trust the workspace assignment rather than win:screen() because macOS
-- doesn't update win:screen() synchronously after setFrame — checking it
-- here would cause the fallback to miss the window and never call focus(),
-- leaving the previous window raised on top of the newly placed one.
-- If the workspace has no windows, warp the mouse to that screen so macOS
-- keeps it as the active screen — preventing focusedScreen() from drifting.
local function focusWorkspaceOnScreen(wsNum, screen)
  local fw = lastFocused[wsNum]
  if fw and fw:isVisible() and workspaces[tostring(fw:id())] == wsNum then
    fw:focus()
    return
  end
  for _, win in ipairs(hs.window.allWindows()) do
    local id = tostring(win:id())
    if workspaces[id] == wsNum and win:isVisible() then
      win:focus()
      return
    end
  end
  -- No windows: warp mouse so macOS treats this screen as active.
  local f = screen:frame()
  hs.mouse.absolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
end

-- Assign sequential workspaces to all screens. Called on load and screen change.
-- Primary screen keeps currentWorkspace; others get the next free workspaces.
local function bootstrapScreens()
  screenWorkspace = {}
  workspaceScreen = {}
  lastPivotScreen = nil
  local primary = hs.screen.primaryScreen()
  bindScreenWorkspace(primary, currentWorkspace)
  local wsIdx = 1
  for _, screen in ipairs(hs.screen.allScreens() --[[@as table]]) do
    if screen ~= primary then
      while wsIdx == currentWorkspace or workspaceScreen[wsIdx] ~= nil do
        wsIdx = wsIdx + 1
        if wsIdx > maxWorkspaces then break end
      end
      if wsIdx <= maxWorkspaces then
        bindScreenWorkspace(screen, wsIdx)
        wsIdx = wsIdx + 1
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Core switcher
--
-- Invariant: workspace n goes to the focused screen.
-- If n is already visible on another screen, swap that screen with the focused screen.
-- If n is hidden, evict the focused screen's current workspace and show n there.
-- Focus stays on the pivot (focused) screen after the switch.
-- ---------------------------------------------------------------------------

local function showWorkspace(n)
  if n == 0 then return end

  local pivot   = focusedScreen()
  local pivSid  = screenId(pivot)
  local pivWs   = screenWorkspace[pivSid] -- workspace currently on pivot (may be nil)

  -- Save the focused window under the workspace that is actually on the pivot screen.
  -- Using currentWorkspace here would be wrong when the focused screen was assigned
  -- its workspace by bootstrap rather than by a prior showWorkspace call.
  lastFocused[pivWs or currentWorkspace] = hs.window.focusedWindow()

  -- Already showing on the focused screen — just ensure focus and update state.
  if pivWs == n then
    currentWorkspace = n
    lastPivotScreen  = pivot
    focusWorkspaceOnScreen(n, pivot)
    return
  end

  local targetSid = workspaceScreen[n] -- screen currently showing ws n (nil if hidden)

  if targetSid and targetSid ~= pivSid then
    -- ws n is visible on a different screen: swap the two workspaces.
    local targetScreen = getScreenById(targetSid)
    if targetScreen then
      -- Bind pivot to n first (overwrites workspaceScreen[n] = pivSid)
      bindScreenWorkspace(pivot, n)
      if pivWs then
        -- Send pivWs to the target screen
        bindScreenWorkspace(targetScreen, pivWs)
        showWorkspaceOnScreen(pivWs, targetScreen)
      else
        -- Pivot had no workspace: clear the stale screenWorkspace entry on target
        screenWorkspace[targetSid] = nil
      end
      showWorkspaceOnScreen(n, pivot)
    end
  else
    -- ws n is hidden (or somehow already on pivot): evict and show
    if pivWs and pivWs ~= n then
      hideWorkspace(pivWs)
      unbindWorkspace(pivWs)
    end
    bindScreenWorkspace(pivot, n)
    showWorkspaceOnScreen(n, pivot)
  end

  currentWorkspace = n
  lastPivotScreen  = pivot
  hs.alert.show("Workspace " .. n)

  focusWorkspaceOnScreen(n, pivot)
end

-- ---------------------------------------------------------------------------
-- Assign window to workspace
-- ---------------------------------------------------------------------------

local function assignWindowToWorkspace(n)
  local win = hs.window.focusedWindow()
  if not win then return end
  local id = tostring(win:id())
  workspaces[id] = n
  hs.alert.show("Window assigned to Workspace " .. n)
  saveWorkspaceData(workspaces)
end

-- ---------------------------------------------------------------------------
-- Screen change: reconcile existing bindings rather than full reset.
--
-- Preserves screen->workspace assignments for screens still connected.
-- Hides (parks offscreen) workspaces whose screen disappeared.
-- Assigns a free workspace to any newly appeared screen.
-- Ensures currentWorkspace always has a screen.
-- ---------------------------------------------------------------------------

local function reconcileScreens()
  local allScreens  = hs.screen.allScreens()
  local presentSids = {}
  for _, s in ipairs(allScreens --[[@as table]]) do
    presentSids[screenId(s)] = s
  end

  -- Collect workspaces whose screen has gone away (snapshot before mutating)
  local toHide = {}
  for wsNum, sid in pairs(workspaceScreen) do
    if not presentSids[sid] then
      table.insert(toHide, wsNum)
    end
  end
  for _, wsNum in ipairs(toHide) do
    hideWorkspace(wsNum)
    unbindWorkspace(wsNum)
  end

  -- Assign a free workspace to each screen that currently has none
  for sid, screen in pairs(presentSids) do
    if not screenWorkspace[sid] then
      for wsIdx = 1, maxWorkspaces do
        if workspaceScreen[wsIdx] == nil then
          bindScreenWorkspace(screen, wsIdx)
          break
        end
      end
    end
  end

  -- Ensure currentWorkspace is still on a screen; reclaim primary if not
  if not workspaceScreen[currentWorkspace] then
    local primary = hs.screen.primaryScreen()
    local primSid = screenId(primary)
    local oldWs   = screenWorkspace[primSid]
    if oldWs then
      hideWorkspace(oldWs)
      unbindWorkspace(oldWs)
    end
    bindScreenWorkspace(primary, currentWorkspace)
  end

  lastPivotScreen = nil

  -- Re-place windows on all screens
  for _, screen in ipairs(allScreens --[[@as table]]) do
    local ws = screenWorkspace[screenId(screen)]
    if ws then showWorkspaceOnScreen(ws, screen) end
  end
end

hs.screen.watcher.new(function()
  reconcileScreens()
end):start()

-- ---------------------------------------------------------------------------
-- Hotkeys
-- ---------------------------------------------------------------------------

for i = 1, maxWorkspaces do
  hs.hotkey.bind({ "alt" }, tostring(i), function()
    showWorkspace(i)
  end)
  hs.hotkey.bind({ "alt", "shift" }, tostring(i), function()
    assignWindowToWorkspace(i)
  end)
end

hs.hotkey.bind({ "alt", "shift" }, tostring(0), function()
  assignWindowToWorkspace(0)
end)

-- Window movement between physical screens
-- Reassign the window to the workspace of its destination screen so the
-- workspace state stays consistent with where the window actually landed.
local function moveWindowToScreen(win, destScreen, moveFn)
  if not win then return end
  moveFn(win)
  if destScreen then
    local ws = screenWorkspace[screenId(destScreen)]
    if ws then
      workspaces[tostring(win:id())] = ws
      saveWorkspaceData(workspaces)
    end
  end
end

hs.hotkey.bind({ "alt" }, "h", function()
  local w = hs.window.focusedWindow()
  moveWindowToScreen(w, w and w:screen():toWest(), function(win) win:moveOneScreenWest() end)
end)
hs.hotkey.bind({ "alt" }, "l", function()
  local w = hs.window.focusedWindow()
  moveWindowToScreen(w, w and w:screen():toEast(), function(win) win:moveOneScreenEast() end)
end)
hs.hotkey.bind({ "alt" }, "k", function()
  local w = hs.window.focusedWindow()
  moveWindowToScreen(w, w and w:screen():toNorth(), function(win) win:moveOneScreenNorth() end)
end)
hs.hotkey.bind({ "alt" }, "j", function()
  local w = hs.window.focusedWindow()
  moveWindowToScreen(w, w and w:screen():toSouth(), function(win) win:moveOneScreenSouth() end)
end)

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

  local prev_win = hs.window.focusedWindow()
  if task then
    task:start()
    local attempt = 0
    local draw_win = nil
    while true do
      hs.execute("sleep 0.2")
      local win = hs.window.focusedWindow()
      if win and win:title():find("JUST%sDRAW") then
        draw_win = win
        break
      end
      if attempt >= 5 then
        hs.notify.show("Error", "Cannot find drawing window", "")
        task:terminate()
        return
      end
      attempt = attempt + 1
    end
    assignWindowToWorkspace(9)
    if prev_win then prev_win:focus() end
    showWorkspace(9)
    if draw_win then draw_win:focus() end
    resize_window("f")
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
  if not ok or not playlists then hs.alert.show("Could not fetch playlists") return end

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
    if lastFocused[currentWorkspace] then lastFocused[currentWorkspace]:focus() end
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

  if lastFocused[currentWorkspace] then lastFocused[currentWorkspace]:focus() end
end

hs.hotkey.bind({ "alt" }, "/", function() initJn("programming") end)
hs.hotkey.bind({ "alt" }, ".", function() initJn("work") end)
hs.hotkey.bind({ "alt" }, ",", function()
  local b, category = hs.dialog.textPrompt("Insert category", "Indicate topic", "work", "OK", "Cancel")
  if b == "Cancel" or not category then
    if lastFocused[currentWorkspace] then lastFocused[currentWorkspace]:focus() end
    return
  end
  initJn(category)
end)

-- Neospeller
hs.hotkey.bind({ "alt" }, "g", function()
  hs.execute("~/.local/bin/ns-clip", true)
end)

-- Bootstrap on load
hs.timer.doAfter(0.5, function()
  bootstrapScreens()
  for _, screen in ipairs(hs.screen.allScreens() --[[@as table]]) do
    local sid = screenId(screen)
    local ws  = screenWorkspace[sid]
    if ws then showWorkspaceOnScreen(ws, screen) end
  end
end)

hs.application.enableSpotlightForNameSearches(true)
hs.loadSpoon('ControlEscape'):start()
