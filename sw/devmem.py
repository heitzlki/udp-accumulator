#!/usr/bin/env python3
"""Minimal devmem replacement - the PYNQ v3.0.1 image ships neither devmem
nor busybox. Same argument order as the real one:

  devmem.py ADDR            # read 32-bit, prints 0xXXXXXXXX
  devmem.py ADDR 32 VALUE   # write 32-bit

Addresses and values in hex (0x...) or decimal. Root required (/dev/mem).
"""
import mmap
import os
import struct
import sys

addr = int(sys.argv[1], 0)
page = addr & ~0xFFF
off = addr - page
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mem = mmap.mmap(fd, 4096, offset=page)
if len(sys.argv) > 3:
    mem[off:off + 4] = struct.pack("<I", int(sys.argv[3], 0) & 0xFFFFFFFF)
print(f"0x{struct.unpack('<I', mem[off:off + 4])[0]:08X}")
