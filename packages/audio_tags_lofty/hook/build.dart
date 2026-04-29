import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));

    // 1. Try prebuilt binary (fastest — no Rust toolchain needed).
    final prebuilt = _resolvePrebuilt(input.packageRoot, targetOS, targetArch);
    if (prebuilt != null) {
      logger.info('Using prebuilt Lofty binary: $prebuilt');
      _addPrebuiltAsset(input, output, prebuilt);
      return;
    }

    // 2. Build from source with Cargo.
    logger.info('No prebuilt found. Building Lofty shim from source...');
    final binary = await _buildFromSource(input, targetOS, targetArch, logger);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/lofty_shim.dart',
        file: binary,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

// ---------------------------------------------------------------------------
// Prebuilt binary resolution
// ---------------------------------------------------------------------------

Uri? _resolvePrebuilt(Uri packageRoot, OS os, Architecture arch) {
  final key = switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'macos_arm64',
    (OS.macOS, Architecture.x64) => 'macos_x64',
    (OS.linux, Architecture.x64) => 'linux_x64',
    (OS.windows, Architecture.x64) => 'windows_x64',
    (OS.android, Architecture.arm64) => 'android_arm64',
    (OS.android, Architecture.arm) => 'android_arm',
    (OS.android, Architecture.x64) => 'android_x64',
    (OS.iOS, Architecture.arm64) => 'ios_arm64',
    _ => null,
  };
  if (key == null) return null;

  final ext = switch (os) {
    OS.macOS || OS.iOS => 'dylib',
    OS.linux || OS.android => 'so',
    OS.windows => 'dll',
    _ => null,
  };
  if (ext == null) return null;

  final name = os == OS.windows ? 'lofty_shim.$ext' : 'liblofty_shim.$ext';
  final uri = packageRoot.resolve('prebuilt/$key/$name');
  return File.fromUri(uri).existsSync() ? uri : null;
}

void _addPrebuiltAsset(BuildInput input, BuildOutputBuilder output, Uri file) {
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/lofty_shim.dart',
      file: file,
      linkMode: DynamicLoadingBundled(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Build from source with Cargo
// ---------------------------------------------------------------------------

Future<Uri> _buildFromSource(
  BuildInput input,
  OS targetOS,
  Architecture targetArch,
  Logger logger,
) async {
  final cargoDir = Directory.fromUri(input.packageRoot.resolve('src/'));

  // Determine Rust target triple.
  final triple = _rustTriple(targetOS, targetArch);
  if (triple == null) {
    throw StateError(
      'Unsupported target for Cargo build: $targetOS / $targetArch',
    );
  }

  logger.info('Building with: cargo build --release --target $triple');
  final result = await Process.run('cargo', [
    'build',
    '--release',
    '--target',
    triple,
  ], workingDirectory: cargoDir.path);

  if (result.exitCode != 0) {
    throw StateError('Cargo build failed:\n${result.stderr}');
  }

  // Locate the output binary.
  final ext = switch (targetOS) {
    OS.macOS || OS.iOS => 'dylib',
    OS.linux || OS.android => 'so',
    OS.windows => 'dll',
    _ => throw StateError('Unknown OS: $targetOS'),
  };
  final prefix = targetOS == OS.windows ? '' : 'lib';
  final binaryPath =
      '${cargoDir.path}/target/$triple/release/${prefix}lofty_shim.$ext';
  final binaryFile = File(binaryPath);

  if (!binaryFile.existsSync()) {
    throw StateError(
      'Cargo build succeeded but binary not found at $binaryPath',
    );
  }

  return binaryFile.uri;
}

String? _rustTriple(OS os, Architecture arch) {
  return switch ((os, arch)) {
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.iOS, Architecture.arm64) => 'aarch64-apple-ios',
    _ => null,
  };
}
