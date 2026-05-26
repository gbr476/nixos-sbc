{
  config,
  lib,
  sbcPkgs,
  ...
}: {
  imports = [
    # Both image modules are imported unconditionally; each one guards its
    # `system.build.sdImage` assignment with `lib.mkIf` on `bootMedium`.
    # Conditional `imports` would force-evaluate `config` before the option is
    # defined, causing infinite recursion.
    ./sd-image-mt7988.nix
    ./emmc-image-mt7988.nix
    # UART recovery bundle is always available (independent of bootMedium) at
    # `config.system.build.uartRecovery` — used for the initial install onto a
    # blank eMMC, since the SD socket and eMMC chip share one MMC controller.
    ./uart-recovery.nix
  ];

  options.sbc.board.bananapi.bpir4 = {
    bootMedium = lib.mkOption {
      type = lib.types.enum ["sd" "emmc"];
      default = "sd";
      description = lib.mdDoc ''
        Selects which boot medium the produced image targets.

        - `sd`: produces a single raw image with BL2 + FIP + rootfs in a GPT
          partition table, intended to be `dd`ed to an SD card.
        - `emmc`: produces a GPT user-area image (FIP + rootfs) plus a separate
          `bl2.img` for the eMMC hardware boot partition (`/dev/mmcblk0boot0`).
          Pulls in an eMMC-specific U-Boot/ATF (frank-w/u-boot defconfig
          `mt7988a_bpir4_emmc_defconfig`, ATF `BOOT_DEVICE=emmc`). Also flips
          the default root filesystem to ext4 for simplicity.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (config.sbc.board.bananapi.bpir4.bootMedium == "emmc") {
      sbc.bootstrap.rootFilesystem = lib.mkDefault "ext4";
      sbc.filesystem.useDefaultLayout = lib.mkDefault "ext4";
    })
    {
      sbc.enable = true;

      sbc.board = {
        vendor = "BananaPi";
        model = "BPiR4";
        dtRoot = "mediatek,mt7988a";

        i2c.devices.i2c0 = {
          status = "okay";
        };

        i2c.devices.i2c1 = {
          status = "disabled";
          enableMethod.dtOverlay = {
            enable = true;
            pinctrl-names = "default";
            # Pins 3, 5
            pinctrl-0 = lib.mkDefault ["i2c1_pins"];
          };
        };

        i2c.devices.i2c2 = {
          status = "okay";
        };

        uart.devices.uart0 = {
          status = "okay";
          baud = 115200;
          deviceName = "ttyS0";
          console = true;
        };

        # uart.devices.uart1 not currently in DT.  GPIO header pins 11, 13.

        rtc.devices.pcf8563 = {
          status = "okay";
          enable = lib.mkDefault false;
          disableMethod.dtOverlay = {
            enable = true;
          };
        };
      };

      # Custom kernel is required as bpi-r4 does not have enough upstream support.
      boot.kernelPackages = sbcPkgs.linuxPackages_frankw_latest_bananaPiR4;

      boot.kernelParams = [
        # keep boot clocks on
        # currently required for boot
        # long-term this should not be needed as the drivers and device tree mature
        "clk_ignore_unused=1"
      ];

      # We exclude a number of modules included in the default list. A non-insignificant amount do
      # not apply to embedded hardware like this, so simply skip the defaults.
      boot.initrd.includeDefaultModules = false;
      boot.initrd.kernelModules = ["mii"];
      boot.initrd.availableKernelModules = ["nvme" "mmc_block"];

      hardware.deviceTree.filter = "mt7988a-bananapi-bpi-r4.dtb";
      # Keep the SD overlay enabled regardless of bootMedium so a flipped SW3
      # can boot from SD as a recovery medium without rebuilding.
      hardware.deviceTree.overlays = [
        {
          name = "BananaPi bpir4 Enable SD card interface";
          dtsFile = ./mt7988a-bananapi-bpi-r4-sd.dts;
        }
      ];
    }
  ];
}
