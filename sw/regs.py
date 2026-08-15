#!/usr/bin/env python3
"""Slow-path access to the accumulator's registers on M_AXI_GP0.

Run as root on the board, only while the accumulator bitstream is loaded
(reading an unmapped 0x4000_0000 hangs the bus).

Usage:
  sudo ./regs.py            # dump registers
  sudo ./regs.py clear      # zero the running total
  sudo ./regs.py disable    # stop responding to datagrams
  sudo ./regs.py enable     # resume
"""
import mmap
import os
import struct
import sys

BASE = 0x4000_0000
CTRL, TOTAL, RX_CNT, TX_CNT = 0x0, 0x4, 0x8, 0xC
GMII, MAC_RX, ERR, STAGE = 0x10, 0x14, 0x18, 0x1C


def main():
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    mem = mmap.mmap(fd, 4096, offset=BASE)

    def rd(off):
        return struct.unpack("<I", mem[off:off + 4])[0]

    def wr(off, val):
        mem[off:off + 4] = struct.pack("<I", val)

    cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
    if cmd == "clear":
        wr(CTRL, (rd(CTRL) & 1) | 2)  # keep enable, pulse clear
        print("total cleared")
    elif cmd == "enable":
        wr(CTRL, 1)
        print("enabled")
    elif cmd == "disable":
        wr(CTRL, 0)
        print("disabled")

    print(f"CTRL   = 0x{rd(CTRL):08x} (enable={rd(CTRL) & 1})")
    print(f"TOTAL  = {rd(TOTAL)}")
    print(f"RX_CNT = {rd(RX_CNT)}")
    print(f"TX_CNT = {rd(TX_CNT)}")
    err, stage = rd(ERR), rd(STAGE)
    print(f"stats: gmii_frames={rd(GMII)} mac_rx={rd(MAC_RX)} "
          f"bad_fcs={err & 0xFFFF} bad_frame={err >> 16} "
          f"to_gem={stage & 0xFFFF}")
    names = ["fifo_v", "fifo_r", "ehdr_v", "ehdr_r", "epay_v", "epay_r",
             "txhdr_v", "txax_v", "txax_r", "macrx_v", "macrx_l", "macrx_bad",
             "udprx_v", "udptx_v"]
    sticky = stage >> 16
    print("sticky:", " ".join(f"{n}={1 if sticky & (1 << i) else 0}"
                              for i, n in enumerate(names)))


if __name__ == "__main__":
    main()
