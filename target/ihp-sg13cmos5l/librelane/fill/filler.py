# Copyright 2026 FER, HPC Architecture and Application Research Center
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

# Fill script for IHP SG13CMOS5L PDK

import os
import pathlib
import sys

import pya

try:
    output_file
except NameError:
    print("Missing output_file argument. Define '-rd output_file=<path-to-output-file>'")
    sys.exit(1)

pdk_macros = pathlib.Path(os.environ["PDK_ROOT"]) / os.environ["PDK"] / "libs.tech/klayout/tech/macros"

# Run stock fill first
for area, path in [
    ("ActGatP", pdk_macros / "sg13cmos5l_filler_ActGatP.lym"),
    ("Metal", pdk_macros / "sg13cmos5l_filler_Metal.lym"),
]:
    print(f"Start filling {area}")
    pya.Macro(str(path)).run()

layout = pya.CellView.active().layout()
top = layout.top_cell()
dbu = layout.dbu


def um(x):
    return int(round(x / dbu))


FILL_SIZE = 1.0      # fill tile edge
FILL_STEP = 1.42     # tile pitch (spacing + tile size)
SNAP_MARGIN = 0.422  # 0.42 fill-to-metal spacing + slack for snap
GRID = 0.005         # manufacturing grid
TILE = 100.0         # work region size
PASSES = 5           # refill attempts per region


# Instance array a with its origin snapped to GRID
def snapped(a):
    grid = um(GRID)
    d = a.trans.disp
    t = pya.Trans(a.trans.rot, a.trans.is_mirror(), pya.Vector(round(d.x / grid) * grid, round(d.y / grid) * grid))

    if a.is_regular_array():
        return pya.CellInstArray(a.cell_index, t, a.a, a.b, a.na, a.nb)
    return pya.CellInstArray(a.cell_index, t)


# Insert instance array a into cell, minus the elements placed at a point in dropped
def insert_without(cell, a, dropped):
    if not a.is_regular_array():
        if (a.trans.disp.x, a.trans.disp.y) not in dropped:
            cell.insert(a)
        return

    elements = [(i, j) for i in range(a.na) for j in range(a.nb)]
    disp = {(i, j): a.trans.disp + a.a * i + a.b * j for i, j in elements}
    kept = [e for e in elements if (disp[e].x, disp[e].y) not in dropped]

    if len(kept) == len(elements):
        cell.insert(a)
        return

    for e in kept:
        cell.insert(pya.CellInstArray(a.cell_index, pya.Trans(a.trans.rot, a.trans.is_mirror(), disp[e])))


def gap_fill(name, layer, extra_keepout_layers):
    drw = layout.find_layer(layer, 0)   # Drawing
    fil = layout.find_layer(layer, 22)  # Existing fill
    fil_out = layout.layer(layer, 22)   # Output fill
    seal = layout.find_layer(39, 0)     # Seal ring
    blockers = [layout.find_layer(l, d) for l, d in extra_keepout_layers]  # No-fill layers
    blockers = [b for b in blockers if b is not None]

    # Only fill inside the seal ring if present, otherwise whole die
    inner = pya.Region(top.begin_shapes_rec(seal)).holes() if seal is not None else pya.Region(top.bbox())
    inner.merge()

    # Holder cell for fill arrays and the 1x1 um fill tile
    cell = layout.create_cell(f"{name}_GAP_FILL")
    scratch = layout.create_cell(f"{name}_GAP_FILL_SCRATCH")
    tile_cell = layout.create_cell(f"{name}_GAP_FILL_TILE")
    tile_cell.shapes(fil_out).insert(pya.Box(0, 0, um(FILL_SIZE), um(FILL_SIZE)))
    step = um(FILL_STEP)
    fc_box = pya.Box(0, 0, um(FILL_SIZE), um(FILL_SIZE))

    # Look this far ouside a work region so neighbouring shapes are respected
    halo = um(SNAP_MARGIN + FILL_STEP)

    # Walk the die in TILE x TILE work regions
    bbox = top.bbox()

    x = bbox.left
    while x < bbox.right:

        y = bbox.bottom
        while y < bbox.top:
            tile = pya.Box(x, y, min(x + um(TILE), bbox.right), min(y + um(TILE), bbox.top))

            # Find everything fill must keep out of
            probe = tile.enlarged(halo, halo)
            keep = pya.Region(top.begin_shapes_rec_overlapping(drw, probe))

            if fil is not None:
                keep += pya.Region(top.begin_shapes_rec_overlapping(fil, probe))
            keep += pya.Region(cell.begin_shapes_rec_overlapping(fil_out, probe))

            for b in blockers:
                keep += pya.Region(top.begin_shapes_rec_overlapping(b, probe))

            keep.merge()

            # Free area = work region inside seal ring - (keepouts spacing)
            free = (pya.Region(tile) & inner) - keep.sized(um(SNAP_MARGIN), um(SNAP_MARGIN), 2)

            # Fill the free area with tiles until nothing new can be placed, or PASSES is reached
            for _ in range(PASSES):
                if free.is_empty():
                    break

                # Do the fill of free by tile_cell, in the scratch cell
                scratch.clear_insts()
                scratch.fill_region(
                    free,
                    tile_cell.cell_index(),
                    fc_box,
                    pya.Vector(step, 0),
                    pya.Vector(0, step), None
                )

                # Polygon origins are off-grid, snap them to GRID
                arrays = [snapped(inst.cell_inst) for inst in scratch.each_inst()]
                scratch.clear_insts()
                for a in arrays:
                    scratch.insert(a)

                new = pya.Region(scratch.begin_shapes_rec(fil_out))
                close = new.space_check(step - um(FILL_SIZE))
                dropped = {
                    (p.bbox().left, p.bbox().bottom)
                    for p in new.interacting(pya.Edges([ep.second for ep in close.each()])).each()
                }
                placed = new - pya.Region([pya.Box(l, b, l + um(FILL_SIZE), b + um(FILL_SIZE)) for l, b in dropped])

                # Nothing new placed
                if placed.is_empty():
                    break

                for inst in scratch.each_inst():
                    insert_without(cell, inst.cell_inst, dropped)

                # Remove the new fill+spacing from the free area
                free = free - placed.sized(um(SNAP_MARGIN), um(SNAP_MARGIN), 2)

            y += um(TILE)
        # end while y < bbox.top

        x += um(TILE)
    # end while x < bbox.right

    layout.delete_cell(scratch.cell_index())
    placed_total = cell.child_instances()

    # Place the gap fill once in the top cell
    top.insert(pya.CellInstArray(cell.cell_index(), pya.Trans()))
    print(f"{name} gap fill: {placed_total} tile arrays")


# Gap fill M2 and M4 avoiding nofill, slit and NoMetFiller
for name, layer in [("Met2", 10), ("Met4", 50)]:
    print(f"Start gap fill {name}")
    gap_fill(name, layer, [(layer, 23), (layer, 24), (160, 0)])

layout.write(output_file)  # pylint: disable=undefined-variable
