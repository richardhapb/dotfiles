-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

local opacity = 0.8

local windows = wezterm.target_triple:find("windows")
local macos = wezterm.target_triple:find("apple-darwin")
local linux = wezterm.target_triple:find("linux")

-- General configuration
config.color_scheme = 'GitHub Dark'
config.font = wezterm.font("MesloLGL Nerd Font Mono")
config.font_size = 14
config.window_background_image_hsb = {
    brightness = 0.1
}

config.colors = {
   -- Bash color scheme syntax
    ansi = {"#000000", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#bfbfbf"},
    brights = {"#4d4d4d", "#ff6e67", "#5af78e", "#f4f99d", "#caa9fa", "#ff92d0", "#9aedfe", "#e6e6e6"},
  }

config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true

config.keys = {
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
}

if macos then
   -- Toggle blur function
   local with_blur = 14
   local without_blur = 0
   local current_blur = with_blur

   local function toggle_blur(window)
       if current_blur == with_blur then
           current_blur = without_blur
       else
           current_blur = with_blur
       end

       window:set_config_overrides({macos_window_background_blur = current_blur})
   end

   opacity = 0.8
   config.macos_window_background_blur = 14

   table.insert(config.keys, {
        key = "b",
        mods = "ALT",
        action = wezterm.action_callback(toggle_blur)
    })
end

if linux then
    opacity = 0.9
end

if windows then
    opacity = 0.9
end

config.window_background_opacity = opacity

return config
