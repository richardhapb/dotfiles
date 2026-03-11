hs.loadSpoon("EmmyLua")

hs.alert.show("Hammerspoon loaded 🤘")

hs.hotkey.bind({ "alt", "shift" }, "r", function()
  hs.reload()
end)

hs.window.animationDuration = 0

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

local workspaces      = loadWorkspaceData() -- windowId -> workspace number
local maxWorkspaces   = 9
local windowsPosition = {}                  -- windowId -> last known frame (on-screen)
local focusedWindow   = {}                  -- workspace number -> last focused window

-- Metatables same as before
windowsPosition       = setmetatable(windowsPosition, {
  __index = function(t, k)
    local v = rawget(t, k)
    if v ~= nil then return v end
    for _, win in ipairs(hs.window.allWindows()) do
      if tostring(win:id()) == k then
        local frame = win:frame()
        -- If window is already offscreen, use its screen full frame instead
        if frame.x >= 20000 or frame.y >= 20000 then
          local screen = win:screen() or hs.screen.primaryScreen()
          frame = screen:frame()
        end
        rawset(t, k, frame)
        return frame
      end
    end
    print("Window not found for id:", k)
    return nil
  end
})

focusedWindow         = setmetatable(focusedWindow, {
  __index = function(t, k)
    local v = rawget(t, k)
    if v then return v end
    return hs.window.focusedWindow()
  end
})

local function saveWorkspaceData(data)
  local encoded = hs.json.encode(data)
  if not encoded then
    hs.alert.show("⚠️ JSON encoding failed")
    return
  end
  local file, err = io.open(workspaceDataFile, "w+")
  if not file then
    hs.alert.show("⚠️ File write failed: " .. (err or "unknown"))
    return
  end
  file:write(encoded)
  file:close()
end

-- Screen slot management

-- Returns screens sorted clockwise starting from primary.
-- Clockwise angle is computed from the centroid of all screens.
local function getScreenSlots()
  local primary = hs.screen.primaryScreen()
  local all     = hs.screen.allScreens()

  if #all == 1 then return { primary } end

  -- Compute centroid of all screen centers
  local cx, cy = 0, 0
  for _, s in ipairs(all --[[@as table]]) do
    local f = s:frame()
    cx = cx + f.x + f.w / 2
    cy = cy + f.y + f.h / 2
  end
  cx = cx / #all
  cy = cy / #all

  -- Angle of each screen center relative to centroid
  -- atan2 gives CCW from east; we want CW from north so we negate and offset
  local function angle(s)
    local f = s:frame()
    local dx = (f.x + f.w / 2) - cx
    local dy = (f.y + f.h / 2) - cy
    -- CW from north: atan2(dx, -dy), normalised to [0, 2\pi)
    -- math.atan(y,x) is Lua 5.3+ two-arg form; alias cast silences EmmyLua 1-arg stub
    local atan2 = math.atan --[[@as fun(y:number,x:number):number]]
    local a = atan2(dx, -dy)
    -- transform to positive preserving the angle
    if a < 0 then a = a + 2 * math.pi end
    return a
  end

  -- Primary always goes first (slot 0); rest sorted by CW angle relative to primary
  local primaryAngle = angle(primary)
  local others = {}
  for _, s in ipairs(all --[[@as table]]) do
    if s ~= primary then
      local a = angle(s) - primaryAngle
      if a < 0 then a = a + 2 * math.pi end
      table.insert(others, { screen = s, a = a })
    end
  end
  table.sort(others, function(a, b) return a.a < b.a end)

  local slots = { primary }
  for _, o in ipairs(others) do
    table.insert(slots, o.screen)
  end
  return slots
end

-- slotWorkspace[i] = workspace number currently shown on slot i (1-indexed)
-- nil means the slot is empty (no workspace assigned yet)
local slotWorkspace = {} -- slot index -> ws number
local workspaceSlot = {} -- ws number  -> slot index

-- initSlots does NOT pre-fill secondary slots.
-- Slots are filled lazily as workspaces are shown via showWorkspace.
-- On screen count change we only reset if we have more screens than tracked slots,
-- preserving slot 1 (primary) assignment.
local function initSlots()
  slotWorkspace = {}
  workspaceSlot = {}
end

initSlots()

-- Window positioning helpers

local OFFSCREEN_X = 30000
local OFFSCREEN_Y = 30000

-- Move all windows of a workspace offscreen.
-- Only saves position if the window is currently on a real screen (not already hidden).
local function hideWorkspace(wsNum)
  for _, win in ipairs(hs.window.allWindows()) do
    local id = tostring(win:id())
    if workspaces[id] == wsNum then
      local f = win:frame()
      -- A window is on-screen when its coords are well below the offscreen sentinel.
      -- Using 20000 as threshold leaves plenty of headroom vs real screen coords.
      if f.x < 20000 and f.y < 20000 then
        windowsPosition[id] = win:frame()
      end
      f.x = OFFSCREEN_X
      f.y = OFFSCREEN_Y
      win:setFrame(f)
    end
  end
end

-- Place all windows of wsNum filling the given screen.
-- Does NOT save position here -- windowsPosition is the canonical "last real frame"
-- and must only be written when a window is known to be on a real screen (hideWorkspace above).
-- app:activate() is intentionally omitted; focus is managed by showWorkspace after placement.
local function placeWorkspaceOnScreen(wsNum, screen)
  local max = screen:frame()
  for _, win in ipairs(hs.window.allWindows()) do
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

-- Core workspace switcher

local currentWorkspace = 1

-- Ensure every screen slot has a workspace assigned, using workspaces not
-- currently visible. Skips slot 1 (primary) — that is always managed explicitly.
-- Also prunes stale slots if screen count shrank.
local function ensureSlotsFilled(numSlots)
  -- Remove slots that no longer correspond to a screen
  for slotIdx, wsNum in pairs(slotWorkspace) do
    if slotIdx > numSlots then
      hideWorkspace(wsNum)
      workspaceSlot[wsNum] = nil
      slotWorkspace[slotIdx] = nil
    end
  end

  -- Fill empty slots 2..numSlots
  local nextWs = 1
  for slotIdx = 2, numSlots do
    if not slotWorkspace[slotIdx] then
      -- Advance nextWs to one that is not already assigned to any slot
      while nextWs <= maxWorkspaces and workspaceSlot[nextWs] ~= nil do
        nextWs = nextWs + 1
      end
      if nextWs <= maxWorkspaces then
        slotWorkspace[slotIdx] = nextWs
        workspaceSlot[nextWs] = slotIdx
        nextWs = nextWs + 1
      end
    end
  end
end

local function showWorkspace(n)
  if n == 0 then return end -- 0 is frozen/pinned
  if n == currentWorkspace then return end

  local slots = getScreenSlots()
  local numSlots = #slots

  -- Save focused window of current workspace before switching
  focusedWindow[currentWorkspace] = hs.window.focusedWindow()

  local targetSlot = workspaceSlot[n] -- nil if n is not currently visible

  if targetSlot then
    -- n is already on a screen: rotate the slot assignments so n lands on slot 1.
    -- Compute shortest rotation distance.
    -- stepsLeft: shift assignments left by k (slot k+1 -> slot 1, etc.)
    -- This is equivalent to rotating workspaces CCW (toward primary).
    local stepsLeft  = (targetSlot - 1) % numSlots
    local stepsRight = numSlots - stepsLeft
    local shift      = (stepsLeft <= stepsRight) and stepsLeft or (numSlots - stepsRight)

    -- Rotate: new slot i gets the workspace that was at slot ((i-1+shift) % numSlots)+1
    -- Lua % is always non-negative so this works for both directions.
    local newSlotWs  = {}
    local newWsSlot  = {}
    for i = 1, numSlots do
      local srcSlot = ((i - 1 + shift) % numSlots) + 1
      local ws = slotWorkspace[srcSlot]
      if ws ~= nil then
        newSlotWs[i] = ws
        newWsSlot[ws] = i
      end
    end
    slotWorkspace = newSlotWs
    workspaceSlot = newWsSlot
  else
    -- n is not visible: evict slot 1 (primary), assign n there.
    -- Secondary slots keep whatever they currently have.
    local evicted = slotWorkspace[1]
    if evicted then
      hideWorkspace(evicted)
      workspaceSlot[evicted] = nil
    end
    slotWorkspace[1] = n
    workspaceSlot[n] = 1
  end

  -- Always reconcile: fill any empty slots, prune any excess slots
  ensureSlotsFilled(numSlots)

  currentWorkspace = n

  -- Apply all slot assignments to their screens
  for slotIdx, wsNum in pairs(slotWorkspace) do
    if slots[slotIdx] then
      placeWorkspaceOnScreen(wsNum, slots[slotIdx])
    end
  end

  hs.alert.show("Workspace " .. n)

  local fw = focusedWindow[n]
  if fw and fw:isVisible() then
    fw:focus()
  end
end

-- Assign window to workspace

local function assignWindowToWorkspace(n)
  local win = hs.window.focusedWindow()
  if not win then return end
  local id = tostring(win:id())
  workspaces[id] = n
  hs.alert.show("Window assigned to Workspace " .. n)
  saveWorkspaceData(workspaces)
  windowsPosition[id] = win:frame()
end

-- Screen change: re-derive slots and reapply

hs.screen.watcher.new(function()
  -- Reset slot state and force re-layout on the current workspace.
  -- We temporarily clear currentWorkspace so showWorkspace doesn't early-exit.
  initSlots()
  local ws = currentWorkspace
  currentWorkspace = -1
  showWorkspace(ws)
end):start()

-- Hotkeys: workspace switching and assignment

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

-- Spotify controls

hs.hotkey.bind({ "alt" }, "space", function() hs.execute("spotify_player playback play-pause", true) end)
hs.hotkey.bind({ "alt" }, "[", function() hs.execute("spotify_player playback previous", true) end)
hs.hotkey.bind({ "alt" }, "]", function() hs.execute("spotify_player playback next", true) end)
hs.hotkey.bind({ "alt" }, "-", function() hs.execute("spotify_player playback volume --offset -- -5", true) end)
hs.hotkey.bind({ "alt" }, "=", function() hs.execute("spotify_player playback volume --offset 5", true) end)

-- jn timer integration

local function initJn(category)
  local b, description = hs.dialog.textPrompt(
    "[" .. category .. "] Insert the description", "Task to do it", "", "OK", "Cancel"
  )
  if b == "Cancel" or not description then
    focusedWindow[currentWorkspace]:focus()
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

  focusedWindow[currentWorkspace]:focus()
end

hs.hotkey.bind({ "alt" }, "/", function() initJn("programming") end)
hs.hotkey.bind({ "alt" }, ".", function() initJn("work") end)
hs.hotkey.bind({ "alt" }, ",", function()
  local b, category = hs.dialog.textPrompt("Insert category", "Indicate topic", "work", "OK", "Cancel")
  if b == "Cancel" or not category then
    focusedWindow[currentWorkspace]:focus()
    return
  end
  initJn(category)
end)

-- Bootstrap on load

hs.timer.doAfter(0.5, function()
  -- Force entry into showWorkspace on first load
  local ws = currentWorkspace
  currentWorkspace = -1
  showWorkspace(ws)
end)

hs.application.enableSpotlightForNameSearches(true)
hs.loadSpoon('ControlEscape'):start()

-- Neospeller

hs.hotkey.bind({ "alt" }, "g", function()
  hs.execute("~/.local/bin/ns-clip", true)
end)
