#!/bin/sh

# Reset any previous configuration
xrandr --output HDMI-A-0 --off
xrandr --auto

# Configure displays:
# - eDP: Internal laptop display
# - HDMI-A-1: External display, mirrored with same content
# - Scale from 4K (3840x2160) and set DPI for HiDPI display
xrandr --output eDP --scale-from 3840x2160 --output HDMI-A-0 --primary --mode 3840x2160 --pos 0x0 --output DisplayPort-0 --off --output DisplayPort-1 --off

