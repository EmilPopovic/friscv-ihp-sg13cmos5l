#!/usr/bin/env bash
# Build the HyperBus delay-line macro and install its views.
#   ./build.sh          build into out/, do not touch views/
#   ./build.sh install  build, then copy out/ -> views/
set -euo pipefail

cd "$(dirname "$0")"

DESIGN=delay_line_D4_O1_6P000
: "${PDK:?set PDK}"
: "${PDK_ROOT:?set PDK_ROOT}"

REF=$PDK_ROOT/$PDK/libs.ref
TECH=$PDK_ROOT/$PDK/libs.tech/klayout/tech

LYT=$(echo "$TECH"/*.lyt)
[ -f "$LYT" ] || { echo "no .lyt under $TECH"; exit 1; }

LIBRELANE_PY=$("$(command -v librelane)" --version >/dev/null 2>&1; \
    python3 - <<'EOF'
import os, shutil, re, sys
path = shutil.which("librelane")
for _ in range(8):
    with open(path) as f:
        head = f.readline()
        body = f.read()
    if "python" in head:
        break
    m = re.findall(r'^exec (?:-a "\$0" )?"([^"]+)"', body, re.M)
    if not m:
        sys.exit("could not follow librelane wrapper chain")
    path = m[-1]
else:
    sys.exit("could not follow librelane wrapper chain")
interp = head.lstrip("#!").split()[0]
root = os.path.dirname(os.path.dirname(path))
for entry in os.listdir(os.path.join(root, "lib")):
    sp = os.path.join(root, "lib", entry, "site-packages")
    if os.path.isdir(os.path.join(sp, "librelane")):
        print(interp)
        print(sp)
        break
else:
    sys.exit("could not find librelane site-packages")
EOF
)
PY=$(echo "$LIBRELANE_PY" | head -1)
LIBRELANE_PY=$(echo "$LIBRELANE_PY" | tail -1)
STREAM_OUT=$LIBRELANE_PY/librelane/scripts/klayout/stream_out.py

echo "== openroad: place, route, characterise =="
openroad -no_init -exit delay.tcl

echo "== fix up liberty power pins =="
"$PY" - "out/$DESIGN.lib" <<'EOF'
import re, sys

path = sys.argv[1]
lib = open(path).read()

pg = {"VDD": "primary_power", "VSS": "primary_ground"}
found = []
for net, kind in pg.items():
    pat = re.compile(
        r'^[ \t]*pin\("%s"\)[ \t]*\{[^}]*\}[ \t]*\n' % net, re.M
    )
    lib, n = pat.subn("", lib)
    if n:
        found.append((net, kind, n))

if not found:
    sys.exit(f"{path}: no signal-pin VDD/VSS blocks to convert - did the "
             f"write_timing_model output change?")

m = re.search(r'^([ \t]*)cell \("?[\w\[\]]+"?\)[ \t]*\{[ \t]*\n', lib, re.M)
if not m:
    sys.exit(f"{path}: could not find the cell declaration")
indent = m.group(1) + "  "
block = "".join(
    f'{indent}pg_pin ({net}) {{\n'
    f'{indent}  pg_type : {kind};\n'
    f'{indent}  voltage_name : {net};\n'
    f'{indent}}}\n'
    for net, kind, _ in found
)
lib = lib[: m.end()] + block + lib[m.end() :]

m = re.search(r'^([ \t]*)library[ \t]*\([^)]*\)[ \t]*\{[ \t]*\n', lib, re.M)
if not m:
    sys.exit(f"{path}: could not find the library declaration")
vmap = f'{m.group(1)}  voltage_map (VDD, 1.20);\n{m.group(1)}  voltage_map (VSS, 0.0);\n'
lib = lib[: m.end()] + vmap + lib[m.end() :]

open(path, "w").write(lib)
print("  converted to pg_pin: " + ", ".join(n for n, _, _ in found))
EOF

echo "== klayout: stream out GDS =="
PYTHONPATH="$LIBRELANE_PY${PYTHONPATH:+:$PYTHONPATH}" "$PY" "$STREAM_OUT" \
    "out/$DESIGN.def" \
    --output "out/$DESIGN.gds" \
    --top "$DESIGN" \
    --conflict-resolution OverwriteCell \
    -T "$LYT" \
    -P "${LYT%.lyt}.lyp" \
    -M "${LYT%.lyt}.map" \
    -l "$REF/sg13cmos5l_stdcell/lef/sg13cmos5l_tech.lef" \
    -l "$REF/sg13cmos5l_stdcell/lef/sg13cmos5l_stdcell.lef" \
    -w "$REF/sg13cmos5l_stdcell/gds/sg13cmos5l_stdcell.gds"

echo "== checks =="
fail=0

abst=out/$DESIGN.abst.lef
if [ "$(grep -c "^MACRO $DESIGN\$" "$abst")" != 1 ]; then
    echo "FAIL: $abst does not define exactly one MACRO $DESIGN"; fail=1
fi
for pin in VDD VSS; do
    if ! grep -q "^  PIN $pin\$" "$abst"; then
        echo "FAIL: $abst has no $pin pin - the parent cannot power this macro"
        echo "      (librelane would report PDN-0231 as a *warning* and ship it)"
        fail=1
    fi
done
if ! awk "/^  PIN VDD\$/,/^  END VDD\$/" "$abst" | grep -q "LAYER Metal4"; then
    echo "FAIL: VDD pin is not on Metal4; librelane's macro grid connects"
    echo "      Metal4 to TopMetal1, so pins on any other layer are unreachable"
    fail=1
fi

lib=out/$DESIGN.lib
if grep -qE '^\s*pin\("(VDD|VSS)"\)' "$lib"; then
    echo "FAIL: $lib still declares VDD/VSS as signal pins"; fail=1
fi
for net in VDD VSS; do
    grep -q "pg_pin ($net)" "$lib" || { echo "FAIL: $lib has no pg_pin ($net)"; fail=1; }
done

drc=reports/route_drc.rpt
if [ -s "$drc" ]; then
    n=$(grep -c "violation type" "$drc" || true)
    if [ "$n" != 0 ]; then echo "FAIL: $n routing DRC violations, see $drc"; fail=1; fi
fi

[ "$fail" = 0 ] && echo "OK: $(grep -oP 'SIZE \K[0-9.]+ BY [0-9.]+' "$abst")" || exit 1

if [ "${1:-}" = install ]; then
    echo "== install =="
    mkdir -p views
    for ext in abst.lef lib def v sdf sdc gds; do
        cp -v "out/$DESIGN.$ext" "views/$DESIGN.$ext"
    done
fi
