# audio_tags_lofty

[Lofty](https://github.com/Serial-ATA/lofty-rs) (Rust) backend for the
`audio_tags` ecosystem. Provides read and write support for MP3, FLAC, OGG,
MP4, WAV, AIFF, and more via FFI to a Rust `cdylib`.

## When to use this package

Use this as an alternative to the default TagLib backend when you want:
- A pure-Rust native dependency (no C++ toolchain needed to build from source)
- Potentially different format behavior or compatibility

## Install

```yaml
dependencies:
  audio_tags_interface: ^0.1.0
  audio_tags_lofty: ^0.1.0
```

## Usage

```dart
import 'package:audio_tags/audio_tags.dart';
import 'package:audio_tags_lofty/audio_tags_lofty.dart';

void main() async {
  // Use Lofty instead of the default TagLib backend.
  final service = AudioMetadataService(backend: LoftyAudioMetadataBackend());

  final doc = await service.read('song.mp3');
  print('Title: ${doc.metadata.title}');
  print('Lofty version: ${service.backend.version}');

  await service.write(
    'song.mp3',
    AudioMetadataPatch(
      setFields: {AudioTagField.title: 'New Title'},
    ),
  );
}
```

Or set as the global default:

```dart
AudioMetadataConfig.instance.defaultBackend = LoftyAudioMetadataBackend();
```

## Native build

The package includes prebuilt binaries for most platforms. If no prebuilt is
available, the build hook runs `cargo build --release` automatically (requires
Rust toolchain).

### Prebuilt binaries included

| Target | Status |
|--------|--------|
| macOS arm64 | Included |
| macOS x64 | Included |
| iOS arm64 | Included |
| Android arm64 | Included |
| Android arm | Included |
| Android x64 | Included |
| Linux x64 | Included |
| Windows x64 | Included |

### Building prebuilt binaries from source

If you need to refresh the prebuilts (e.g. after upgrading lofty-rs), helper
scripts are included in the source tree at
[github.com/birjuvachhani/audio_tags](https://github.com/birjuvachhani/audio_tags):

- `build_macos.sh` — builds `macos_arm64` and `macos_x64`.
- `build_linux.sh` — run on a Linux x86_64 host.
- `build_windows.ps1` — run on a Windows x64 host.

You can also cross-compile from macOS using `cargo-zigbuild` (Linux) and
`mingw-w64` (Windows). All scripts require a Rust toolchain
([rustup.rs](https://rustup.rs)).

## Supported formats

| Format | Read | Write | Pictures |
|--------|------|-------|----------|
| MP3 (ID3v1/ID3v2) | Yes | Yes | Read + Write |
| FLAC | Yes | Yes | Read + Write |
| OGG Vorbis | Yes | Yes | Read + Write |
| Opus | Yes | Yes | Read + Write |
| Speex | Yes | Yes | — |
| MP4 / M4A / M4B / AAC | Yes | Yes | Read + Write |
| WAV | Yes | Yes | Read + Write |
| AIFF | Yes | Yes | Read + Write |
| APE | Yes | Yes | — |
| Musepack | Yes | Yes | — |
| WavPack | Yes | Yes | — |

## Differences from the TagLib backend

| Feature | TagLib | Lofty |
|---------|--------|-------|
| Language | C++ | Rust |
| Chapter extraction (MP3) | Yes | No |
| Picture read | Yes | Yes |
| Picture write | Yes | Yes |
| DSF / DFF support | Yes | No |
| Build from source | CMake + C++ | Cargo (Rust) |

## Related packages

- [`audio_tags`](https://pub.dev/packages/audio_tags) — User-facing package, uses TagLib by default.
- [`audio_tags_interface`](https://pub.dev/packages/audio_tags_interface) — Backend interface.
- [`audio_tags_taglib`](https://pub.dev/packages/audio_tags_taglib) — TagLib (C++) backend.

## Issues

Report bugs or request features at
[github.com/birjuvachhani/audio_tags/issues](https://github.com/birjuvachhani/audio_tags/issues).
