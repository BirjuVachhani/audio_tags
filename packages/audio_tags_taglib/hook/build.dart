import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// TagLib source distribution.
const _taglibVersion = '2.2.1';
const _taglibTarball =
    'https://taglib.github.io/releases/taglib-$_taglibVersion.tar.gz';
const _taglibSha256 =
    '7e76b5299dcef427c486bffe455098470c8da91cf3ccb9ea804893df57389b5e';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;
    final logger = Logger('')
      ..level = Level.ALL
      ..onRecord.listen((record) => print(record.message));

    // 1. Try prebuilt binary (fastest — no compiler needed).
    final prebuilt = _resolvePrebuilt(input.packageRoot, targetOS, targetArch);
    if (prebuilt != null) {
      logger.info('Using prebuilt binary: $prebuilt');
      _addPrebuiltAsset(input, output, prebuilt);
      return;
    }

    // 2. Try system TagLib (e.g. Homebrew, apt).
    final systemTaglib = _findSystemTaglib(targetOS);
    if (systemTaglib != null) {
      logger.info('Using system TagLib at: ${systemTaglib.root}');
      await _buildShimWithTaglib(input, output, logger, systemTaglib);
      return;
    }

    // 3. Download TagLib source and build everything from scratch.
    logger.info(
      'No prebuilt or system TagLib found. '
      'Downloading TagLib $_taglibVersion source...',
    );
    final buildDir = Directory.fromUri(
      input.outputDirectoryShared.resolve('taglib_build/'),
    );
    final taglibInstall = await _downloadAndBuildTaglib(buildDir, logger);
    await _buildShimWithTaglib(input, output, logger, taglibInstall);
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

  final name = os == OS.windows ? 'taglib_shim.$ext' : 'libtaglib_shim.$ext';
  final uri = packageRoot.resolve('prebuilt/$key/$name');
  return File.fromUri(uri).existsSync() ? uri : null;
}

void _addPrebuiltAsset(BuildInput input, BuildOutputBuilder output, Uri file) {
  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/taglib_shim.dart',
      file: file,
      linkMode: DynamicLoadingBundled(),
    ),
  );
}

// ---------------------------------------------------------------------------
// System TagLib detection
// ---------------------------------------------------------------------------

class _TaglibLocation {
  final String root;
  String get includeDir => '$root/include';
  String get libDir => '$root/lib';
  const _TaglibLocation(this.root);
}

_TaglibLocation? _findSystemTaglib(OS targetOS) {
  if (targetOS == OS.android || targetOS == OS.iOS) return null;

  // macOS Homebrew.
  for (final prefix in ['/opt/homebrew', '/usr/local']) {
    if (File('$prefix/include/taglib/fileref.h').existsSync()) {
      return _TaglibLocation(prefix);
    }
  }

  // Linux system paths.
  if (File('/usr/include/taglib/fileref.h').existsSync()) {
    return const _TaglibLocation('/usr');
  }

  // pkg-config fallback.
  try {
    final result = Process.runSync('pkg-config', [
      '--variable=prefix',
      'taglib',
    ]);
    if (result.exitCode == 0) {
      final prefix = (result.stdout as String).trim();
      if (prefix.isNotEmpty &&
          File('$prefix/include/taglib/fileref.h').existsSync()) {
        return _TaglibLocation(prefix);
      }
    }
  } on ProcessException {
    // pkg-config not available.
  }

  return null;
}

// ---------------------------------------------------------------------------
// Build shim against a known TagLib location
// ---------------------------------------------------------------------------

Future<void> _buildShimWithTaglib(
  BuildInput input,
  BuildOutputBuilder output,
  Logger logger,
  _TaglibLocation taglib,
) async {
  final cBuilder = CBuilder.library(
    name: 'taglib_shim',
    assetName: 'src/taglib_shim.dart',
    sources: ['src/taglib_shim.cpp'],
    language: Language.cpp,
    std: 'c++17',
    flags: [
      '-DSHIM_TAGLIB_VERSION=$_taglibVersion',
      '-I${taglib.includeDir}',
      '-L${taglib.libDir}',
      '-ltag',
    ],
  );
  await cBuilder.run(input: input, output: output, logger: logger);
}

// ---------------------------------------------------------------------------
// Download and build TagLib from source
// ---------------------------------------------------------------------------

Future<_TaglibLocation> _downloadAndBuildTaglib(
  Directory buildDir,
  Logger logger,
) async {
  final installDir = Directory('${buildDir.path}/install');

  // Skip if already built (cached across hook invocations).
  if (File('${installDir.path}/lib/libtag.a').existsSync() ||
      File('${installDir.path}/lib/libtag.dylib').existsSync()) {
    logger.info('TagLib already built at ${installDir.path}');
    return _TaglibLocation(installDir.path);
  }

  buildDir.createSync(recursive: true);

  // Download.
  final tarball = File('${buildDir.path}/taglib-$_taglibVersion.tar.gz');
  if (!tarball.existsSync()) {
    logger.info('Downloading $_taglibTarball ...');
    final result = await Process.run('curl', [
      '-fsSL',
      '-o',
      tarball.path,
      _taglibTarball,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Failed to download TagLib: ${result.stderr}');
    }

    // Verify checksum. Pick the right tool for the host platform.
    final shaTool = Platform.isLinux ? 'sha256sum' : 'shasum';
    final shaArgs = Platform.isLinux
        ? [tarball.path]
        : ['-a', '256', tarball.path];
    final sha = await Process.run(shaTool, shaArgs);
    if (sha.exitCode != 0) {
      throw StateError('$shaTool failed (exit ${sha.exitCode}): ${sha.stderr}');
    }
    final actualSha = (sha.stdout as String).split(' ').first.trim();
    if (actualSha != _taglibSha256) {
      tarball.deleteSync();
      throw StateError(
        'TagLib checksum mismatch: expected $_taglibSha256, got $actualSha',
      );
    }
  }

  // Extract.
  final srcDir = Directory('${buildDir.path}/taglib-$_taglibVersion');
  if (!srcDir.existsSync()) {
    await Process.run('tar', ['xzf', tarball.path, '-C', buildDir.path]);
  }

  // Build with CMake.
  final cmakeBuildDir = Directory('${buildDir.path}/cmake_build');
  cmakeBuildDir.createSync(recursive: true);
  installDir.createSync(recursive: true);

  logger.info('Configuring TagLib with CMake...');
  var result = await Process.run('cmake', [
    '-S',
    srcDir.path,
    '-B',
    cmakeBuildDir.path,
    '-DCMAKE_INSTALL_PREFIX=${installDir.path}',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DWITH_MP4=ON',
    '-DWITH_ASF=ON',
    '-DBUILD_SHARED_LIBS=ON',
    '-DBUILD_TESTING=OFF',
    '-DBUILD_EXAMPLES=OFF',
    '-DBUILD_BINDINGS=OFF',
  ]);
  if (result.exitCode != 0) {
    throw StateError('CMake configure failed: ${result.stderr}');
  }

  logger.info('Building TagLib...');
  result = await Process.run('cmake', [
    '--build',
    cmakeBuildDir.path,
    '--config',
    'Release',
    '--parallel',
  ]);
  if (result.exitCode != 0) {
    throw StateError('CMake build failed: ${result.stderr}');
  }

  logger.info('Installing TagLib to ${installDir.path}...');
  result = await Process.run('cmake', ['--install', cmakeBuildDir.path]);
  if (result.exitCode != 0) {
    throw StateError('CMake install failed: ${result.stderr}');
  }

  return _TaglibLocation(installDir.path);
}
