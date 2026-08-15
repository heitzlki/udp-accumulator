#!/usr/bin/env python3
"""Send numbers to the fabric accumulator as UDP datagrams (one uint32 each).

Usage:
  ./sender.py 7 35 100            # send these numbers
  ./sender.py --rtt --count 1000  # latency test: send 1, await each reply
"""
import argparse
import socket
import statistics
import struct
import time

FPGA = ("10.99.0.2", 1234)
REPLY_PORT = 5678


def main():
    p = argparse.ArgumentParser()
    p.add_argument("numbers", nargs="*", type=int, help="numbers to send")
    p.add_argument("--rtt", action="store_true", help="round-trip latency test")
    p.add_argument("--count", type=int, default=1000, help="datagrams for --rtt")
    args = p.parse_args()

    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    if args.rtt:
        rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        rx.bind(("10.99.0.1", REPLY_PORT))
        rx.settimeout(1.0)
        lat = []
        lost = 0
        for i in range(args.count):
            t0 = time.perf_counter_ns()
            tx.sendto(struct.pack("!I", 1), FPGA)
            try:
                rx.recvfrom(64)
                lat.append((time.perf_counter_ns() - t0) / 1000)
            except socket.timeout:
                lost += 1
        lat.sort()
        print(f"{len(lat)} replies, {lost} lost")
        if lat:
            print(f"rtt us: min {lat[0]:.1f}  median {statistics.median(lat):.1f}  "
                  f"p99 {lat[int(len(lat) * 0.99) - 1]:.1f}  max {lat[-1]:.1f}")
        return

    if not args.numbers:
        p.error("give numbers to send, or --rtt")
    for n in args.numbers:
        tx.sendto(struct.pack("!I", n & 0xFFFFFFFF), FPGA)
        print(f"sent {n}")
        time.sleep(0.01)


if __name__ == "__main__":
    main()
