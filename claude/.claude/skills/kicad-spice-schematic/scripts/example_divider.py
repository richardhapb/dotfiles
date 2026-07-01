#!/usr/bin/env python3
import os, uuid, pathlib

# SP must hold the extracted symbol blocks sym_r.txt / sym_vdc.txt / sym_gnd.txt
# / sym_pwrflag.txt — produce them first with scripts/extract_symbol.sh, e.g.:
#   SYM=/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols
#   extract_symbol.sh "$SYM/Device.kicad_sym" R           > $SP/sym_r.txt
#   extract_symbol.sh "$SYM/Simulation_SPICE.kicad_sym" VDC > $SP/sym_vdc.txt
#   extract_symbol.sh "$SYM/power.kicad_sym" GND          > $SP/sym_gnd.txt
#   extract_symbol.sh "$SYM/power.kicad_sym" PWR_FLAG     > $SP/sym_pwrflag.txt
SP = pathlib.Path(os.environ.get("SP", "/tmp/kicad_syms"))
OUT = pathlib.Path.home() / "kicad" / "massbe-rover" / "echo-divider"
PROJ = "echo-divider"
ROOT_UUID = "11111111-1111-4111-8111-111111111111"

def U():
    return str(uuid.uuid4())

# --- embedded library symbols, renamed to lib_id form ---
sym_r   = (SP/"sym_r.txt").read_text().replace('(symbol "R"',   '(symbol "Device:R"', 1)
sym_vdc = (SP/"sym_vdc.txt").read_text().replace('(symbol "VDC"', '(symbol "Simulation_SPICE:VDC"', 1)
sym_gnd = (SP/"sym_gnd.txt").read_text().replace('(symbol "GND"', '(symbol "power:GND"', 1)
sym_flg = (SP/"sym_pwrflag.txt").read_text().replace('(symbol "PWR_FLAG"', '(symbol "power:PWR_FLAG"', 1)
lib_symbols = "\t(lib_symbols\n" + sym_r + sym_vdc + sym_gnd + sym_flg + "\t)\n"

parts = []   # symbol instance blocks
wires = []
labels = []
texts = []

def wire(x1,y1,x2,y2):
    wires.append(f'''\t(wire
\t\t(pts (xy {x1} {y1}) (xy {x2} {y2}))
\t\t(stroke (width 0) (type default))
\t\t(uuid "{U()}")
\t)\n''')

def label(name,x,y,ang=0):
    labels.append(f'''\t(label "{name}"
\t\t(at {x} {y} {ang})
\t\t(effects (font (size 1.27 1.27)) (justify left bottom))
\t\t(uuid "{U()}")
\t)\n''')

def junction(x,y):
    wires.append(f'\t(junction (at {x} {y}) (diameter 0) (color 0 0 0 0) (uuid "{U()}"))\n')

def pwrflag(x,y):
    parts.append(f'''\t(symbol
\t\t(lib_id "power:PWR_FLAG")
\t\t(at {x} {y} 0)
\t\t(unit 1)
\t\t(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)
\t\t(uuid "{U()}")
\t\t(property "Reference" "#FLG01" (at {x} {y-3.81} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Value" "PWR_FLAG" (at {x} {y-5.08} 0) (effects (font (size 1.27 1.27))))
\t\t(property "Footprint" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Datasheet" "~" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(pin "1" (uuid "{U()}"))
\t\t(instances (project "{PROJ}" (path "/{ROOT_UUID}" (reference "#FLG01") (unit 1))))
\t)\n''')

def text(s,x,y):
    texts.append(f'''\t(text "{s}"
\t\t(exclude_from_sim yes)
\t\t(at {x} {y} 0)
\t\t(effects (font (size 1.27 1.27)) (justify left))
\t\t(uuid "{U()}")
\t)\n''')

def res(ref,val,x,y):
    pins = '\n'.join(f'\t\t(pin "{n}" (uuid "{U()}"))' for n in ("1","2"))
    parts.append(f'''\t(symbol
\t\t(lib_id "Device:R")
\t\t(at {x} {y} 0)
\t\t(unit 1)
\t\t(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)
\t\t(uuid "{U()}")
\t\t(property "Reference" "{ref}" (at {x+3.81} {y} 0) (effects (font (size 1.27 1.27)) (justify left)))
\t\t(property "Value" "{val}" (at {x+3.81} {y+2.54} 0) (effects (font (size 1.27 1.27)) (justify left)))
\t\t(property "Footprint" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Datasheet" "~" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
{pins}
\t\t(instances (project "{PROJ}" (path "/{ROOT_UUID}" (reference "{ref}") (unit 1))))
\t)\n''')

def vdc(ref,val,x,y):
    pins = '\n'.join(f'\t\t(pin "{n}" (uuid "{U()}"))' for n in ("1","2"))
    parts.append(f'''\t(symbol
\t\t(lib_id "Simulation_SPICE:VDC")
\t\t(at {x} {y} 0)
\t\t(unit 1)
\t\t(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)
\t\t(uuid "{U()}")
\t\t(property "Reference" "{ref}" (at {x+5.08} {y-2.54} 0) (effects (font (size 1.27 1.27)) (justify left)))
\t\t(property "Value" "{val}" (at {x+5.08} {y} 0) (effects (font (size 1.27 1.27)) (justify left)))
\t\t(property "Footprint" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Datasheet" "~" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
{pins}
\t\t(instances (project "{PROJ}" (path "/{ROOT_UUID}" (reference "{ref}") (unit 1))))
\t)\n''')

_pwr = [0]
def gnd(x,y):
    _pwr[0] += 1
    ref = f"#PWR0{_pwr[0]}"
    parts.append(f'''\t(symbol
\t\t(lib_id "power:GND")
\t\t(at {x} {y} 0)
\t\t(unit 1)
\t\t(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no)
\t\t(uuid "{U()}")
\t\t(property "Reference" "{ref}" (at {x} {y+5.08} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Value" "GND" (at {x} {y+3.81} 0) (effects (font (size 1.27 1.27))))
\t\t(property "Footprint" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Datasheet" "~" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(pin "1" (uuid "{U()}"))
\t\t(instances (project "{PROJ}" (path "/{ROOT_UUID}" (reference "{ref}") (unit 1))))
\t)\n''')

# ---- layout (all coords on the 1.27mm / 50mil connection grid) ----
X = 101.6   # 80 * 1.27
# resistor chain centers spaced 12.7mm; R pin tips at center ±3.81
centers = [50.8 + 12.7*i for i in range(6)]   # R1..R6  (all multiples of 1.27)
for i,cy in enumerate(centers):
    res(f"R{i+1}", "100", X, cy)

# pin tips helper
def top(cy):    return cy-3.81
def bot(cy):    return cy+3.81

# series wires between consecutive resistors (these are the internal nodes)
for i in range(5):
    wire(X, bot(centers[i]), X, top(centers[i+1]))

# IN: above R1
wire(X, top(centers[0]), X, top(centers[0])-2.54)
label("IN", X, top(centers[0])-2.54)

# OUT / TAP: the node between R2 and R3 (after 2x100 top, before 4x100 bottom)
tap_y = (bot(centers[1]) + top(centers[2]))/2.0   # midpoint of that wire
label("OUT", X, tap_y)

# GND: below R6, plus a PWR_FLAG so ERC sees the ground net as driven
gy = bot(centers[5])
wire(X, gy, X, gy+2.54)
gnd(X, gy+2.54)
wire(X, gy, X+7.62, gy)        # branch right to the flag
junction(X, gy)
pwrflag(X+7.62, gy)

# V1 on the left: + -> IN, - -> GND
VX = 68.58; VY = 63.5      # 54*1.27, 50*1.27 ; VDC pin1(+) at VY-5.08, pin2(-) at VY+5.08
vdc("V1", "5", VX, VY)
wire(VX, VY-5.08, VX, VY-5.08-2.54); label("IN", VX, VY-5.08-2.54)
wire(VX, VY+5.08, VX, VY+5.08+2.54); gnd(VX, VY+5.08+2.54)

# annotations
text("HC-SR04 ECHO divider  -  Vout = 5 * 400/600 = 3.33 V", 55.0, 30.0)
text("top = R1+R2 = 200 ohm   bottom = R3..R6 = 400 ohm", 55.0, 34.0)
text("OUT -> ESP32 GPIO7 (high-Z input, no load)", 108.0, tap_y)
# real, exported SPICE directive (text starting with '.' with exclude_from_sim no
# is appended to the netlist) — operating point prints every node voltage.
texts.append(f'''\t(text ".op"
\t\t(exclude_from_sim no)
\t\t(at 55.0 138.0 0)
\t\t(effects (font (size 1.524 1.524) (color 80 180 255 1)) (justify left))
\t\t(uuid "{U()}")
\t)\n''')
text("Sim directive above (.op = DC node voltages). Alt: edit to '.dc V1 0 5 0.1' to sweep input.", 55.0, 142.0)

sch = (
    '(kicad_sch\n'
    '\t(version 20250114)\n'
    '\t(generator "eeschema")\n'
    '\t(generator_version "9.0")\n'
    f'\t(uuid "{ROOT_UUID}")\n'
    '\t(paper "A4")\n'
    + lib_symbols
    + "".join(wires)
    + "".join(labels)
    + "".join(texts)
    + "".join(parts)
    + '\t(sheet_instances\n\t\t(path "/" (page "1"))\n\t)\n'
    + ')\n'
)
(OUT/f"{PROJ}.kicad_sch").write_text(sch)
print("wrote", OUT/f"{PROJ}.kicad_sch", len(sch), "bytes")
