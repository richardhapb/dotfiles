#!/usr/bin/env bash
# Extract one symbol's full s-expression block from a KiCad .kicad_sym library,
# using balanced-paren matching. Usage:
#   extract_symbol.sh <library.kicad_sym> '<SymbolName>'
# Example:
#   extract_symbol.sh "$SYM/Device.kicad_sym" R
#   extract_symbol.sh "$SYM/Simulation_SPICE.kicad_sym" VDC
#   extract_symbol.sh "$SYM/power.kicad_sym" GND
# where SYM=/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols
set -euo pipefail
lib="$1"; name="$2"
awk -v n="$name" '
  $0 ~ "\\(symbol \"" n "\"" { f=1 }
  f { print; d+=gsub(/\(/,"("); d-=gsub(/\)/,")"); if (f && d<=0) exit }
' "$lib"
