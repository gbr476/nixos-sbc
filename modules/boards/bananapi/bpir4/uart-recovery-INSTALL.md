# BPI-R4 UART recovery → eMMC install

First-time install of NixOS onto a **blank** BPI-R4 eMMC. The on-board eMMC has
no bootloader, so we load U-Boot into RAM over the serial console, boot a NixOS
from a USB stick, and write the eMMC from that running system. The microSD slot
is never used (it shares the MMC controller with the eMMC — see
[README-emmc.md](./README-emmc.md)).

## What you need

From this UART-recovery bundle (`system.build.uartRecovery`):
- `bl2.bin`          — BL2 built `BOOT_DEVICE=ram` (UART-loadable, no BROM header)
- `fip.bin`          — FIP (BL31 + U-Boot) for UART recovery
- `bin/mtk_uartboot` — MTK BootROM UART loader

From a `bootMedium = "emmc"` build (`system.build.sdImage`):
- `firmware/bl2.img`     — eMMC BL2 (BROM header) → goes to `/dev/mmcblk0boot0`
- `sd-image/*.raw.zst`   — the GPT image (FIP partition + ext4 root)

Plus: a USB stick, the USB-C serial console wired to the host (e.g.
`/dev/ttyUSB0`), and an ethernet cable if you want to copy artifacts over the
network instead of staging them on the stick.

## Prepare the USB recovery stick (on your host)

Write the eMMC image straight to the stick — it is bootable (it carries the eMMC
device tree) and becomes your permanent recovery medium:

```bash
zstd -dc result/sd-image/nixos-emmc-*.raw.zst \
  | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress   # sdX = your USB stick
sync
```

Also copy the two install artifacts somewhere the booted NixOS can read them —
simplest is a small extra FAT partition on the same stick, or just `scp` them
over the network in step 5:

```bash
# bl2.img (boot0 BL2) and the raw image, for writing to eMMC later
cp result/firmware/bl2.img /path/to/fat/
zstd -dc result/sd-image/nixos-emmc-*.raw.zst > /path/to/fat/emmc.raw
```

## 1. Set SW3 to eMMC and power on

SW3 = eMMC (per frank-w's wiki, "down = 1": A=1, B=0 — confirm against your
board's silkscreen / revision). Because the eMMC is blank, the BootROM finds no
valid BL2 and drops into UART download mode — the serial console stays silent.
(If your board doesn't auto-fall-back, use the dedicated UART/BROM SW3 position.)

## 2. Push RAM U-Boot over UART

```bash
./bin/mtk_uartboot -s /dev/ttyUSB0 -p bl2.bin --aarch64 -f fip.bin
```

It handshakes with the BROM, loads `bl2.bin` then `fip.bin` into RAM, and BL2
starts U-Boot. Attach a console (mtk_uartboot may release the port when done):

```bash
tio /dev/ttyUSB0 -b 115200
```

## 3. Boot the USB NixOS

With the stick inserted, U-Boot's `bootflow scan` (bootdev-order `usb`,`mmc0`)
finds the USB NixOS and boots it (the blank eMMC is skipped). If it doesn't
autoboot, interrupt U-Boot and run `bootflow scan -lb`. Log in over serial.

> Why this works: USB is a separate bus from the MMC controller, so the
> USB-booted system can see and write `/dev/mmcblk0` (the eMMC) directly.

## 4. Write the eMMC from the running NixOS

Make `bl2.img` and the raw image available (mount the FAT partition, or `scp`
them from your host). Then:

```bash
# 4a. BL2 → eMMC hardware boot partition (boot0)
echo 0 | sudo tee /sys/block/mmcblk0boot0/force_ro
sudo dd if=bl2.img of=/dev/mmcblk0boot0 bs=512 conv=fsync status=progress

# 4b. GPT image (FIP partition + rootfs) → user area
sudo dd if=emmc.raw of=/dev/mmcblk0 bs=4M conv=fsync status=progress
#   (equivalently, clone the stick: dd if=/dev/sda of=/dev/mmcblk0 ...)

# 4c. MANDATORY: enable the eMMC boot partition in EXT_CSD.
#     boot_ack=1, boot_partition=1 (boot0). Without this the BootROM will NOT
#     read BL2 from boot0 and the board stays silent.
sudo mmc bootpart enable 1 1 /dev/mmcblk0

sync
sudo poweroff
```

## 5. Boot from eMMC

Remove the USB stick, leave SW3 on eMMC, power on. Watch the serial console for
`BL2 → BL31 → U-Boot → kernel → NixOS getty`. Keep the USB stick — it's now your
recovery medium (insert + power-cycle to boot it again).

## Troubleshooting

- **Board silent after step 5 / won't reach U-Boot from eMMC.** Almost always a
  missing step 4c (`mmc bootpart enable 1 1`), or BL2 not actually at `boot0`
  offset 0. Re-enter UART recovery (steps 1–2) — it works regardless of eMMC
  state — boot the USB NixOS, and redo 4a/4c.
- **U-Boot comes up but no rootfs / kernel panic.** Confirm the eMMC overlay is
  applied (the kernel must see an 8-bit `non-removable` mmc, not an SD card). The
  build selects it automatically for `bootMedium = "emmc"`.
- **BL2 reached but hangs before U-Boot.** ATF locates FIP by the GPT partition
  named `fip`; make sure the image was written whole (step 4b) so that partition
  exists.
- **Need a clean redo.** UART recovery never depends on what's on the eMMC, so
  you can always get back to a U-Boot prompt this way.
