#!/usr/bin/env bash
#
# Build the prebuilt macOS shim binaries for audio_tags_lofty.
# Produces liblofty_shim.dylib for arm64 and/or x86_64.
#
# Prerequisites:
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#
# Usage:
#   chmod +x build_macos.sh
#   ./build_macos.sh             # builds arm64 + x86_64
#   ./build_macos.sh arm64       # builds only arm64
#   ./build_macos.sh x86_64      # builds only x86_64
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="${SCRIPT_DIR}/src"

ARCHS=()
if [ $# -eq 0 ]; then
  ARCHS=("arm64" "x86_64")
else
  ARCHS=("$@")
fi

if ! command -v cargo &>/dev/null; then
  echo "ERROR: cargo is required but not found."
  echo "  Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  exit 1
fi

for ARCH in "${ARCHS[@]}"; do
  case "${ARCH}" in
    arm64)
      TRIPLE="aarch64-apple-darwin"
      OUT_KEY="macos_arm64"
      ;;
    x86_64)
      TRIPLE="x86_64-apple-darwin"
      OUT_KEY="macos_x64"
      ;;
    *)
      echo "ERROR: unknown arch '${ARCH}'. Use arm64 or x86_64."
      exit 1
      ;;
  esac

  OUT_DIR="${SCRIPT_DIR}/prebuilt/${OUT_KEY}"
  mkdir -p "${OUT_DIR}"

  echo ""
  echo "==> Adding rustc target ${TRIPLE} (if missing)..."
  rustup target add "${TRIPLE}"

  echo "==> Building lofty_shim for ${TRIPLE} (release)..."
  RUSTFLAGS="-C link-arg=-Wl,-headerpad_max_install_names" \
    cargo build --release --manifest-path "${CRATE_DIR}/Cargo.toml" --target "${TRIPLE}"

  SRC_BIN="${CRATE_DIR}/target/${TRIPLE}/release/liblofty_shim.dylib"
  if [ ! -f "${SRC_BIN}" ]; then
    echo "ERROR: Build succeeded but binary not found at ${SRC_BIN}"
    exit 1
  fi

  cp "${SRC_BIN}" "${OUT_DIR}/liblofty_shim.dylib"
  strip -x "${OUT_DIR}/liblofty_shim.dylib" || true

  echo "==> Done!"
  echo "  Output: ${OUT_DIR}/liblofty_shim.dylib"
  echo "  Size:   $(du -h "${OUT_DIR}/liblofty_shim.dylib" | awk '{print $1}')"
  file "${OUT_DIR}/liblofty_shim.dylib"
done

echo ""
echo "All architectures built successfully."
