-- apps.lua — direct app focus/launch on alt+<key> (replaces AeroSpace workspaces).
-- Focus only: never moves, resizes, or tiles windows. Native macOS owns geometry,
-- including fullscreen Spaces (activating an app jumps to its Space).
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
local function findDrawingWindow()
  for _, win in ipairs(hs.window.allWindows()) do
    if win:title():find("JUST%sDRAW") then return win end
  end
  return nil
end

local function focusDrawing()
  local win = findDrawingWindow()
  if win then
    win:focus()
    return
  end

  -- just_draw doesn't quit when its window is closed -- it keeps running in
  -- the background holding the tablet device, which blocks a fresh instance
  -- from ever opening a window. Clear out any such stale process first.
  hs.execute("pkill -f " .. DRAWING_PATH)

  local task = hs.task.new(DRAWING_PATH, function(code, _, stderr)
    if code ~= 0 then hs.notify.show("Just Draw", "", stderr or "") end
  end)
  if not task then return end
  task:start()

  -- Poll asynchronously: a blocking loop here would stall Hammerspoon's run
  -- loop, which is exactly what starves the accessibility notifications that
  -- make the new window show up in hs.window.allWindows().
  local attempt = 0
  local function waitForWindow()
    local w = findDrawingWindow()
    if w then
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
    fn = function() hs.application.launchOrFocus(target) end
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

-- Keep the watcher referenced via package.loaded so it isn't garbage-collected.
return { appWatcher = appWatcher }
