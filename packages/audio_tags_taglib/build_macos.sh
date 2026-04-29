#!/usr/bin/env bash
#
# Build the prebuilt macOS shim binaries for audio_tags_taglib.
# Produces statically-linked libtaglib_shim.dylib for both arm64 and x86_64.
#
# Run on a macOS machine with Homebrew, CMake, and Clang installed.
#
#   brew install cmake
#
# Usage:
#   chmod +x build_macos.sh
#   ./build_macos.sh             # builds arm64 + x86_64
#   ./build_macos.sh arm64       # builds only arm64
#   ./build_macos.sh x86_64      # builds only x86_64
#
set -euo pipefail

TAGLIB_VERSION="2.2.1"
TAGLIB_URL="https://taglib.github.io/releases/taglib-${TAGLIB_VERSION}.tar.gz"
TAGLIB_SHA256="7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHIM_SRC="${SCRIPT_DIR}/src/taglib_shim.cpp"

ARCHS=()
if [ $# -eq 0 ]; then
  ARCHS=("arm64" "x86_64")
else
  ARCHS=("$@")
fi

echo "==> Checking prerequisites..."
for cmd in cmake clang++ curl shasum tar; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not found."
    exit 1
  fi
done

for ARCH in "${ARCHS[@]}"; do
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Building for ${ARCH}"
  echo "════════════════════════════════════════════════════════════════"

  case "${ARCH}" in
    arm64)
      OUT_KEY="macos_arm64"
      CMAKE_ARCH="arm64"
      ;;
    x86_64)
      OUT_KEY="macos_x64"
      CMAKE_ARCH="x86_64"
      ;;
    *)
      echo "ERROR: unknown arch '${ARCH}'. Use arm64 or x86_64."
      exit 1
      ;;
  esac

  BUILD_DIR="/tmp/taglib_${ARCH}_build"
  INSTALL_DIR="${BUILD_DIR}/install"
  OUT_DIR="${SCRIPT_DIR}/prebuilt/${OUT_KEY}"

  mkdir -p "${BUILD_DIR}" "${OUT_DIR}"

  TARBALL="${BUILD_DIR}/taglib-${TAGLIB_VERSION}.tar.gz"
  if [ ! -f "${TARBALL}" ]; then
    echo "==> Downloading TagLib ${TAGLIB_VERSION}..."
    curl -fsSL -o "${TARBALL}" "${TAGLIB_URL}"
  fi

  echo "==> Verifying checksum..."
  ACTUAL_SHA=$(shasum -a 256 "${TARBALL}" | awk '{print $1}')
  if [ "${ACTUAL_SHA}" != "${TAGLIB_SHA256}" ]; then
    echo "ERROR: Checksum mismatch! expected ${TAGLIB_SHA256}, got ${ACTUAL_SHA}"
    rm -f "${TARBALL}"
    exit 1
  fi

  SRC_DIR="${BUILD_DIR}/taglib-${TAGLIB_VERSION}"
  if [ ! -d "${SRC_DIR}" ]; then
    echo "==> Extracting..."
    tar xzf "${TARBALL}" -C "${BUILD_DIR}"
  fi

  CMAKE_BUILD="${BUILD_DIR}/cmake_build"
  if [ ! -f "${INSTALL_DIR}/lib/libtag.a" ]; then
    echo "==> Configuring TagLib (CMake, ${CMAKE_ARCH})..."
    cmake -S "${SRC_DIR}" -B "${CMAKE_BUILD}" \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="${CMAKE_ARCH}" \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TESTING=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_BINDINGS=OFF \
      -DWITH_MP4=ON \
      -DWITH_ASF=ON

    echo "==> Building TagLib..."
    cmake --build "${CMAKE_BUILD}" --config Release --parallel "$(sysctl -n hw.ncpu)"

    echo "==> Installing TagLib..."
    cmake --install "${CMAKE_BUILD}"
  else
    echo "==> TagLib already built at ${INSTALL_DIR}"
  fi

  OUTPUT="${OUT_DIR}/libtaglib_shim.dylib"
  echo "==> Compiling taglib_shim..."
  clang++ -std=c++17 -fPIC -shared -O2 \
    -arch "${CMAKE_ARCH}" -mmacosx-version-min=11.0 \
    -DSHIM_TAGLIB_VERSION="${TAGLIB_VERSION}" \
    -I"${INSTALL_DIR}/include" \
    "${SHIM_SRC}" \
    "${INSTALL_DIR}/lib/libtag.a" \
    -lz \
    -Wl,-headerpad_max_install_names \
    -install_name @rpath/libtaglib_shim.dylib \
    -o "${OUTPUT}"

  strip -x "${OUTPUT}" || true

  echo ""
  echo "==> Done!"
  echo "  Output: ${OUTPUT}"
  echo "  Size:   $(du -h "${OUTPUT}" | awk '{print $1}')"
  file "${OUTPUT}"
done

echo ""
echo "All architectures built successfully."
