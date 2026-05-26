{
  config,
  lib,
  pkgs,
  sbcPkgs,
  ...
}:
# UART recovery bundle for BPI-R4.
#
# Builds the RAM-targeted BL2 + FIP (BOOT_DEVICE=ram) and bundles them with
# mtk_uartboot so the user can run a single `nix build` and end up with a
# directory containing everything needed to push U-Boot into RAM via the
# MTK BootROM's UART download protocol.
#
# Exposed unconditionally as `config.system.build.uartRecovery` — it doesn't
# depend on `bootMedium`, since the *target* of UART recovery is typically a
# blank eMMC that we then install onto from the UART-loaded U-Boot prompt.
{
  config.system.build.uartRecovery = pkgs.runCommandLocal "bpir4-uart-recovery" {
    passthru = {
      inherit (sbcPkgs) mtk_uartboot;
      uboot = sbcPkgs.ubootBananaPiR4Ram;
    };
  } ''
    mkdir -p $out/bin
    cp ${sbcPkgs.ubootBananaPiR4Ram}/bl2.bin  $out/bl2.bin
    cp ${sbcPkgs.ubootBananaPiR4Ram}/fip.bin  $out/fip.bin
    ln -s ${lib.getExe sbcPkgs.mtk_uartboot}  $out/bin/mtk_uartboot

    cp ${./uart-recovery-INSTALL.md}  $out/INSTALL.md
  '';
}
