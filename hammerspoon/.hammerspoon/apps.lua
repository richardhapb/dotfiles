-- apps.lua — direct app focus/launch on alt+<key> (replaces AeroSpace workspaces).
-- App bindings only focus/launch; native macOS owns geometry, including fullscreen
-- Spaces (activating an app jumps to its Space). The one exception is alt+f, which
-- maximizes the focused window to fill the screen frame (see bottom of file).
--
-- To add/remove an app, edit the APPS table below. A value can be:
--   - a string:   app name for hs.application.launchOrFocus
--   - a function: custom focus logic (see braveProfile / focusDrawing)

local BRAVE = "Brave Browser"
local DRAWING_PATH = os.getenv("HOME") .. "/.local/bin/just_draw"

-- Brave profile aliases (work/personal) resolve through brouter's config so the
-- per-machine profile names live in one place, shared with URL routing:
--   "profiles": { "work": { "dir": "Default", "menu": "Checkr" }, ... }
-- 'dir' is the --profile-directory value, 'menu' the display name in Brave's
-- Profiles menu.
local BROUTER_CONFIG = os.getenv("HOME") .. "/.config/brouter/rules.json"

local function braveProfile(alias)
  return function()
    local cfg = hs.json.read(BROUTER_CONFIG) or {}
    local prof = cfg.profiles and cfg.profiles[alias]
    if not prof then
      hs.alert.show("No profiles." .. alias .. " in " .. BROUTER_CONFIG)
      return
    end

    -- Selecting the profile in Brave's Profiles menu focuses that profile's
    -- existing window (across fullscreen Spaces) instead of spawning a new one,
    -- which is what launching with --profile-directory does. The menu action
    -- works while Brave is in the background; activate() then brings the
    -- freshly-raised window forward.
    local app = hs.application.get(BRAVE)
    if app and prof.menu and app:selectMenuItem({ "Profiles", prof.menu }) then
      app:activate()
      return
    end

    -- Brave not running (or menu name stale): launch straight into the profile.
    hs.task.new("/usr/bin/open", nil, {
      "-na", BRAVE, "--args", "--profile-directory=" .. (prof.dir or "Default"),
    }):start()
  end
end

-- just_draw: focus the existing window, or launch and focus once it appears.
-- hs.window.allWindows() only enumerates the CURRENT Space, so once the
-- drawing window lives on another Space a fresh scan can't see it -- and
-- relaunching wipes the canvas. Instead, cache the hs.window handle when the
-- window is created (AX references stay valid across Spaces) and drop it when
-- the window is destroyed.
local drawingWin = nil

local function findDrawingWindow()
  for _, win in ipairs(hs.window.allWindows()) do
    if win:title():find("JUST%sDRAW") then return win end
  end
  return nil
end

-- windowCreated/windowDestroyed don't fire retroactively, so sync the initial
-- state in case the tool is already running when Hammerspoon (re)loads.
drawingWin = findDrawingWindow()

local drawFilter = hs.window.filter.new("just_draw")
drawFilter:subscribe(hs.window.filter.windowCreated, function(w) drawingWin = w end)
drawFilter:subscribe(hs.window.filter.windowDestroyed, function() drawingWin = nil end)

local function launchDrawing()
  -- just_draw doesn't quit when its window is closed -- it keeps running in
  -- the background holding the tablet device, which blocks a fresh instance
  -- from ever opening a window. Clear out any such stale process first.
  hs.execute("pkill -f " .. DRAWING_PATH)

  -- Pass the arguments table as arg 3: hs.task.new rejects an explicit nil in
  -- the streamCallback slot ("incorrect type 'nil' for argument 3"), so the
  -- `nil, { "--udp" }` form threw before the task was ever created -- which is
  -- why --udp never took effect. Omit the stream callback entirely instead.
  local task = hs.task.new(DRAWING_PATH, function(code, _, stderr)
    if code ~= 0 then hs.notify.show("Just Draw", "", stderr or "") end
  end, { "--udp" })
  if not task then return end
  task:start()

  -- Poll asynchronously: a blocking loop here would stall Hammerspoon's run
  -- loop, which is exactly what starves the accessibility notifications that
  -- make the new window show up in hs.window.allWindows().
  local attempt = 0
  local function waitForWindow()
    local w = findDrawingWindow()
    if w then
      drawingWin = w
      w:focus()
      return
    end
    attempt = attempt + 1
    if attempt >= 15 then
      hs.notify.show("Error", "", "Cannot find drawing window")
      task:terminate()
      return
    end
    hs.timer.doAfter(0.2, waitForWindow)
  end
  hs.timer.doAfter(0.2, waitForWindow)
end

local function focusDrawing()
  -- Prefer the cached handle: it can focus the window from any Space.
  if drawingWin then
    local ok = pcall(function() drawingWin:focus() end)
    if ok and drawingWin:application() then return end
    drawingWin = nil -- handle went stale (window closed without a destroy event)
  end

  local win = findDrawingWindow()
  if win then
    drawingWin = win
    win:focus()
    return
  end

  -- No window handle anywhere, but the process may still be alive with a
  -- window Hammerspoon can't enumerate (e.g. after a reload while the window
  -- sits on another Space). Activate the app and check whether its window
  -- lands in the current Space before concluding it's a stale headless
  -- process -- relaunching wipes the canvas, so only do it as a last resort.
  local app = hs.application.get("just_draw")
  if app then
    app:activate()
    hs.timer.doAfter(0.5, function()
      local w = findDrawingWindow()
      if w then
        drawingWin = w
        w:focus()
      else
        launchDrawing()
      end
    end)
    return
  end

  launchDrawing()
end

-- Focus an app by name, jumping to its fullscreen Space if needed.
-- hs.application.launchOrFocus only *activates* the app, and with
-- AppleSpacesSwitchOnActivate off (System Settings > Desktop & Dock >
-- "When switching to an application, switch to a Space with open windows...")
-- macOS won't follow the window to its Space. Focusing a concrete window via
-- AX switches Spaces regardless of that setting. mainWindow() is AX-based so
-- it sees windows on other Spaces (allWindows() returns 0 for some apps,
-- e.g. Telegram, so don't rely on it).
local function focusApp(name)
  return function()
    local app = hs.application.get(name)
    local win = app and (app:mainWindow() or app:allWindows()[1])
    if win then
      win:focus()
    else
      hs.application.launchOrFocus(name)
    end
  end
end

local APPS = {
  ["1"] = "Ghostty",
  ["2"] = braveProfile("personal"),
  ["3"] = braveProfile("work"),
  ["4"] = "Slack",
  ["5"] = "Spotify",
  ["9"] = "Claude",
  ["a"] = "Granola",
  ["s"] = "Telegram",
  ["z"] = "zoom.us",
  ["p"] = focusDrawing,
}

for key, target in pairs(APPS) do
  local fn = target
  if type(target) == "string" then
    fn = focusApp(target)
  end
  hs.hotkey.bind({ "alt" }, key, fn)
end

-- alt+tab bounces between the two most recently used apps (replaces
-- AeroSpace's workspace-back-and-forth, at app granularity).
local currentApp, previousApp
local appWatcher = hs.application.watcher.new(function(_, event, app)
  if event ~= hs.application.watcher.activated then return end
  local id = app and app:bundleID()
  if id and id ~= currentApp then
    previousApp = currentApp
    currentApp = id
  end
end)
appWatcher:start()

hs.hotkey.bind({ "alt" }, "tab", function()
  if previousApp then hs.application.launchOrFocusByBundleID(previousApp) end
end)

-- alt+f maximizes the focused window to fill the screen frame (respecting the
-- menu bar / Dock). Unlike native fullscreen, the window stays in its Space.
hs.hotkey.bind({ "alt" }, "f", function()
  local win = hs.window.focusedWindow()
  if win then win:maximize() end
end)

-- Keep the watcher and window filter referenced via package.loaded so they
-- aren't garbage-collected.
return { appWatcher = appWatcher, drawFilter = drawFilter }
