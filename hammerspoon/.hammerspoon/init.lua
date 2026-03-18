hs.loadSpoon("EmmyLua")

hs.alert.show("Hammerspoon loaded 🤘")

hs.hotkey.bind({ "alt", "shift" }, "r", function()
  hs.reload()
end)

hs.window.animationDuration = 0

local workspaceDataFile = os.getenv("HOME") .. "/.hammerspoon/workspaces.json"
local json              = hs.json

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
  if not encoded then hs.alert.show("⚠️ JSON encoding failed"); return end
  local file, err = io.open(workspaceDataFile, "w+")
  if not file then hs.alert.show("⚠️ File write failed: " .. (err or "unknown")); return end
  file:write(encoded)
  file:close()
end

-- ---------------------------------------------------------------------------
-- State
--
-- screenWorkspace[sid]  = workspace number currently shown on that screen
-- workspaceScreen[wsNum]= screenId currently showing that workspace (nil = hidden)
-- activeScreen          = the screen the user is actively working on
--                         maintained proactively; never computed on demand
-- currentWorkspace      = screenWorkspace[screenId(activeScreen)]
--                         always derived from activeScreen, never set independently
--
-- Invariants (enforced by verifyState):
--   screenWorkspace[sid] = n  ↔  workspaceScreen[n] = sid
--   activeScreen is a currently connected screen
--   currentWorkspace = screenWorkspace[screenId(activeScreen)]
-- ---------------------------------------------------------------------------

local screenWorkspace  = {}
local workspaceScreen  = {}
local lastFocused      = {}  -- wsNum -> last focused hs.window
local savedFrames      = {}  -- windowId -> {x,y,w,h} saved on hide, restored on show
local activeScreen     = nil -- always current; set by watcher + explicit calls
local currentWorkspace = 1

local OFFSCREEN_X = 30000
local OFFSCREEN_Y = 30000

-- ---------------------------------------------------------------------------
-- Core helpers
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

-- Authoritative setter for the active screen.
-- Always use this instead of writing activeScreen directly.
local function setActiveScreen(screen)
  if not screen then return end
  activeScreen = screen
  local ws = screenWorkspace[screenId(screen)]
  if ws then currentWorkspace = ws end
end

-- Verify bidirectional consistency of the maps and that activeScreen is live.
-- Repairs in-place and alerts on any violation so bugs surface immediately.
local function verifyState()
  for sid, ws in pairs(screenWorkspace) do
    if workspaceScreen[ws] ~= sid then
      hs.alert.show("⚠ ws: sw[" .. sid .. "]=" .. tostring(ws) ..
                    " ↔ ws[" .. tostring(ws) .. "]=" .. tostring(workspaceScreen[ws]))
      workspaceScreen[ws] = sid
    end
  end
  for ws, sid in pairs(workspaceScreen) do
    if screenWorkspace[sid] ~= ws then
      hs.alert.show("⚠ ws: ws[" .. tostring(ws) .. "]=" .. sid ..
                    " ↔ sw[" .. sid .. "]=" .. tostring(screenWorkspace[sid]))
      screenWorkspace[sid] = ws
    end
  end
  -- Ensure activeScreen points to a real, connected screen
  local live = activeScreen and getScreenById(screenId(activeScreen))
  if not live then
    setActiveScreen(hs.screen.primaryScreen())
  end
end

-- Atomically bind screen ↔ workspace, clearing any stale reverse entries first.
-- This is the only place screenWorkspace/workspaceScreen are written.
local function bindScreenWorkspace(screen, wsNum)
  local sid = screenId(screen)
  -- Clear old ws that this screen was showing
  local oldWs = screenWorkspace[sid]
  if oldWs and oldWs ~= wsNum then workspaceScreen[oldWs] = nil end
  -- Clear old screen that was showing this workspace
  local oldSid = workspaceScreen[wsNum]
  if oldSid and oldSid ~= sid then screenWorkspace[oldSid] = nil end
  -- Commit both directions atomically
  screenWorkspace[sid]  = wsNum
  workspaceScreen[wsNum] = sid
end

local function unbindWorkspace(wsNum)
  local sid = workspaceScreen[wsNum]
  if sid then
    screenWorkspace[sid]   = nil
    workspaceScreen[wsNum] = nil
  end
end

-- Lazily assign an untracked window to the workspace shown on its screen.
-- Skips windows parked offscreen (macOS reports them as primary, causing mis-assignment).
local function autoAssignWindow(win)
  if not win:isStandard() then return end  -- skip menus, tooltips, popovers
  local id = tostring(win:id())
  if workspaces[id] ~= nil then return end
  local f = win:frame()
  if f.x >= OFFSCREEN_X - 1000 or f.y >= OFFSCREEN_Y - 1000 then return end
  local s = win:screen()
  if not s then return end
  local ws = screenWorkspace[screenId(s)]
  if ws then workspaces[id] = ws end
end

-- ---------------------------------------------------------------------------
-- Window placement
-- ---------------------------------------------------------------------------

local function hideWorkspace(wsNum)
  for _, win in ipairs(hs.window.allWindows()) do
    autoAssignWindow(win)
    local id = tostring(win:id())
    if workspaces[id] == wsNum then
      local f = win:frame()
      if f.x < OFFSCREEN_X and f.y < OFFSCREEN_Y then
        savedFrames[id] = { x = f.x, y = f.y, w = f.w, h = f.h }
      end
      win:setFrame({ x = OFFSCREEN_X, y = OFFSCREEN_Y, w = f.w, h = f.h })
    end
  end
end

-- Tiles all windows belonging to wsNum that are currently on-screen.
-- Also updates savedFrames so hide/show preserves the tiled layout.
local function tileWorkspaceOnScreen(wsNum, screen)
  local max = screen:frame()
  local wins = {}
  for _, win in ipairs(hs.window.allWindows()) do
    local id = tostring(win:id())
    -- Include all standard windows assigned to this workspace
    if workspaces[id] == wsNum and win:isStandard() then
      table.insert(wins, win)
    end
  end
  local n = #wins
  if n == 0 then return end

  local frames = {}
  if n == 1 then
    frames[1] = { x = max.x, y = max.y, w = max.w, h = max.h }
  elseif n == 2 then
    local w = math.floor(max.w / 2)
    frames[1] = { x = max.x,     y = max.y, w = w,         h = max.h }
    frames[2] = { x = max.x + w, y = max.y, w = max.w - w, h = max.h }
  else
    local mainW = math.floor(max.w * 0.6)
    local sideW = max.w - mainW
    local sideH = math.floor(max.h / (n - 1))
    frames[1] = { x = max.x, y = max.y, w = mainW, h = max.h }
    for i = 2, n do
      local y = max.y + (i - 2) * sideH
      local h = (i == n) and (max.h - (i - 2) * sideH) or sideH
      frames[i] = { x = max.x + mainW, y = y, w = sideW, h = h }
    end
  end

  for i, win in ipairs(wins) do
    win:setFrame(frames[i])
    savedFrames[tostring(win:id())] = frames[i]
  end
end

-- Returns true if frame center is within screen bounds.
local function frameOnScreen(f, screen)
  local sf = screen:frame()
  local cx = f.x + f.w / 2
  local cy = f.y + f.h / 2
  return cx >= sf.x and cx < sf.x + sf.w and cy >= sf.y and cy < sf.y + sf.h
end

local function showWorkspaceOnScreen(wsNum, screen)
  local max    = screen:frame()
  local needsTile = false

  for _, win in ipairs(hs.window.allWindows()) do
    autoAssignWindow(win)
    local id = tostring(win:id())
    if workspaces[id] == wsNum then
      local f   = win:frame()
      local parked   = f.x >= OFFSCREEN_X or f.y >= OFFSCREEN_Y
      local wrongScr = not parked and not frameOnScreen(f, screen)

      if parked or wrongScr then
        local saved = savedFrames[id]
        if saved and frameOnScreen(saved, screen) then
          -- Saved position is on this screen — restore it
          win:setFrame(saved)
        else
          -- No saved frame or saved frame is for a different screen — tile
          win:setFrame({ x = max.x, y = max.y, w = max.w, h = max.h })
          needsTile = true
        end
      end
    end
  end

  -- Defer tiling so macOS processes the setFrame calls above first
  if needsTile then
    hs.timer.doAfter(0, function() tileWorkspaceOnScreen(wsNum, screen) end)
  end
end

-- Focus the best window for wsNum.
-- setActiveScreen(screen) is called first — this is the single place that
-- commits the new active screen, covering both the window-focus and mouse-warp paths.
-- We do not check win:screen() because macOS doesn't update it synchronously
-- after setFrame; we trust the workspace assignment instead.
local function focusWorkspaceOnScreen(wsNum, screen)
  setActiveScreen(screen)
  local fw = lastFocused[wsNum]
  if fw and fw:isVisible() and workspaces[tostring(fw:id())] == wsNum then
    fw:focus(); return
  end
  for _, win in ipairs(hs.window.allWindows()) do
    local id = tostring(win:id())
    if workspaces[id] == wsNum and win:isVisible() then
      win:focus(); return
    end
  end
  -- Empty workspace: warp mouse so the OS treats this screen as active.
  -- activeScreen is already updated above so our state is correct even
  -- though no window focus event will fire.
  local f = screen:frame()
  hs.mouse.absolutePosition({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
end

-- ---------------------------------------------------------------------------
-- Bootstrap: assign sequential workspaces to all screens on load.
-- Primary screen gets currentWorkspace; others get the next free slots.
-- ---------------------------------------------------------------------------

local function bootstrapScreens()
  screenWorkspace = {}
  workspaceScreen = {}
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
  setActiveScreen(primary)
end

-- ---------------------------------------------------------------------------
-- Core switcher (state machine transition)
--
-- Pre:  activeScreen is the screen the user is on; maps are consistent.
-- Post: workspace n is on activeScreen; activeScreen and focus are unchanged;
--       maps remain consistent.
--
-- Cases:
--   pivWs == n          → already there, just focus
--   n visible elsewhere → swap: n→pivot, pivWs→target
--   n hidden            → evict pivWs, show n on pivot
-- ---------------------------------------------------------------------------

local function showWorkspace(n)
  if n == 0 then return end
  verifyState()

  local pivot  = activeScreen
  local pivSid = screenId(pivot)
  local pivWs  = screenWorkspace[pivSid]

  -- Record the focused window for the workspace currently on the pivot screen.
  lastFocused[pivWs or currentWorkspace] = hs.window.focusedWindow()

  -- Already showing n on the active screen.
  if pivWs == n then
    currentWorkspace = n
    focusWorkspaceOnScreen(n, pivot)
    return
  end

  local targetSid = workspaceScreen[n]

  if targetSid and targetSid ~= pivSid then
    -- n is visible on another screen: swap.
    -- bindScreenWorkspace is atomic — it clears stale reverse entries, so two
    -- calls in sequence leave the maps fully consistent with no extra cleanup.
    local targetScreen = getScreenById(targetSid)
    if targetScreen then
      bindScreenWorkspace(pivot, n)
      if pivWs then
        bindScreenWorkspace(targetScreen, pivWs)
        showWorkspaceOnScreen(pivWs, targetScreen)
      end
      showWorkspaceOnScreen(n, pivot)
    end
  else
    -- n is hidden: evict pivot's current workspace, place n there.
    if pivWs and pivWs ~= n then
      hideWorkspace(pivWs)
      unbindWorkspace(pivWs)
    end
    bindScreenWorkspace(pivot, n)
    showWorkspaceOnScreen(n, pivot)
  end

  currentWorkspace = n
  hs.alert.show("Workspace " .. n)
  focusWorkspaceOnScreen(n, pivot)
end

-- ---------------------------------------------------------------------------
-- Assign window to workspace
-- ---------------------------------------------------------------------------

local function assignWindowToWorkspace(n)
  local win = hs.window.focusedWindow()
  if not win then return end
  local id   = tostring(win:id())
  local oldWs = workspaces[id]
  workspaces[id] = n
  hs.alert.show("Window → Workspace " .. n)
  saveWorkspaceData(workspaces)
  -- Re-tile the source workspace now that this window has left it
  if oldWs and oldWs ~= n and workspaceScreen[oldWs] then
    local screen = getScreenById(workspaceScreen[oldWs])
    if screen then tileWorkspaceOnScreen(oldWs, screen) end
  end
end

-- ---------------------------------------------------------------------------
-- Screen change: reconcile without full reset.
-- Preserves live screen↔workspace bindings, hides disappeared ones,
-- assigns free slots to new screens, re-places all windows.
-- ---------------------------------------------------------------------------

local function reconcileScreens()
  local allScreens  = hs.screen.allScreens()
  local presentSids = {}
  for _, s in ipairs(allScreens --[[@as table]]) do
    presentSids[screenId(s)] = s
  end

  -- Hide workspaces whose screen disappeared (snapshot before mutating).
  local toHide = {}
  for wsNum, sid in pairs(workspaceScreen) do
    if not presentSids[sid] then table.insert(toHide, wsNum) end
  end
  for _, wsNum in ipairs(toHide) do
    hideWorkspace(wsNum)
    unbindWorkspace(wsNum)
  end

  -- Assign free workspaces to newly appeared screens.
  for sid, screen in pairs(presentSids) do
    if not screenWorkspace[sid] then
      for wsIdx = 1, maxWorkspaces do
        if workspaceScreen[wsIdx] == nil then
          bindScreenWorkspace(screen, wsIdx); break
        end
      end
    end
  end

  -- Ensure currentWorkspace has a screen; reclaim primary if not.
  if not workspaceScreen[currentWorkspace] then
    local primary = hs.screen.primaryScreen()
    local oldWs   = screenWorkspace[screenId(primary)]
    if oldWs then hideWorkspace(oldWs); unbindWorkspace(oldWs) end
    bindScreenWorkspace(primary, currentWorkspace)
  end

  -- Re-place all visible workspaces on their screens.
  for _, screen in ipairs(allScreens --[[@as table]]) do
    local ws = screenWorkspace[screenId(screen)]
    if ws then showWorkspaceOnScreen(ws, screen) end
  end

  verifyState()
end

-- ---------------------------------------------------------------------------
-- Focus watcher
--
-- Keeps activeScreen in sync on every window focus change.
-- hs.window.filter.windowFocused fires for any window, including windows of
-- the same app on a different screen — hs.application.watcher.activated would
-- miss those (it only fires when the active *app* changes).
-- ---------------------------------------------------------------------------

hs.window.filter.new()
  :subscribe(hs.window.filter.windowFocused, function(win)
    if win then
      setActiveScreen(win:screen())
      local wsNum = workspaces[tostring(win:id())]
      if wsNum then lastFocused[wsNum] = win end
    end
  end)

-- Focus-follows-mouse via eventtap (requires Input Monitoring permission).
-- Debounces 50ms after the last mouse movement, then focuses the topmost
-- standard on-screen window under the cursor.
local ffmLastWinId = nil
local ffmDebounce  = nil
local ffmEventtap  = nil

local function ffmFocus()
  local pos = hs.mouse.absolutePosition()
  if pos.x >= OFFSCREEN_X or pos.y >= OFFSCREEN_Y then return end
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isStandard() and not win:isMinimized() then
      local f = win:frame()
      if f.x < OFFSCREEN_X and f.y < OFFSCREEN_Y and
         pos.x >= f.x and pos.x < f.x + f.w and
         pos.y >= f.y and pos.y < f.y + f.h then
        local wid = tostring(win:id())
        if wid ~= ffmLastWinId then
          ffmLastWinId = wid
          win:focus()
          local s = win:screen()
          if s and s ~= activeScreen then setActiveScreen(s) end
        end
        return
      end
    end
  end
end

ffmEventtap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
  if ffmDebounce then ffmDebounce:stop() end
  ffmDebounce = hs.timer.doAfter(0.05, function()
    local ok, err = pcall(ffmFocus)
    if not ok then hs.alert.show("FFM error: " .. tostring(err)) end
  end)
  return false
end)
ffmEventtap:start()

-- Watchdog: macOS can silently disable eventtaps on sleep/wake.
local ffmWatchdog = hs.timer.new(5, function()
  if not ffmEventtap:isEnabled() then ffmEventtap:start() end
end)
ffmWatchdog:start()

hs.window.filter.new()
  :subscribe(hs.window.filter.windowCreated, function(win)
    if not win or not win:isStandard() or not win:isVisible() then return end
    local pos = win:topLeft()
    if pos.x >= OFFSCREEN_X or pos.y >= OFFSCREEN_Y then return end
    autoAssignWindow(win)
    local wsNum = workspaces[tostring(win:id())]
    if wsNum and workspaceScreen[wsNum] then
      local screen = getScreenById(workspaceScreen[wsNum])
      if screen then
        hs.timer.doAfter(0, function() tileWorkspaceOnScreen(wsNum, screen) end)
      end
    end
  end)

hs.window.filter.new()
  :subscribe(hs.window.filter.windowDestroyed, function(win)
    if not win then return end
    local wid = tostring(win:id())
    local wsNum = workspaces[wid]
    savedFrames[wid] = nil
    if wsNum then
      workspaces[wid] = nil
      saveWorkspaceData(workspaces)
      if workspaceScreen[wsNum] then
        local screen = getScreenById(workspaceScreen[wsNum])
        if screen then
          hs.timer.doAfter(0, function() tileWorkspaceOnScreen(wsNum, screen) end)
        end
      end
    end
    for ws, lastWin in pairs(lastFocused) do
      if lastWin and lastWin:id() == win:id() then
        lastFocused[ws] = nil; break
      end
    end
  end)

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

-- Window movement between physical screens.
-- Reassigns only the moved window to the workspace shown on the destination
-- screen, leaving all other windows and workspace bindings untouched.
local function moveWindowToScreen(win, destScreen, moveFn)
  if not win then return end
  local id    = tostring(win:id())
  local srcWs = workspaces[id]
  moveFn(win)
  if not destScreen then return end

  local destWs = screenWorkspace[screenId(destScreen)]
  if not destWs then return end

  workspaces[id] = destWs
  setActiveScreen(destScreen)
  saveWorkspaceData(workspaces)
  -- Re-tile the source workspace now that this window has left it
  if srcWs and srcWs ~= destWs and workspaceScreen[srcWs] then
    local srcScreen = getScreenById(workspaceScreen[srcWs])
    if srcScreen then tileWorkspaceOnScreen(srcWs, srcScreen) end
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

-- Bootstrap on load
hs.timer.doAfter(0.5, function()
  bootstrapScreens()
  for _, screen in ipairs(hs.screen.allScreens() --[[@as table]]) do
    local ws = screenWorkspace[screenId(screen)]
    if ws then showWorkspaceOnScreen(ws, screen) end
  end
  verifyState()
end)

hs.application.enableSpotlightForNameSearches(true)
hs.loadSpoon('ControlEscape'):start()
