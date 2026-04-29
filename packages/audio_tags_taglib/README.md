# audio_tags_taglib

[TagLib](https://taglib.org) backend for the `audio_tags` ecosystem. Provides
read and write support for MP3, FLAC, OGG, MP4, WAV, AIFF, and many more
formats via FFI.

## When to use this package

- **End users**: You don't need this package directly. Use `audio_tags` instead
  — it includes this backend by default.
- **Direct usage**: If you want the TagLib backend without the service layer,
  depend on this package directly.

## Install

```yaml
dependencies:
  audio_tags_taglib: ^0.1.0
```

## Usage

```dart
import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:audio_tags_taglib/audio_tags_taglib.dart';

void main() async {
  final backend = TaglibAudioMetadataBackend();

  // Check version.
  print('TagLib version: ${backend.version}');

  // Read.
  final doc = await backend.readFromFile(
    'song.mp3',
    const AudioReadOptions(),
  );
  print('Title: ${doc.metadata.title}');

  // Write.
  await backend.writeToFile(
    'song.mp3',
    const AudioMetadataPatch(
      setFields: {AudioTagField.title: 'New Title'},
    ),
    const AudioWriteOptions(),
  );
}
```

## Native build

The package includes a Dart native asset build hook (`hook/build.dart`) that
resolves the native library in three tiers:

1. **Prebuilt binary** — checked first in `prebuilt/{os}_{arch}/`. Zero build
   step.
2. **System TagLib** — detected via Homebrew, apt, or pkg-config. Compiles only
   the thin C shim.
3. **Download & build** — downloads TagLib 2.2.1 source, verifies SHA-256,
   builds with CMake, then compiles the shim. Fully automatic.

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

### Building prebuilt binaries

**Linux:**

```bash
cd packages/audio_tags_taglib
chmod +x build_linux.sh
./build_linux.sh
```

**Windows** (from Developer PowerShell for VS 2022):

```powershell
cd packages\audio_tags_taglib
.\build_windows.ps1
```

## Supported formats

| Format | Read | Write | Pictures |
|--------|------|-------|----------|
| MP3 (ID3v1/ID3v2) | Yes | Yes | Read + Write |
| FLAC | Yes | Yes | Read + Write |
| OGG Vorbis | Yes | Yes | Read + Write |
| Opus | Yes | Yes | Read + Write |
| MP4 / M4A / M4B / AAC | Yes | Yes | Read + Write |
| WAV | Yes | Yes | Read + Write |
| AIFF | Yes | Yes | Read + Write |
| WMA / ASF | Yes | Yes | — |
| APE | Yes | Yes | — |
| Musepack | Yes | Yes | — |
| WavPack | Yes | Yes | — |
| DSF / DFF | Yes | — | — |
| Speex | Yes | — | — |
| TrueAudio | Yes | — | — |

## Related packages

- [`audio_tags`](https://pub.dev/packages/audio_tags) — User-facing package; uses this backend by default.
- [`audio_tags_interface`](https://pub.dev/packages/audio_tags_interface) — Backend interface.
- [`audio_tags_lofty`](https://pub.dev/packages/audio_tags_lofty) — Alternative pure-Rust backend.

## Issues

Report bugs or request features at
[github.com/birjuvachhani/audio_tags/issues](https://github.com/birjuvachhani/audio_tags/issues).
