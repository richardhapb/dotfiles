---
name: kicad-spice-schematic
description: Author a simulation-ready KiCad schematic (and project) for an analog circuit from a description — voltage dividers, RC/RLC filters, biasing networks, op-amp stages, etc. Use when the user wants a KiCad project they can open and run in the built-in ngspice simulator, NOT a PCB layout. Produces a validated .kicad_sch + .kicad_pro using local kicad-cli; no KiCad GUI, no MCP server, no PCB.
---

# KiCad SPICE schematic authoring

Generate a valid KiCad 9/10 schematic with embedded SPICE models, ready to run
in KiCad's built-in ngspice. The KiCad MCP servers are analysis-/PCB-oriented and
don't author simulatable schematics — this does it by writing the `.kicad_sch`
s-expression directly and validating with `kicad-cli`.

## When to use
- "Make me a KiCad project for <analog circuit> ready to simulate."
- Verifying a divider/filter/bias network before building it.
NOT for PCB layout, footprints, or routing.

## Project location (Richard's convention)
All new KiCad projects go under **`~/kicad/<project-name>/`** — one
folder per project. Create the project there, not inside the code repo.

## Tooling (macOS paths; adjust per OS)
- CLI: `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`
- Symbol libs: `/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/`
  (`Device.kicad_sym`, `Simulation_SPICE.kicad_sym`, `power.kicad_sym`)
- Project template: `.../SharedSupport/template/kicad.kicad_pro`
- ngspice runs **inside the KiCad GUI** — there is usually no standalone
  `ngspice` binary, so you can't run the sim from the CLI. Validate connectivity
  with `kicad-cli` and have the user press Run in the GUI.

## Procedure
1. **Find the schematic format version** from any shipped demo:
   `grep -m1 version .../template/.../*.kicad_sch` (e.g. `(version 20250114)`).
2. **Extract the symbol defs** you need from the libraries with a balanced-paren
   extractor (see `scripts/extract_symbol.sh`). Typical symbols:
   - `Device:R`, `Device:C`, `Device:L`
   - `Simulation_SPICE:VDC` (DC source; `Value` field = volts), `VSIN`, `VPULSE`,
     `IDC`, `OPAMP`, diodes/transistors (each carries `Sim.Device`/`Sim.Type`)
   - `power:GND` (becomes ngspice node 0), `power:PWR_FLAG`
3. **Assemble the `.kicad_sch`** (see `scripts/example_divider.py` — a working,
   validated template you adapt). Key rules:
   - Embed each used symbol inside `(lib_symbols ...)`, renaming the outer id to
     `lib_id` form: `(symbol "R"` → `(symbol "Device:R"`, etc.
   - Each placed symbol needs an `(instances (project "<proj>" (path "/<root-uuid>"
     (reference "R1") (unit 1))))` block; the path uuid = the schematic's own uuid.
   - **Connectivity** = coincident coordinates. A wire endpoint or a label at a
     pin's tip joins them. Easiest robust pattern: a short wire stub off each pin
     + a **local label** (same label text on one sheet = same net). Series parts:
     connect pin-to-pin with a wire (auto-named internal node).
   - Pin tip math (rotation 0): symbol pin `(at sx sy …)` → schematic
     `(px + sx, py - sy)`. `Device:R` pins at sy = ±3.81; `VDC` at ±5.08; `GND`/
     `PWR_FLAG` pin at origin.
   - **Stay on the 1.27 mm grid** (use multiples of 1.27 for every coordinate) or
     ERC throws `endpoint_off_grid` warnings.
   - Add a `power:PWR_FLAG` on the ground net, else ERC errors
     `power_pin_not_driven`.
   - **Embed the SPICE command** as a `(text ".op" (exclude_from_sim no) …)` whose
     content starts with `.` — the netlist exporter appends it, so the project is
     truly ready to Run. `.op` prints node voltages; `.dc V1 0 5 0.1` sweeps;
     `.tran 1u 5m` for transient.
   - Unique references (`R1..`, `V1`, `#PWR01/02`, `#FLG01`) or you get annotation
     errors.
4. **Project file**: copy the template `kicad.kicad_pro` to `<name>.kicad_pro`.
5. **Validate** (must be clean before handing over):
   ```
   kicad-cli sch erc <name>.kicad_sch -o /dev/stdout      # want: Errors 0 Warnings 0
   kicad-cli sch export netlist --format spice -o /tmp/n.cir <name>.kicad_sch
   ```
   Read `/tmp/n.cir` and confirm the topology + the `.` directive are present.
   Hand-check the expected node voltages.
6. **Write a short README** with the circuit, expected results, and "Inspect →
   Simulator → Run" instructions.

## Gotchas learned
- `kicad-cli` can't create or simulate, only validate/export — so author the file
  yourself and lean on `erc` + `export netlist` as the test loop.
- Symbol library version (`.kicad_sym`) differs from schematic version
  (`.kicad_sch`) — don't copy one into the other's header.
- `exclude_from_sim yes` on a directive text means it's NOT exported — set `no`.
- Coincident pin endpoints connect, but at a 3-way tee add a `(junction …)`.

`scripts/example_divider.py` is the reference implementation that produced a
0-error/0-warning HC-SR04 5V→3.3V divider with an embedded `.op`. Copy it and
change the components/topology/directive for the new circuit.
