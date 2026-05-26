{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  systemdLibs,
}:

rustPlatform.buildRustPackage {
  pname = "mtk_uartboot";
  version = "0.1.1-b0ec7bd";

  src = fetchFromGitHub {
    owner = "981213";
    repo = "mtk_uartboot";
    rev = "b0ec7bdf1bab7089df948e745e17d206f3426dc1";
    hash = "sha256-wUF1e0TfP9khfC9WruJkIg4j4DClOJTTPRABIe4Ma4U=";
  };

  cargoHash = "sha256-DtYCSPcyLDYeo9fIQpHGdm5r6ijRAzsDExWcDuSvh/o=";

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
