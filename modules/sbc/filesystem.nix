{
  config,
  lib,
  ...
}: let
  cfg = config.sbc.filesystem;
in {
  options.sbc.filesystem = with lib; {
    useDefaultLayout = mkOption {
      type = types.enum ["btrfs-subvol" "btrfs" "ext4" false];
      description = mdDoc ''
        When a pre-built SD image is used, the filesystem layout will be
        known to us, so by enabling the use of the default layout you do
        not need to specify it yourself.

        Options are false, "btrfs-subvol" "btrfs" or "ext4".
      '';
    };

    rootUUID = mkOption {
      type = types.str;
      default =
        if cfg.useDefaultLayout == "ext4"
        then "0b5e3376-c7e9-4284-9514-9c3b51244f19"
        else "18db6211-ac36-42c1-a22f-5e15e1486e0d";
      defaultText = literalMD "the layout's historical fixed UUID";
      description = mdDoc ''
        UUID stamped on the default-layout root filesystem and referenced by
        `fileSystems."/".device`. It is deliberately fixed (deterministic) so
        the prebuilt image's `fileSystems` matches the bytes on disk.

        Override it when building a SECOND image that may be present alongside
        the primary install — most importantly a USB recovery medium for a
        board that boots from eMMC. Both images otherwise share this UUID, so
        `root=…by-uuid/<this>` resolves to whichever disk enumerates first
        (the eMMC), and the recovery USB can't override a broken eMMC root.
        Give the recovery image a distinct `rootUUID` and each medium's initrd
        mounts only its own root.
      '';
    };
  };

  config = lib.mkMerge [
    {
      sbc.filesystem.useDefaultLayout = lib.mkDefault (
        if config.sbc.bootstrap.enable
        then config.sbc.bootstrap.rootFilesystem
        else false
      );
    }
    (lib.mkIf (config.sbc.enable && cfg.useDefaultLayout == "btrfs-subvol") {
      assertions = [
        {
          assertion = builtins.all (fs: (fs.device == "/dev/disk/by-uuid/${cfg.rootUUID}") -> !(builtins.any (opt: lib.hasPrefix "subvolid=" opt) fs.options)) config.system.build.fileSystems;
          message = "subvolid is not idempotent, can't reproduce, refusing to build";
        }
      ];

      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/${cfg.rootUUID}";
          fsType = "btrfs";
          options = ["compress=zstd" "subvol=/@"];
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/${cfg.rootUUID}";
          fsType = "btrfs";
          options = ["compress=zstd" "subvol=/@boot"];
        };
        "/nix" = {
          device = "/dev/disk/by-uuid/${cfg.rootUUID}";
          fsType = "btrfs";
          options = ["compress=zstd" "subvol=/@nix"];
        };
      };
    })
    (lib.mkIf (config.sbc.enable && cfg.useDefaultLayout == "btrfs") {
      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/${cfg.rootUUID}";
          fsType = "btrfs";
          options = ["compress=zstd"];
        };
      };
    })
    (lib.mkIf (config.sbc.enable && cfg.useDefaultLayout == "ext4") {
      fileSystems = {
        "/" = {
          device = "/dev/disk/by-uuid/${cfg.rootUUID}";
          fsType = "ext4";
        };
      };
    })
  ];
}
