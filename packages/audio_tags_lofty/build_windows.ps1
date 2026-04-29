#
# Build the prebuilt windows_x64 binary for audio_tags_lofty.
# Run this on a Windows x64 machine with Rust installed.
#
# Prerequisites:
#   - Rust (https://rustup.rs)
#   - Visual Studio C++ Build Tools (for the MSVC linker)
#
# Usage:
#   .\build_windows.ps1
#

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CrateDir = "$ScriptDir\src"
$OutDir = "$ScriptDir\prebuilt\windows_x64"

Write-Host "==> Checking prerequisites..."
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Error "cargo is required but not found. Install Rust from https://rustup.rs"
    exit 1
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "==> Building lofty_shim (release)..."
cargo build --release --manifest-path "$CrateDir\Cargo.toml"
if ($LASTEXITCODE -ne 0) { Write-Error "Cargo build failed."; exit 1 }

$Output = "$CrateDir\target\release\lofty_shim.dll"
if (-not (Test-Path $Output)) {
    Write-Error "Build succeeded but binary not found at $Output"
    exit 1
}

Copy-Item $Output "$OutDir\lofty_shim.dll"

$Size = (Get-Item "$OutDir\lofty_shim.dll").Length / 1MB
Write-Host "==> Done!"
Write-Host "  Output: $OutDir\lofty_shim.dll"
Write-Host ("  Size:   {0:N1} MB" -f $Size)
