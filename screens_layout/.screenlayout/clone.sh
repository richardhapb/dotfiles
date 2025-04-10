#!/bin/sh

# Necessary for detect HMDI
xrandr --ouput HDMI-A-1 --off
xrandr --auto

xrandr --output eDP --auto --output HDMI-A-1 --primary --auto --same-as eDP --scale-from 3840x2160 --dpi 220 --output DisplayPort-0 --off --output DisplayPort-1 --off

