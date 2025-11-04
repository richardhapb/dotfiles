#!/bin/sh
# Necessary for detect HMDI
xrandr --output HDMI-1 --off
xrandr --auto


xrandr --output eDP-1 --left-of HDMI-1 --scale 1x0.9 --output HDMI-1 --primary  --mode 3840x2160 --scale 0.5x0.5 --dpi 220 --pos 0x0 --rotate normal

./wallpaper.sh
