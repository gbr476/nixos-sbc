# BPI-R4 eMMC boot

Boots NixOS on a Banana Pi R4 from the on-board eMMC, with a USB stick as a
swappable recovery root. No microSD card is involved once provisioned.

## Hardware constraints that shape this (read first)

- **One shared MMC controller.** MT7988A has a single MMC controller
  (`mmc@11230000`) muxed between the SD slot and the eMMC; only one is usable per
  boot, selected by the device tree (which follows SW3). You therefore **cannot**
  access the eMMC while booted from SD, and a single image can't boot both media.
  The board module applies the SD overlay for `bootMedium = "sd"` and the eMMC
  overlay (`mt7988a-bananapi-bpi-r4-emmc.dts`) for `"emmc"` — never both.
- **The BootROM can't boot from USB.** BL2 must live on eMMC (or NAND/SD). USB
  can only supply the kernel + rootfs, via U-Boot.
- **USB is an independent bus.** Unlike SD, USB coexists with the eMMC, so a
  USB-booted system can read/write `/dev/mmcblk0`. That's what makes USB a usable
  recovery + install medium.

## Runtime boot flow (SW3 = eMMC, permanently)

```
BROM ──► BL2 (eMMC boot0) ──► FIP/U-Boot (eMMC "fip" partition) ──► U-Boot
   U-Boot: bootflow scan, bootdev-order = "usb","mmc0"
     ├─ recovery USB present with valid NixOS?  boot it
     └─ otherwise                               boot the eMMC primary OS
```

BL2 + FIP + U-Boot always come from eMMC, even when the USB OS runs (USB only
carries kernel + root). So USB failover covers a broken OS, **not** a corrupted
eMMC bootloader — adding a NAND bootloader later closes that last gap.

## What this module produces

- `$out/sd-image/nixos-emmc-BananaPi-BPiR4-v<ver>.raw.zst` — GPT image with:
  - `fip` (4 MiB at sector 8192) — ATF locates FIP by the partition **name**
    `fip`, so the exact sector is flexible.
  - `root` (ext4 rootfs, sector 16384 → end).
- `$out/firmware/bl2.img` — separate BL2, destined for `/dev/mmcblk0boot0`.

U-Boot/ATF come from `mt7988a_bpir4_emmc_defconfig` (`frank-w/u-boot`) and ATF
`BOOT_DEVICE=emmc` (`mtk-openwrt/arm-trusted-firmware`).

## Building

In your host config:

```nix
{ ... }: {
  sbc.board.bananapi.bpir4.bootMedium = "emmc";
  # rootFilesystem defaults to ext4 when bootMedium = "emmc".
}
```

```bash
# eMMC image (GPT: "fip" partition + ext4 root) and the separate boot0 BL2:
nix build .#nixosConfigurations.<host>.config.system.build.sdImage -o result
ls result/sd-image/ result/firmware/      # *.raw.zst  and  bl2.img

# UART-recovery bundle (RAM U-Boot + mtk_uartboot) for the first install:
nix build .#nixosConfigurations.<host>.config.system.build.uartRecovery -o recovery
```

## Installing onto a blank eMMC

The on-board eMMC ships blank, so the first install needs U-Boot loaded over UART
(the BootROM falls back to UART download when the selected medium has no valid
BL2). See [uart-recovery-INSTALL.md](./uart-recovery-INSTALL.md) for the full
step-by-step. In short:

1. Write the eMMC `*.raw` image to a USB stick — this doubles as your recovery
   stick (it carries the eMMC device tree, so a USB boot can see the eMMC).
2. SW3 → eMMC, connect the USB-C serial console, power on.
3. `mtk_uartboot` pushes RAM U-Boot over serial; it autoboots the USB NixOS.
4. From that USB-booted NixOS, write BL2 → `boot0`, the image → `/dev/mmcblk0`,
   and **enable the boot partition** (`mmc bootpart enable 1 1 /dev/mmcblk0`) —
   the BootROM ignores `boot0` unless this EXT_CSD bit is set.
5. Power off, remove the USB stick, power on → boots from eMMC.

## Recovery later

Keep the USB stick. If the eMMC OS breaks, insert it and power-cycle: U-Boot
prefers USB, so you land in the known-good system, from which you can re-image the
eMMC (`dd` / reinstall to `/dev/mmcblk0`). Pull the stick to go back to eMMC.

## Status / caveats

- Vendor kernel (frank-w 6.12 tree, same as the SD variant).
- MAC addresses randomize each boot — pin via `systemd.network.links` once
  `ip link` shows the active interface names.
- HW NAT offload (WED/PPE) not enabled in this vendor kernel by default.
- A NAND backup bootloader (for bootloader-corruption redundancy) is planned but
  not yet implemented.
