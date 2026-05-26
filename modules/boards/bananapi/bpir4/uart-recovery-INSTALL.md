# BPI-R4 UART recovery → eMMC install

Files in this bundle:
- `bl2.bin`             — BL2 built with `BOOT_DEVICE=ram` (UART-loadable)
- `fip.bin`             — FIP wrapping BL31 + U-Boot, ready for UART recovery
- `bin/mtk_uartboot`    — MTK BootROM UART loader (third-party Rust port of MTK's protocol)

## What you also need (built separately)

The eMMC artifacts from a `bootMedium = "emmc"` build of the same nixos-sbc:

- `<emmc-result>/firmware/bl2.img`       — destined for `/dev/mmcblk0boot0` (eMMC BL2 with BROM header)
- `<emmc-result>/sd-image/*.raw.zst`     — decompress, write to `/dev/mmcblk0`

## Procedure

Run from your build host (e.g. fire-zfs) with the BPI-R4 connected over its
USB-C console as `/dev/ttyUSB0`.

### 1. Set SW3 to UART download mode

Power off the BPI-R4. Consult the silkscreen on the PCB next to SW3 for the
"UART download" / "BROM" pattern (different from SD, eMMC, NAND, NOR).

### 2. Apply power

The board should be silent on the serial console — no banner, no anything.
BROM is waiting for a UART payload.

### 3. Push BL2 + FIP via UART

```
./bin/mtk_uartboot -s /dev/ttyUSB0 -p bl2.bin --aarch64 -f fip.bin
```

`mtk_uartboot` will:
1. Open `/dev/ttyUSB0` at 460800 baud, do BROM handshake.
2. Push `bl2.bin` into RAM and start it.
3. Re-negotiate to 921600 baud.
4. Push `fip.bin` (BL31 + U-Boot) into RAM, BL2 takes over.

### 4. Attach serial console

In a second terminal (mtk_uartboot keeps `/dev/ttyUSB0` open, so close it
after step 3 completes):

```
tio /dev/ttyUSB0 -b 115200
```

You should land at the U-Boot prompt (`MT7988>` or similar).

### 5. Load eMMC install artifacts into U-Boot

Two paths — pick whichever fits your setup.

#### Option A: TFTP from fire-zfs

On fire-zfs, run a TFTP server in the directory containing your eMMC
artifacts. Easiest with `dnsmasq`:

```
sudo dnsmasq -d --enable-tftp --tftp-root=/path/to/emmc-result \
             --port=0 --no-daemon
```

Then connect the BPI-R4's WAN (or any working ethernet) to your LAN. From
U-Boot:

```
setenv ipaddr 192.168.x.y          # an unused address on your LAN
setenv serverip 192.168.x.z        # fire-zfs's IP
setenv autostart no
tftpboot 0x46000000 firmware/bl2.img    # eMMC variant's BL2 (BROM header included)
```

`${filesize}` after the tftpboot tells you how many bytes were loaded —
keep it in mind for the next step.

#### Option B: USB stick

Format a USB stick as FAT32, copy `bl2.bin` and the decompressed `.raw`
image onto it, plug into the BPI-R4's USB-A port.

```
usb start
fatload usb 0:1 0x46000000 bl2.bin
```

### 6. Write BL2 to the eMMC hardware boot partition

```
mmc dev 0 1                    # switch to /dev/mmcblk0boot0
# bl2.bin is ~250 KB. Round up filesize to whole sectors (512 bytes):
# blocks = (filesize + 511) / 512
# In u-boot, easier: write a generous count.
mmc write 0x46000000 0x0 0x200    # writes 0x200 sectors = 256 KB = enough for BL2
```

### 7. Write the GPT user-area image to mmcblk0

```
mmc dev 0 0                    # back to user area
```

For the decompressed `.raw` image you'd ideally need to load all 1.1 GB
into RAM at once. U-Boot's DRAM is 4 GB so that fits, but loading 1.1 GB
over TFTP is slow. Alternative: split the image into chunks and write
sequentially with offsets. Or boot a small Linux from initramfs via TFTP
and use `dd` there.

The cleanest pragmatic path is Option B with the USB stick — `fatload usb`
streams directly without filling RAM.

### 8. Verify, power off, reboot from eMMC

```
mmc info                       # confirm sizes
gpt verify mmc 0               # confirm GPT
```

Power off. Set SW3 to eMMC. Power on. Watch for BL2 → BL31 → U-Boot →
kernel → NixOS getty.

### If it doesn't boot

- Flip SW3 back to UART download. You can re-enter recovery without
  touching anything else.
- The SD card with the original NixOS image is still untouched — flipping
  SW3 to SD recovers that path.
- Common pitfall: BL2 expects FIP at a specific offset on eMMC (sector
  8192 in our image's GPT). If your image's `fip` partition isn't there,
  BL2 will hang silently.
