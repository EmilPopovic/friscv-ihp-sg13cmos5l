#!/usr/bin/env python3
"""Flatten an RV32 ELF into a $readmemh image for the SRAM preload.

One 32-bit little-endian word per line from --base, where the entry must be.
"""

import argparse
import struct

PT_LOAD = 1


def read_segments(path):
    """(entry, [(vaddr, bytes)]) from an ELF32 little-endian RISC-V file."""
    data = open(path, "rb").read()
    if data[:6] != b"\x7fELF\x01\x01" or struct.unpack_from("<H", data, 18)[0] != 243:
        raise SystemExit(f"{path}: not a little-endian RV32 ELF")

    entry, phoff = struct.unpack_from("<II", data, 24)
    phentsize, phnum = struct.unpack_from("<HH", data, 42)

    segments = []
    for i in range(phnum):
        typ, off, vaddr, _, filesz, memsz = struct.unpack_from(
            "<IIIIII", data, phoff + i * phentsize)
        if typ == PT_LOAD and memsz:
            # .bss occupies memory but not file space
            segments.append((vaddr, data[off:off + filesz] + bytes(memsz - filesz)))
    return entry, segments


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("--base", required=True, type=lambda v: int(v, 0))
    ap.add_argument("--size", required=True, type=lambda v: int(v, 0))
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    entry, segments = read_segments(args.elf)
    if entry != args.base:
        raise SystemExit(f"{args.elf}: entry 0x{entry:08x} is not the reset "
                         f"vector 0x{args.base:08x}")

    image = bytearray(args.size)
    top = 0
    for vaddr, chunk in segments:
        start = vaddr - args.base
        if start < 0 or start + len(chunk) > args.size:
            raise SystemExit(f"{args.elf}: segment at 0x{vaddr:08x} does not fit")
        image[start:start + len(chunk)] = chunk
        top = max(top, start + len(chunk))

    # Trailing words are left out; block RAM is already zero
    with open(args.output, "w") as out:
        for i in range(0, (top + 3) // 4):
            out.write("%08x\n" % struct.unpack_from("<I", image, i * 4))
    print(f"{args.output}: {(top + 3) // 4} words from 0x{args.base:08x}")


if __name__ == "__main__":
    main()
