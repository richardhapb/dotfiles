#!/bin/sh

# Necessary for detect HMDI
xrandr --output HDMI-A-1 --off
xrandr --auto

xrandr --output eDP --off --output HDMI-A-1 --primary --dpi 220 --pos 0x0 --rotate normal --output DisplayPort-0 --off --output DisplayPort-1 --off
