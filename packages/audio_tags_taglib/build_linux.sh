#!/usr/bin/env bash
#
# Build the prebuilt linux_x64 binary for audio_metadata.
# Run this on an x86_64 Linux machine.
#
# Prerequisites:
#   sudo apt install build-essential cmake curl
#
# Usage:
#   chmod +x build_linux.sh
#   ./build_linux.sh
#
set -euo pipefail

TAGLIB_VERSION="2.2.1"
TAGLIB_URL="https://taglib.github.io/releases/taglib-${TAGLIB_VERSION}.tar.gz"
TAGLIB_SHA256="7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/taglib_linux_build"
INSTALL_DIR="${BUILD_DIR}/install"
OUT_DIR="${SCRIPT_DIR}/prebuilt/linux_x64"

echo "==> Checking prerequisites..."
for cmd in cmake g++ curl sha256sum strip; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not found."
    echo "  sudo apt install build-essential cmake curl coreutils"
    exit 1
  fi
done

mkdir -p "${BUILD_DIR}" "${OUT_DIR}"

# ── Download TagLib source ──────────────────────────────────────────────────

TARBALL="${BUILD_DIR}/taglib-${TAGLIB_VERSION}.tar.gz"
if [ ! -f "${TARBALL}" ]; then
  echo "==> Downloading TagLib ${TAGLIB_VERSION}..."
  curl -fsSL -o "${TARBALL}" "${TAGLIB_URL}"
fi

echo "==> Verifying checksum..."
ACTUAL_SHA=$(sha256sum "${TARBALL}" | awk '{print $1}')
if [ "${ACTUAL_SHA}" != "${TAGLIB_SHA256}" ]; then
  echo "ERROR: Checksum mismatch!"
  echo "  Expected: ${TAGLIB_SHA256}"
  echo "  Got:      ${ACTUAL_SHA}"
  rm -f "${TARBALL}"
  exit 1
fi

# ── Extract ─────────────────────────────────────────────────────────────────

SRC_DIR="${BUILD_DIR}/taglib-${TAGLIB_VERSION}"
if [ ! -d "${SRC_DIR}" ]; then
  echo "==> Extracting..."
  tar xzf "${TARBALL}" -C "${BUILD_DIR}"
fi

# ── Build TagLib as a static library ────────────────────────────────────────

CMAKE_BUILD="${BUILD_DIR}/cmake_build"
if [ ! -f "${INSTALL_DIR}/lib/libtag.a" ]; then
  echo "==> Configuring TagLib with CMake..."
  cmake -S "${SRC_DIR}" -B "${CMAKE_BUILD}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DWITH_MP4=ON \
    -DWITH_ASF=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_BINDINGS=OFF

  echo "==> Building TagLib..."
  cmake --build "${CMAKE_BUILD}" --config Release --parallel "$(nproc)"

  echo "==> Installing TagLib..."
  cmake --install "${CMAKE_BUILD}"
else
  echo "==> TagLib already built at ${INSTALL_DIR}"
fi

# ── Compile the shim ────────────────────────────────────────────────────────

OUTPUT="${OUT_DIR}/libtaglib_shim.so"
echo "==> Compiling taglib_shim (TagLib ${TAGLIB_VERSION})..."
g++ -std=c++17 -fPIC -shared -O2 \
  -DSHIM_TAGLIB_VERSION="${TAGLIB_VERSION}" \
  -I"${INSTALL_DIR}/include" \
  "${SCRIPT_DIR}/src/taglib_shim.cpp" \
  "${INSTALL_DIR}/lib/libtag.a" \
  -lz \
  -o "${OUTPUT}"

strip "${OUTPUT}"

echo "==> Done!"
echo "  Output: ${OUTPUT}"
echo "  Size:   $(du -h "${OUTPUT}" | awk '{print $1}')"
file "${OUTPUT}"
