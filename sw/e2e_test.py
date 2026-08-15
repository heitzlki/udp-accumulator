#!/usr/bin/env python3
"""End-to-end + edge-case test for the fabric accumulator. Run on the board.

Sends datagrams to the fabric at 10.99.0.2:1234, listens for {n, total}
replies on 10.99.0.1:5678, and cross-checks the memory-mapped registers.
Needs root only for the register checks (invokes regs.py via sudo -n or
plain if already root).
"""
import socket
import struct
import subprocess
import sys
import time

FPGA = ("10.99.0.2", 1234)
M32 = 0xFFFFFFFF

tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.bind(("10.99.0.1", 5678))
rx.settimeout(1.0)

passed = failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS {name} {detail}")
    else:
        failed += 1
        print(f"  FAIL {name} {detail}")


def drain():
    rx.settimeout(0.2)
    try:
        while True:
            rx.recvfrom(64)
    except socket.timeout:
        pass
    rx.settimeout(1.0)


def send_raw(payload):
    tx.sendto(payload, FPGA)


def send_num(n):
    send_raw(struct.pack("!I", n & M32))


def recv_reply():
    try:
        data, addr = rx.recvfrom(64)
        if len(data) >= 8:
            return struct.unpack("!II", data[:8])
        return ("short", data.hex())
    except socket.timeout:
        return None


def regs():
    out = subprocess.run(["python3", "regs.py"], capture_output=True, text=True).stdout
    d = {}
    for line in out.splitlines():
        if "=" in line and not line.startswith(("sticky", "DBG", "capture")):
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip().split()[0]
    return d


def clear_total():
    subprocess.run(["python3", "regs.py", "clear"], capture_output=True)
    time.sleep(0.1)


print("== 1. basic accumulation: 7, 35, 100 -> totals 7, 42, 142")
clear_total()
drain()
expect_total = 0
for n in (7, 35, 100):
    send_num(n)
    r = recv_reply()
    expect_total = (expect_total + n) & M32
    check(f"send {n}", r == (n, expect_total), f"got {r}, want {(n, expect_total)}")

print("== 2. registers agree")
d = regs()
check("TOTAL==142", d.get("TOTAL") == "142", d.get("TOTAL"))

print("== 3. zero")
send_num(0)
r = recv_reply()
check("send 0", r == (0, 142), f"got {r}")

print("== 4. overflow wraps modulo 2^32")
clear_total()
drain()
send_num(0xFFFFFFFF)
r = recv_reply()
check("send 2^32-1", r == (0xFFFFFFFF, 0xFFFFFFFF), f"got {r}")
send_num(5)
r = recv_reply()
check("wrap: +5 -> 4", r == (5, 4), f"got {r}")
send_num(0xFFFFFFFF)
r = recv_reply()
check("wrap again: -1 -> 3", r == (0xFFFFFFFF, 3), f"got {r}")
d = regs()
check("TOTAL==3 in regs", d.get("TOTAL") == "3", d.get("TOTAL"))

print("== 5. junk input never wedges the pipeline")
clear_total()
drain()
send_raw(b"")                    # empty datagram
send_raw(b"\x01")                # 1 byte
send_raw(b"\x00\x01")            # 2 bytes
send_raw(b"A" * 100)             # oversized, first 4 bytes = 0x41414141
time.sleep(0.5)
drain()
send_num(9)                      # pipeline must still respond
r = recv_reply()
check("alive after junk", r is not None and r[0] == 9, f"got {r}")

print("== 6. wrong port is ignored")
clear_total()
drain()
before = regs().get("RX_CNT")
tx.sendto(struct.pack("!I", 77), ("10.99.0.2", 9999))
time.sleep(0.3)
r = recv_reply()
after = regs().get("RX_CNT")
check("no reply", r is None, f"got {r}")
check("RX_CNT unchanged", before == after, f"{before} -> {after}")

print("== 7. enable/disable from the slow path")
subprocess.run(["python3", "regs.py", "disable"], capture_output=True)
drain()
send_num(50)
r = recv_reply()
check("disabled: no reply", r is None, f"got {r}")
subprocess.run(["python3", "regs.py", "enable"], capture_output=True)
send_num(50)
r = recv_reply()
check("re-enabled: replies", r is not None and r[0] == 50, f"got {r}")

print("== 8. burst: 1000 datagrams, every reply correct")
clear_total()
drain()
rx.settimeout(2.0)
total = 0
got = 0
mismatches = 0
for i in range(1, 1001):
    send_num(i)
    r = recv_reply()
    if r is None:
        continue
    got += 1
    total = (total + i) & M32
    if r != (i, total):
        mismatches += 1
check("1000/1000 replies", got == 1000, f"{got}/1000")
check("all totals correct", mismatches == 0, f"{mismatches} mismatches")
d = regs()
check("TOTAL==500500", d.get("TOTAL") == "500500", d.get("TOTAL"))
check("RX==TX==1000+", d.get("RX_CNT") == d.get("TX_CNT"),
      f"rx={d.get('RX_CNT')} tx={d.get('TX_CNT')}")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
