{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  systemdLibs,
  runCommand,
  callPackage,
  path,
}: let
  src = fetchFromGitHub {
    owner = "981213";
    repo = "mtk_uartboot";
    rev = "b0ec7bdf1bab7089df948e745e17d206f3426dc1";
    hash = "sha256-wUF1e0TfP9khfC9WruJkIg4j4DClOJTTPRABIe4Ma4U=";
  };

  # crates.io now returns 403 for requests sent with a default library
  # User-Agent (python-requests, curl, ...). nixpkgs' fetchCargoVendor fetches
  # crates with python-requests, so vendoring fails here. Patch just that
  # fetcher to send a UA crates.io accepts (cargo's). The vendored *output* is
  # byte-identical, so `cargoHash` below is unchanged. If a future nixpkgs sets
  # its own UA, the sed simply no-ops and this can be dropped.
  patchedFetchCargoVendor = let
    patchedDir = runCommand "patched-fetch-cargo-vendor" {} ''
      mkdir -p $out
      cp ${path}/pkgs/build-support/rust/fetch-cargo-vendor.nix $out/default.nix
      cp ${path}/pkgs/build-support/rust/replace-workspace-values.py $out/
      sed 's@session = requests.Session()@&\n    session.headers.update({"User-Agent": "cargo 1.82 (nixpkgs fetchCargoVendor)"})@' \
        ${path}/pkgs/build-support/rust/fetch-cargo-vendor-util.py > $out/fetch-cargo-vendor-util.py
    '';
  in
    callPackage "${patchedDir}/default.nix" {};
in
  rustPlatform.buildRustPackage {
    pname = "mtk_uartboot";
    version = "0.1.1-b0ec7bd";
    inherit src;

    cargoDeps = patchedFetchCargoVendor {
      name = "mtk_uartboot-0.1.1-b0ec7bd-vendor";
      inherit src;
      hash = "sha256-DtYCSPcyLDYeo9fIQpHGdm5r6ijRAzsDExWcDuSvh/o=";
    };

    nativeBuildInputs = [pkg-config];
    # serialport crate needs libudev on Linux.
    buildInputs = [systemdLibs];

    meta = {
      description = "Third-party MTK BootROM UART recovery tool";
      homepage = "https://github.com/981213/mtk_uartboot";
      license = lib.licenses.agpl3Only;
      mainProgram = "mtk_uartboot";
      platforms = lib.platforms.linux;
    };
  }
