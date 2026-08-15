#!/usr/bin/env python3
"""Receive {number, running total} replies from the fabric and store them.

Each reply is 8 bytes: uint32 number echoed, uint32 total, big-endian.
Appends one CSV line per reply to results.csv and prints it.
"""
import datetime
import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("10.99.0.1", 5678))
print("listening on 10.99.0.1:5678, writing results.csv")

with open("results.csv", "a") as f:
    while True:
        data, addr = sock.recvfrom(64)
        if len(data) < 8:
            print(f"short datagram from {addr}: {data.hex()}")
            continue
        n, total = struct.unpack("!II", data[:8])
        line = f"{datetime.datetime.now().isoformat()},{n},{total}"
        print(line)
        f.write(line + "\n")
        f.flush()
