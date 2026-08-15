#!/bin/bash
# Bring up eth1 (GEM1 over EMIO) on the PYNQ-Z2. Run on the board, after the
# accumulator bitstream is loaded. Idempotent - safe to re-run, and needed
# again after a reboot (the dtbo and SLCR bits don't survive one; the SLCR
# bits do survive a bitstream reload).
#
# Steps: SLCR clock muxes -> EMIO, device-tree overlay -> eth1 appears,
# IP config.
set -euo pipefail

cd "$(dirname "$0")"

devmem() { sudo python3 "$(dirname "$0")/devmem.py" "$@"; }  # image has no devmem binary

echo "== SLCR: route GEM1 tx/rx clocks to EMIO"
devmem 0xF8000008 32 0xDF0D                     # SLCR unlock
devmem 0xF800013C 32 0x00000011                 # GEM1_RCLK_CTRL: CLKACT=1, SRCSEL=EMIO
v=$(devmem 0xF8000144)                          # GEM1_CLK_CTRL
devmem 0xF8000144 32 $(( v | 0x41 ))            # CLKACT=1, SRCSEL=EMIO, keep divisors
# Do NOT relock the SLCR (0xF8000004): the kernel unlocks it once at early
# boot and its clock driver writes APER/GEM clock registers without
# unlocking. Relocking makes those writes silently no-op and macb's probe of
# gem1 fails with -EIO.
echo "   GEM1_RCLK_CTRL=$(devmem 0xF800013C)  GEM1_CLK_CTRL=$(devmem 0xF8000144)"

if ip link show eth1 &>/dev/null; then
  echo "== eth1 already exists, skipping overlay"
else
  echo "== compiling and loading device-tree overlay"
  [ -f gem1-emio.dtbo ] || dtc -@ -I dts -O dtb -o gem1-emio.dtbo gem1-emio.dtso
  sudo mount -t configfs configfs /sys/kernel/config 2>/dev/null || true
  sudo mkdir -p /sys/kernel/config/device-tree/overlays/gem1
  sudo sh -c 'cat gem1-emio.dtbo > /sys/kernel/config/device-tree/overlays/gem1/dtbo'
  sleep 1
  dmesg | grep -i macb | tail -2
fi

echo "== configuring eth1: 10.99.0.1/24"
sudo ip addr replace 10.99.0.1/24 dev eth1
sudo ip link set eth1 up
# Leave checksum offloads ON. The Xilinx kernel patch validates the FCS in
# software whenever RXCSUM is off, but the hardware only keeps the FCS in the
# buffer if RXCSUM was already off when the interface was opened - disabling
# it at runtime makes the driver compare payload bytes against a CRC and drop
# every frame with "incorrect FCS".

echo "== done. The fabric answers at 10.99.0.2 (ARP and UDP only, no ping):"
echo "   ./sender.py 7 35 100"
