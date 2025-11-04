#!/bin/sh

# Reset any previous configuration
xrandr --output HDMI-1 --off
xrandr --auto

# Configure displays:
# - eDP-1: Internal laptop display
# - HDMI-A-1: External display, mirrored with same content
# - Scale from 4K (3840x2160) and set DPI for HiDPI display
xrandr --output eDP-1 --primary --pos 0x0 --scale 1x0.9 --output HDMI-1 --mode 3840x2160 --scale 0.5x0.5 --pos 0x0
./wallpaper.sh
