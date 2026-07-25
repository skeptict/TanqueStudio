#!/usr/bin/env python3
"""Decode resolution_dependent_shift from a Draw Things history DB.

Mirrors FBReader in DrawThingsStudio/DTProjectDatabase.swift exactly:
root offset at 0, vtable at tablePos - int32(tablePos), size = uint16(vtablePos).
Reads both the old (146) and new (182) vtable slots so they can be compared.
"""
import sqlite3, struct, sys, collections

OLD_SLOT = 146   # decoding_tile_width  (ushort)
NEW_SLOT = 182   # resolution_dependent_shift (bool)
SHIFT_SLOT = 136 # shift (float) -- known-good control

def root_table(b):
    if len(b) < 8: return None
    (root,) = struct.unpack_from('<I', b, 0)
    tp = root
    if tp + 4 > len(b): return None
    (rel,) = struct.unpack_from('<i', b, tp)
    vp = tp - rel
    if vp < 0 or vp + 4 > len(b): return None
    (vsize,) = struct.unpack_from('<H', b, vp)
    if vp + vsize > len(b): return None
    return tp, vp, vsize

def foff(b, vp, vsize, slot):
    if slot < 0 or slot + 2 > vsize: return None
    (off,) = struct.unpack_from('<H', b, vp + slot)
    return None if off == 0 else off

def main(path, limit=600):
    con = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
    rows = con.execute(
        "SELECT rowid, p FROM tensorhistorynode ORDER BY rowid DESC LIMIT ?", (limit,)
    ).fetchall()

    vsizes = collections.Counter()
    old_present = new_present = 0
    old_vals = collections.Counter()
    new_vals = collections.Counter()
    old_decoded = collections.Counter()   # what the buggy reader reported (with ?? true)
    new_decoded = collections.Counter()   # what the fixed reader reports (with ?? true)
    samples = []

    for rowid, blob in rows:
        b = bytes(blob)
        rt = root_table(b)
        if rt is None:
            continue
        tp, vp, vsize = rt
        vsizes[vsize] += 1

        o = foff(b, vp, vsize, OLD_SLOT)
        n = foff(b, vp, vsize, NEW_SLOT)
        s = foff(b, vp, vsize, SHIFT_SLOT)

        # buggy path: readUInt8 at slot 146 (a ushort field) != 0, else default true
        if o is not None:
            old_present += 1
            old_vals[struct.unpack_from('<H', b, tp + o)[0]] += 1
            old_decoded[b[tp + o] != 0] += 1
        else:
            old_decoded[True] += 1

        if n is not None:
            new_present += 1
            new_vals[b[tp + n]] += 1
            new_decoded[b[tp + n] != 0] += 1
        else:
            new_decoded[True] += 1

        shift = struct.unpack_from('<f', b, tp + s)[0] if s is not None else 1.0
        if len(samples) < 12:
            samples.append((rowid, vsize,
                            'absent' if o is None else struct.unpack_from('<H', b, tp+o)[0],
                            'absent' if n is None else b[tp+n],
                            round(shift, 4)))

    print(f"rows decoded: {sum(vsizes.values())} / {len(rows)}")
    print(f"vtable sizes: {dict(vsizes)}")
    print()
    print(f"slot {OLD_SLOT} (decoding_tile_width) present in {old_present} rows; raw ushort values: {dict(old_vals)}")
    print(f"slot {NEW_SLOT} (resolution_dependent_shift) present in {new_present} rows; raw byte values: {dict(new_vals)}")
    print()
    print(f"OLD reader reported resolutionDependentShift: {dict(old_decoded)}")
    print(f"NEW reader reports  resolutionDependentShift: {dict(new_decoded)}")
    print()
    print(f"{'rowid':>8} {'vtsz':>5} {'@146':>8} {'@182':>8} {'shift':>8}")
    for r in samples:
        print(f"{r[0]:>8} {r[1]:>5} {str(r[2]):>8} {str(r[3]):>8} {r[4]:>8}")

if __name__ == '__main__':
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 600)
