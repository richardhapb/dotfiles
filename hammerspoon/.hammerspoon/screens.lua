-- screens.lua — alt+shift+tab: send the focused thing to the next screen.
-- Mirrors AeroSpace's move-through-monitors, but on native macOS Spaces.
--
--   * Normal window     -> moved onto the NEXT screen and pinned to that
--                          screen's default (first "user") Space, then focused.
--   * Fullscreen window -> a fullscreen window owns a native fullscreen Space,
--                          which macOS pins to its display and refuses to
--                          relocate. So we exit fullscreen, hop the window to
--                          the next screen's default Space, and re-enter
--                          fullscreen -- a fresh fullscreen Space is then born
--                          on that display.
--
-- Why not "move the Space"? macOS binds every Space to one display permanently;
-- there is no API (Hammerspoon or otherwise) to move a Space between screens.
-- So "move the space between screens" is necessarily "move its window(s)".

-- Screens ordered left-to-right so "next" is spatially predictable and wraps.
local function orderedScreens()
  local screens = hs.screen.allScreens()
  table.sort(screens, function(a, b) return a:frame().x < b:frame().x end)
  return screens
end

local function nextScreen(screen)
  local screens = orderedScreens()
  if #screens < 2 then return nil end
  for i, s in ipairs(screens) do
    if s:id() == screen:id() then
      return screens[(i % #screens) + 1]
    end
  end
  return screens[1]
end

-- The default Space of a screen is its first "user" (desktop) Space. Fullscreen
-- Spaces are not valid landing targets, so skip them.
local function defaultSpace(screen)
  for _, id in ipairs(hs.spaces.spacesForScreen(screen:getUUID()) or {}) do
    if hs.spaces.spaceType(id) == "user" then return id end
  end
  return nil
end

-- Physically relocate the window onto `target` (moveToScreen keeps its relative
-- frame), THEN pin it to that display's default Space. moveWindowToSpace only
-- reassigns the Space -- it won't carry a window across displays on its own, so
-- the moveToScreen has to come first.
local function land(win, target, space)
  win:moveToScreen(target)
  hs.spaces.moveWindowToSpace(win, space)
  win:focus()
end

local function moveToNextScreen()
  local win = hs.window.focusedWindow()
  if not win then return end

  local target = nextScreen(win:screen())
  if not target then
    hs.alert.show("Only one screen")
    return
  end

  local space = defaultSpace(target)
  if not space then
    hs.alert.show("No desktop Space on target screen")
    return
  end

  if win:isFullScreen() then
    -- Exiting fullscreen is animated and async; moving the window before it has
    -- rejoined a user Space races the animation and silently no-ops. Wait it
    -- out, relocate, then re-enter fullscreen on the new display.
    win:setFullScreen(false)
    hs.timer.doAfter(0.8, function()
      land(win, target, space)
      win:setFullScreen(true)
    end)
  else
    land(win, target, space)
  end
end

hs.hotkey.bind({ "alt", "shift" }, "tab", moveToNextScreen)
