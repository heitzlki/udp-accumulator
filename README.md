# udp-accumulator

A UDP accumulator implemented entirely in the FPGA fabric of a PYNQ-Z2
(Zynq-7020), built with the open-source toolchain - no Vivado.

UDP datagrams carrying one 32-bit number each arrive at the programmable
logic, which adds every number to a running total and answers each datagram
with `{number, total}` - the CPU never touches a packet. Linux on the ARM
side arms and monitors the fabric through memory-mapped registers (the slow
path) while packets flow through fabric-only logic (the fast path) - the
same host/NIC split used in latency-sensitive packet processing, e.g. on
trading FPGAs.

## How it works

No extra hardware is needed. Instead of a physical PHY, the Zynq's second
Ethernet MAC (GEM1) is routed through EMIO into the fabric, where a full
Ethernet/ARP/IPv4/UDP stack terminates it. Linux sees a real `eth1`; its far
end is the accumulator logic. The fabric supplies both GMII clocks, so the
MAC, the stack, the application and the register block all live in a single
25 MHz clock domain with no clock-domain crossings.

```
Linux eth1 10.99.0.1 --GEM1--EMIO GMII--> eth_mac_1g -- udp_complete -- acc_app
      sender.py / listener.py                          (ARP, IP, UDP)     | total += n
      regs.py ----------------M_AXI_GP0 @ 0x4000_0000---------------------+
```

- `main.v` - top level: 125->25 MHz clock divider, power-on reset, the
  GEM-to-MAC crossover wiring, PS7, LEDs, frame counters
- `acc_core.v` - MAC + frame FIFO + Ethernet framers + UDP/IP/ARP stack +
  application; this is the unit the testbench drives
- `acc_app.v` - the application: parse a uint32, accumulate, reply
- `axil_regs.v` - AXI3 slave on M_AXI_GP0 at `0x4000_0000`: control
  (enable, clear-total), totals/counters, and per-stage telemetry
- `ps7_enet.v` - PS7 instance with GEM1's EMIO GMII and M_AXI_GP0 wired out
- `udp_accumulator_tb.v` - Icarus testbench that impersonates GEM1 and
  Linux: hand-built ARP and UDP frames, every FCS checked both ways
- `sw/` - device-tree overlay, board setup script, and host tools
  (`sender.py`, `listener.py`, `regs.py`, `e2e_test.py`, `devmem.py`)

The Ethernet plumbing (MAC, framers, `udp_complete`, FIFOs) is vendored
from [verilog-ethernet](https://github.com/alexforencich/verilog-ethernet)
in `rtl/vendor/veth/` - see acknowledgments below. One file is a local
drop-in replacement: `lfsr.v` computes its CRC masks as precomputed
constants because yosys takes hours evaluating the upstream constant
function (the original is kept as `lfsr.v.upstream`, and the testbench
verifies real CRC32 values end to end).

Two details worth knowing before reading the code:

- Every Zynq bitstream needs a `PS7` instance, even if unused - without one
  the PS-PL interface is unconfigured and Linux freezes the moment the
  bitstream loads.
- `apio.ini` passes `-flatten` to yosys, and it is required: nextpnr-xilinx
  mishandles hierarchical netlists (modules nested two or more levels
  deep), producing designs that simulate perfectly but misbehave on the
  chip.

## Requirements

- PYNQ-Z2 board running the stock PYNQ v3.0.1 image, connected over
  Ethernet (for Linux) and micro-USB (power + JTAG)
- [apio](https://github.com/FPGAwars/apio) with the openXC7 toolchain:
  `pipx install apio && apio packages install`
- `dtc` on the host (`brew install dtc` / `apt install device-tree-compiler`)
  for the device-tree overlay - the PYNQ image doesn't ship it. A compiled
  `gem1-emio.dtbo` is checked in, so this is only needed if you edit the
  overlay.

## Running it

Simulate (no board needed):

```sh
apio test
```

Build and load over USB-JTAG, then set up the Linux side:

```sh
apio upload
scp -r sw xilinx@<board>:udp-accumulator/     # password: xilinx
ssh xilinx@<board>
cd udp-accumulator/sw && sudo ./setup-eth1.sh
```

`setup-eth1.sh` points the GEM1 clock muxes at EMIO (a step the device tree
cannot express), loads the overlay that enables gem1 with a fixed link and
no PHY, and configures `eth1` as 10.99.0.1/24. It is idempotent; re-run it
after every reboot. Then, on the board:

```sh
./listener.py &            # stores {n, total} replies in results.csv
./sender.py 7 35 100       # -> totals 7, 42, 142
sudo ./regs.py             # TOTAL=142, counters, per-stage telemetry
sudo ./regs.py clear       # zero the total from the slow path
sudo python3 e2e_test.py   # 18 checks: overflow, junk input, 1000-burst...
./sender.py --rtt --count 10000
```

Measured round-trip (Linux -> fabric -> Linux, 100 Mb/s over EMIO): median
134 us, p99 179 us, no losses. The latency is dominated by the Linux
network stack; the fabric's share is a few deterministic microseconds.

LEDs: LD0 heartbeat, LD1 blinks on receive, LD2 on reply, LD3 latches on
CRC errors (should stay dark).

There is also a loopback build (`apio upload --env loopback`) that wires
GEM1's transmit straight back to its receive - useful for verifying the
clock topology and SLCR setup independently of the network stack: bring
`eth1` up, send anything, and watch the RX counters track TX in
`ip -s link show eth1`.

## Notes and limits

- `ping 10.99.0.2` never answers: the fabric speaks ARP and UDP only. Use
  `./sender.py` or check `ip neigh` after sending a datagram.
- UDP replies carry checksum 0 ("no checksum", legal in IPv4); the checksum
  generator is disabled - see the note in `acc_core.v`.
- EMIO limits GEM to 10/100. The default build runs 100 Mb/s; for 10 Mb/s
  set `DIV=50` in `clkgen` and `speed = <10>` in the overlay.
- The registers at `0x4000_0000` must only be touched while this bitstream
  is loaded; otherwise the AXI access hangs the CPU hard (power cycle).
- Don't load the bitstream over JTAG while the board is still booting - it
  races the boot-time bitstream load and wedges the board. Wait for SSH.
- Don't toggle `ethtool -K eth1 rx off` at runtime: the Xilinx kernel's
  macb driver then validates the FCS in software against a buffer that no
  longer contains one, and drops every frame.

## Acknowledgments

- [verilog-ethernet](https://github.com/alexforencich/verilog-ethernet) by
  Alex Forencich - the vendored MAC, framers and UDP/IP/ARP stack in
  `rtl/vendor/veth/` (MIT, license text in `rtl/vendor/veth/COPYING`)
- [openXC7](https://github.com/openXC7) - yosys + nextpnr-xilinx flow for
  7-series parts
- [apio](https://github.com/FPGAwars/apio) - toolchain packaging and build
  flow
- [openFPGALoader](https://github.com/trabucayre/openFPGALoader) - USB-JTAG
  programming

## License

MIT - see [LICENSE](LICENSE). The vendored verilog-ethernet sources keep
their own MIT copyright (Alex Forencich).
