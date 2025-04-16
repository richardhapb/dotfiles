#!/bin/sh
# Necessary for detect HMDI
xrandr --output HDMI-A-0 --off
xrandr --auto

xrandr --output eDP --right-of HDMI-A-0 --output HDMI-A-0 --primary --dpi 220 --pos 0x0 --rotate normal --output DisplayPort-0 --off --output DisplayPort-1 --off
