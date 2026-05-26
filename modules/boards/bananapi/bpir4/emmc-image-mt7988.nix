{
  config,
  lib,
  pkgs,
  sbcPkgs,
  ...
}:
# eMMC variant of the BPI-R4 boot image.
#
# Unlike SD (where BL2 + FIP + rootfs all live on a single GPT-partitioned
# medium), eMMC boot on MT7988 requires BL2 in the eMMC hardware boot partition
# (/dev/mmcblk0boot0) — the MTK BROM looks there, not in the user-data area.
#
# So we produce TWO outputs:
#   - $out/sd-image/<name>.raw[.zst]  : GPT user-area image (FIP + ext4 rootfs)
#   - $out/firmware/bl2.img           : separate BL2 for writing to boot0
#
# The "sd-image" path is reused for the user-area image to stay compatible with
# nixos-sbc's existing sdImage attribute consumers; an install script writes it
# to /dev/mmcblk0 while writing bl2.img to /dev/mmcblk0boot0.
{
  config = lib.mkIf (config.sbc.board.bananapi.bpir4.bootMedium == "emmc") {
  system.build.sdImage = pkgs.callPackage (
    {
      stdenv,
      e2fsprogs,
      gptfdisk,
      util-linux,
      uboot,
      zstd,
    }: let
      name = "nixos-emmc-${config.sbc.board.vendor}-${config.sbc.board.model}";
      compress = true;
      imageName = "${name}-v${config.sbc.version}.raw";
    in
      stdenv.mkDerivation {
        inherit name;
        nativeBuildInputs = [
          e2fsprogs
          gptfdisk
          util-linux
          zstd
        ];
        buildInputs = [uboot];

        buildCommand = ''
          root_fs=${config.system.build.rootfsImage}

          mkdir -p $out/nix-support $out/sd-image $out/firmware
          export img=$out/sd-image/${imageName}

          # Expose BL2 as a separate artifact for the install flow to write to
          # /dev/mmcblk0boot0 (the eMMC hardware boot partition).
          cp ${uboot}/bl2.img $out/firmware/bl2.img

          echo "${pkgs.stdenv.buildPlatform.system}" > $out/nix-support/system
          echo "file sd-image $img${
            if compress
            then ".zst"
            else ""
          }" >> $out/nix-support/hydra-build-products
          echo "file bl2 $out/firmware/bl2.img" >> $out/nix-support/hydra-build-products

          ## Sector Math
          # No BL2 partition in the user area — BL2 lives in boot0.
          # FIP partition kept at the same offset as the SD layout for parity
          # with BL2's expectations (FIP partition labelled "fip" on GPT).
          fipStart=8192
          fipEnd=16383

          rootSizeBlocks=$(du -B 512 --apparent-size $root_fs | awk '{ print $1 }')
          rootPartStart=$((fipEnd + 1))
          rootPartEnd=$((rootPartStart + rootSizeBlocks - 1))

          # Last 100 sectors is being lazy about GPT backup (should be 36).
          imageSize=$((rootPartEnd + 100))
          imageSizeB=$((imageSize * 512))

          truncate -s $imageSizeB $img

          sgdisk -o \
          --set-alignment=2 \
          -n 1:$fipStart:$fipEnd -c 1:fip \
          -n 2:$rootPartStart:$rootPartEnd -c 2:root -A 2:set:2 \
          $img

          # Copy FIP and rootfs into the user-area image. BL2 is NOT included
          # here — see $out/firmware/bl2.img above.
          dd conv=notrunc if=${uboot}/fip.bin of=$img seek=$fipStart
          dd conv=notrunc if=$root_fs of=$img seek=$rootPartStart

          if [ ${builtins.toString compress} = 1 ]; then
            zstd --rm -T$NIX_BUILD_CORES -19 $img
          fi
        '';
      }
  ) {uboot = sbcPkgs.ubootBananaPiR4Emmc;};
  };
}
