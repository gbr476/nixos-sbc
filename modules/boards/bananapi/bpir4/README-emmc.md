# BPI-R4 eMMC boot

Boots NixOS on a Banana Pi R4 from the on-board eMMC instead of the SD card.

## What's different from SD

The MTK BROM on MT7988, when its boot-source DIP switches (SW3) select eMMC,
loads BL2 from the **eMMC hardware boot partition** (`/dev/mmcblk0boot0`) —
*not* from a GPT partition in the user data area. So an SD-style single
combined image won't boot from eMMC.

This module produces two artifacts:

- `$out/sd-image/nixos-emmc-BananaPi-BPiR4-v<ver>.raw.zst` — GPT image
  containing two partitions:
  - `fip` (4 MiB at sector 8192)
  - `root` (ext4 rootfs, sector 16384 → end of medium)
- `$out/firmware/bl2.img` — separate BL2, destined for `/dev/mmcblk0boot0`.

It pulls in:

- `mt7988a_bpir4_emmc_defconfig` from **`frank-w/u-boot`** branch `2026-04-bpi`
  (mainline U-Boot only ships the SD defconfig for MT7988).
- ATF built with `BOOT_DEVICE=emmc` from `mtk-openwrt/arm-trusted-firmware`.

## Building

In your consumer flake, set:

```nix
{ ... }: {
  sbc.board.bananapi.bpir4.bootMedium = "emmc";
  # sbc.bootstrap.rootFilesystem defaults to "ext4" when bootMedium=emmc.
}
```

Then:

```bash
nix build .#nixosConfigurations.<host>.config.system.build.sdImage -o result
ls -la result/sd-image/ result/firmware/
```

## Installing onto a board currently booted from SD

```bash
# Copy artifacts to the running board:
scp result/sd-image/nixos-emmc-*.raw.zst result/firmware/bl2.img root@<bpi>:/tmp/

# Then on the board:
echo 0 | sudo tee /sys/block/mmcblk0boot0/force_ro
sudo dd if=/tmp/bl2.img of=/dev/mmcblk0boot0 bs=512 conv=fsync status=progress

zstd -dc /tmp/nixos-emmc-*.raw.zst \
  | sudo dd of=/dev/mmcblk0 bs=4M conv=fsync status=progress
sync
sudo poweroff
```

Then physically flip SW3 from SD to eMMC (consult the silkscreen on your PCB
for the exact switch pattern) and power on.

## Keep the SD card as recovery

The SD device-tree overlay stays enabled in both `bootMedium` modes — flip SW3
back to SD and the original SD-booted NixOS comes up unchanged. Don't wipe the
SD card during bring-up; first eMMC boots frequently need iteration with the
SD as fallback.

## Status

- Vendor kernel (Frank Wunderlich's tree, same as the SD variant).
- MAC addresses still randomize each boot — pin via
  `systemd.network.links` once `ip link` shows the active interface names.
- HW NAT offload (WED/PPE) not enabled in this vendor kernel by default.
