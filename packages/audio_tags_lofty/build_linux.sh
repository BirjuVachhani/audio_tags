#!/usr/bin/env bash
#
# Build the prebuilt linux_x64 binary for audio_tags_lofty.
# Run this on an x86_64 Linux machine with Rust installed.
#
# Prerequisites:
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#
# Usage:
#   chmod +x build_linux.sh
#   ./build_linux.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="${SCRIPT_DIR}/src"
OUT_DIR="${SCRIPT_DIR}/prebuilt/linux_x64"

echo "==> Checking prerequisites..."
if ! command -v cargo &>/dev/null; then
  echo "ERROR: cargo is required but not found."
  echo "  Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  exit 1
fi

mkdir -p "${OUT_DIR}"

echo "==> Building lofty_shim (release)..."
cargo build --release --manifest-path "${CRATE_DIR}/Cargo.toml"

OUTPUT="${CRATE_DIR}/target/release/liblofty_shim.so"
if [ ! -f "${OUTPUT}" ]; then
  echo "ERROR: Build succeeded but binary not found at ${OUTPUT}"
  exit 1
fi

cp "${OUTPUT}" "${OUT_DIR}/liblofty_shim.so"
strip "${OUT_DIR}/liblofty_shim.so"

echo "==> Done!"
echo "  Output: ${OUT_DIR}/liblofty_shim.so"
echo "  Size:   $(du -h "${OUT_DIR}/liblofty_shim.so" | awk '{print $1}')"
file "${OUT_DIR}/liblofty_shim.so"
