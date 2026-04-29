#
# Build the prebuilt windows_x64 binary for audio_metadata.
# Run this on a Windows x64 machine from a Developer PowerShell / VS prompt.
#
# Prerequisites:
#   - Visual Studio 2022 with C++ Desktop workload, or Build Tools for VS 2022
#   - CMake (included with VS or install separately)
#   - curl (included with Windows 10+)
#
# Usage:
#   .\build_windows.ps1
#

$ErrorActionPreference = "Stop"

$TaglibVersion = "2.2.1"
$TaglibUrl = "https://taglib.github.io/releases/taglib-$TaglibVersion.tar.gz"
$TaglibSha256 = "7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BuildDir = "$env:TEMP\taglib_windows_build"
$InstallDir = "$BuildDir\install"
$OutDir = "$ScriptDir\prebuilt\windows_x64"

# ── Check prerequisites ────────────────────────────────────────────────────

Write-Host "==> Checking prerequisites..."
foreach ($cmd in @("cmake", "cl")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd is required but not found. Run from a Developer PowerShell for VS 2022."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ── Download TagLib source ─────────────────────────────────────────────────

$Tarball = "$BuildDir\taglib-$TaglibVersion.tar.gz"
if (-not (Test-Path $Tarball)) {
    Write-Host "==> Downloading TagLib $TaglibVersion..."
    curl.exe -fsSL -o $Tarball $TaglibUrl
    if ($LASTEXITCODE -ne 0) { Write-Error "Download failed."; exit 1 }
}

Write-Host "==> Verifying checksum..."
$ActualHash = (Get-FileHash -Path $Tarball -Algorithm SHA256).Hash.ToLower()
if ($ActualHash -ne $TaglibSha256) {
    Write-Error "Checksum mismatch! Expected $TaglibSha256, got $ActualHash"
    Remove-Item $Tarball -Force
    exit 1
}

# ── Extract ────────────────────────────────────────────────────────────────

$SrcDir = "$BuildDir\taglib-$TaglibVersion"
if (-not (Test-Path $SrcDir)) {
    Write-Host "==> Extracting..."
    tar xzf $Tarball -C $BuildDir
}

# ── Build TagLib as a static library ───────────────────────────────────────

$CmakeBuild = "$BuildDir\cmake_build"
$TaglibLib = "$InstallDir\lib\tag.lib"
if (-not (Test-Path $TaglibLib)) {
    Write-Host "==> Configuring TagLib with CMake..."
    cmake -S $SrcDir -B $CmakeBuild `
        -DCMAKE_INSTALL_PREFIX="$InstallDir" `
        -DCMAKE_BUILD_TYPE=Release `
        -DWITH_MP4=ON `
        -DWITH_ASF=ON `
        -DBUILD_SHARED_LIBS=OFF `
        -DBUILD_TESTING=OFF `
        -DBUILD_EXAMPLES=OFF `
        -DBUILD_BINDINGS=OFF
    if ($LASTEXITCODE -ne 0) { Write-Error "CMake configure failed."; exit 1 }

    Write-Host "==> Building TagLib..."
    cmake --build $CmakeBuild --config Release --parallel
    if ($LASTEXITCODE -ne 0) { Write-Error "CMake build failed."; exit 1 }

    Write-Host "==> Installing TagLib..."
    cmake --install $CmakeBuild --config Release
    if ($LASTEXITCODE -ne 0) { Write-Error "CMake install failed."; exit 1 }
} else {
    Write-Host "==> TagLib already built at $InstallDir"
}

# ── Compile the shim ──────────────────────────────────────────────────────

$Output = "$OutDir\taglib_shim.dll"
$ShimSrc = "$ScriptDir\src\taglib_shim.cpp"

# Find the static lib — could be in lib/ or lib/Release/ depending on generator.
$TaglibStaticLib = $null
foreach ($candidate in @(
    "$InstallDir\lib\tag.lib",
    "$InstallDir\lib\Release\tag.lib",
    "$InstallDir\lib\libtag.a"
)) {
    if (Test-Path $candidate) {
        $TaglibStaticLib = $candidate
        break
    }
}
if (-not $TaglibStaticLib) {
    Write-Error "Could not find TagLib static library under $InstallDir\lib"
    exit 1
}

Write-Host "==> Compiling taglib_shim (TagLib $TaglibVersion)..."
cl.exe /nologo /std:c++17 /O2 /EHsc /MD `
    /DSHIM_TAGLIB_VERSION=$TaglibVersion `
    /DTAGLIB_STATIC `
    /I"$InstallDir\include" `
    /LD `
    $ShimSrc `
    $TaglibStaticLib `
    /Fe:"$Output" `
    /link /DLL
if ($LASTEXITCODE -ne 0) { Write-Error "Compilation failed."; exit 1 }

# Clean up intermediate files cl.exe leaves behind.
Remove-Item "$OutDir\taglib_shim.obj" -ErrorAction SilentlyContinue
Remove-Item "$OutDir\taglib_shim.exp" -ErrorAction SilentlyContinue
Remove-Item "$OutDir\taglib_shim.lib" -ErrorAction SilentlyContinue

$Size = (Get-Item $Output).Length / 1MB
Write-Host "==> Done!"
Write-Host "  Output: $Output"
Write-Host ("  Size:   {0:N1} MB" -f $Size)
