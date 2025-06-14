#!/bin/sh

# Reset any previous configuration
xrandr --output HDMI-1 --off
xrandr --auto

# Configure displays:
# - eDP-1: Internal laptop display
# - HDMI-A-1: External display, mirrored with same content
# - Scale from 4K (3840x2160) and set DPI for HiDPI display
xrandr --output eDP-1 --primary --mode 1366x768 --pos 0x0 --scale 1x1 --output HDMI-1 --mode 3840x2160 --scale 0.35x0.35 --pos 0x0 --output DisplayPort-0 --off --output DisplayPort-1 --off
./wallpaper.sh
