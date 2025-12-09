-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()
config.term = "xterm-256color"
config.keys = {}

config.animation_fps = 120
config.max_fps = 120
config.front_end = "OpenGL"

local opacity = 0.8
local bg = "#111111"

local macos = wezterm.target_triple:match("apple")
local linux = wezterm.target_triple:match("linux")

if linux then
  opacity = 0.9
end

if macos then
  -- Toggle blur function
  local with_blur = 20
  local without_blur = 0
  local current_blur = with_blur
  local hard_opacity = 0.9
  local soft_opacity = 0.4

  local function toggle_blur(window)
    if current_blur == with_blur then
      current_blur = without_blur
      opacity = soft_opacity
    else
      current_blur = with_blur
      opacity = hard_opacity
    end

    window:set_config_overrides({ macos_window_background_blur = current_blur, window_background_opacity = opacity })
  end

  opacity = hard_opacity
  local current_opacity = opacity

  local function toggle_opacity(window)
    if current_opacity == 0.4 then
      current_opacity = 0.9
    else
      current_opacity = 0.4
    end

    window:set_config_overrides({ window_background_opacity = current_opacity })
  end

  config.macos_window_background_blur = 14

  table.insert(config.keys, {
    key = "b",
    mods = "ALT",
    action = wezterm.action_callback(toggle_blur)
  }
  )
  table.insert(config.keys,
    {
      key = "o",
      mods = "ALT",
      action = wezterm.action_callback(toggle_opacity)
    })
end

-- General configuration
config.color_scheme = 'GitHub Dark'
config.font = wezterm.font_with_fallback {
  {
    family = 'Monaspace Neon', weight = "Medium",
    harfbuzz_features = {
      "calt", -- Contextual Alternates (for ligatures like ->, =>, etc.)
      "ss01", -- Stylistic Set 1
      "ss02", -- Stylistic Set 2
      "ss03", -- Stylistic Set 3
      "ss04", -- Stylistic Set 4
    }
  },
  { family = 'JetBrains Mono', weight = "DemiBold" },
}
config.font_size = 13
config.window_background_image_hsb = {
  brightness = 0.1
}
config.use_ime = true
config.enable_kitty_graphics = true

config.colors = {
  background = bg,
  -- Bash color scheme syntax
  ansi = { "#000000", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#bfbfbf" },
  brights = { "#4d4d4d", "#ff6e67", "#5af78e", "#f4f99d", "#caa9fa", "#ff92d0", "#9aedfe", "#e6e6e6" },
}

config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = opacity

local current_opacity = opacity

local mux = wezterm.mux

wezterm.on('gui-startup', function(_)
  local _, _, window = mux.spawn_window({})
  local gui_window = window:gui_window();
  gui_window:maximize()
  gui_window:set_config_overrides({ window_background_opacity = opacity })
end)

local keys = {
  {
    key = "h",
    mods = "ALT",
    action = wezterm.action_callback(function(window, pane)
      local tab = window:mux_window():active_tab()
      if tab:get_pane_direction("Left") ~= nil then
        window:perform_action(wezterm.action.ActivatePaneDirection("Left"), pane)
      else
        window:perform_action(wezterm.action.ActivateTabRelative(-1), pane)
      end
    end),
  },
  { key = "j", mods = "ALT", action = wezterm.action.ActivatePaneDirection("Down") },
  { key = "k", mods = "ALT", action = wezterm.action.ActivatePaneDirection("Up") },
  {
    key = "l",
    mods = "ALT",
    action = wezterm.action_callback(function(window, pane)
      local tab = window:mux_window():active_tab()
      if tab:get_pane_direction("Right") ~= nil then
        window:perform_action(wezterm.action.ActivatePaneDirection("Right"), pane)
      else
        window:perform_action(wezterm.action.ActivateTabRelative(1), pane)
      end
    end)
  },
  {
    key = "z",
    mods = "ALT",
    action = wezterm.action_callback(function(window)
      if current_opacity ~= 1 then
        bg = "#222222"
        current_opacity = 1
      else
        bg = "#111111"
        current_opacity = opacity
      end

      window:set_config_overrides({ window_background_opacity = current_opacity, colors = { background = bg } })
    end)
  }
}

for _, key in ipairs(keys) do
  table.insert(config.keys, key)
end

return config
