#!/usr/bin/env python3
"""Push an RV32 ELF to the serial bootloader and stream its output.

Needs 'make program' before each load; scripts/load.sh does both.

    uart_load.py prog.elf [--port /dev/ttyUSB0] [--baud 57600]
"""

import argparse
import glob
import os
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from elf2mem import read_segments

LOAD_ADDR = 0x80000000


def default_port():
    """The USB-serial adapter on the RPi header.

    Skips the board's own FT2232, whose UART goes to the unused Zynq PS.
    """
    ports = sorted(p for p in glob.glob("/dev/serial/by-id/*") if "tul" not in p)
    return ports[0] if ports else "/dev/ttyUSB0"


def flatten(elf):
    entry, segments = read_segments(elf)
    if entry != LOAD_ADDR:
        raise SystemExit(f"{elf}: entry 0x{entry:08x}, bootloader jumps to "
                         f"0x{LOAD_ADDR:08x}")
    top = max(v - LOAD_ADDR + len(c) for v, c in segments)
    image = bytearray(top)
    for vaddr, chunk in segments:
        image[vaddr - LOAD_ADDR:vaddr - LOAD_ADDR + len(chunk)] = chunk
    return bytes(image)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("--port", default=default_port())
    ap.add_argument("--baud", type=int, default=57600)
    ap.add_argument("--listen", type=float, default=10.0)
    args = ap.parse_args()

    image = flatten(args.elf)
    frame = (b"FRSV" + struct.pack("<I", len(image)) + image
             + struct.pack("<I", sum(image) & 0xFFFFFFFF))

    try:
        subprocess.run(["stty", "-F", args.port, str(args.baud), "raw", "-echo"],
                       check=True, stderr=subprocess.DEVNULL)
        fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except (OSError, subprocess.CalledProcessError):
        raise SystemExit(f"{args.port}: cannot open, is the adapter plugged in?")
    print(f"sending {len(image)} bytes", file=sys.stderr)

    sent = 0
    while sent < len(frame):
        sent += os.write(fd, frame[sent:sent + 256])
        time.sleep(0.002)   # the loader polls per byte, with no flow control

    seen = b""
    deadline = time.time() + args.listen
    while time.time() < deadline:
        try:
            data = os.read(fd, 256)
        except BlockingIOError:
            time.sleep(0.05)
            continue
        seen += data
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
    os.close(fd)

    # The loader acknowledges before jumping, so silence means it never ran
    if b"OK" not in seen:
        raise SystemExit(f"\n{args.port}: no acknowledgement from the loader")


if __name__ == "__main__":
    main()
