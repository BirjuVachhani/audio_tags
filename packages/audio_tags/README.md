# audio_tags

A Dart-first audio metadata library with pluggable backends. Read and write
metadata for MP3, FLAC, OGG, MP4, WAV, AIFF, and many more formats. Defaults
to [TagLib](https://taglib.org) as the production backend.

Works with plain Dart and Flutter on native platforms (macOS, Linux, Windows,
iOS, Android). Suitable for CLI tools, server apps, desktop apps, and mobile
apps.

This is the only package most users need.

## Features

- Stable, idiomatic Dart API that never leaks backend-specific concepts.
- Read and write common metadata fields: title, artist, album, year, genre,
  lyrics, track/disc numbers, and more.
- **Full embedded-picture support** — front cover, back cover, all 21 standard
  picture types — read, write, replace, remove.
- Read audio properties: duration, bitrate, sample rate, channels, bit depth.
- File `format` and tag `container` detection
  (e.g. `mp3` + `ID3v2.4`, `flac` + `VorbisComments`).
- `extras` map exposes non-normalized fields (ISRC, MusicBrainz IDs,
  ReplayGain, copyright, label, ...).
- Read and write raw tag fields for advanced use cases.
- In-memory bytes API (`readBytes` / `writeBytes`) for non-filesystem workflows.
- Chapter-marker reading (ID3v2 CHAP / CTOC frames).
- Pluggable backend architecture with runtime capability reporting.
- Sealed exception hierarchy with file path and cause for structured error
  handling.
- Native asset build hook with prebuilt binaries — no C++ toolchain required
  on supported platforms.

## Install

```yaml
dependencies:
  audio_tags: ^0.1.0
```

```dart
import 'package:audio_tags/audio_tags.dart';
```

This single import gives you everything:

- All data models and types (re-exported from `audio_tags_interface`).
- The TagLib backend (re-exported from `audio_tags_taglib`).
- `AudioMetadataService` — high-level read/write facade.
- `AudioMetadataConfig` — global backend configuration.

## Quick start

### Read metadata

```dart
import 'package:audio_tags/audio_tags.dart';

void main() async {
  final service = AudioMetadataService();
  final doc = await service.read('song.mp3');

  print('${doc.metadata.title} — ${doc.metadata.artist}');
  print('Album: ${doc.metadata.album} (${doc.metadata.year})');
  print('Duration: ${doc.properties?.duration}');
  print('Format: ${doc.format} + ${doc.container}');
}
```

### Write metadata

```dart
await service.write(
  'song.mp3',
  AudioMetadataPatch(
    setFields: {
      AudioTagField.title: 'New Title',
      AudioTagField.artist: 'New Artist',
      AudioTagField.year: '2025',
    },
  ),
);
```

### Read and write cover art

```dart
// Read
final doc = await service.read(
  'song.mp3',
  options: const AudioReadOptions(readPictures: true),
);
final cover = doc.frontCover;
if (cover != null) {
  await File('cover.jpg').writeAsBytes(cover.data);
}

// Write
await service.write(
  'song.mp3',
  AudioMetadataPatch(
    pictureOperations: [
      AddPictureOperation(
        AudioPicture(
          data: await File('new_cover.jpg').readAsBytes(),
          mimeType: 'image/jpeg',
          type: AudioPictureType.frontCover,
        ),
      ),
    ],
  ),
);
```

### In-memory bytes

```dart
final bytes = await File('song.mp3').readAsBytes();
final doc = await service.readBytes(bytes);

final updated = await service.writeBytes(
  bytes,
  AudioMetadataPatch(setFields: {AudioTagField.title: 'New Title'}),
);
```

### Error handling

```dart
try {
  await service.read('song.mp3');
} on AudioFormatUnsupportedException catch (e) {
  print('Unsupported format: ${e.path}');
} on AudioMetadataReadException catch (e) {
  print('Read failed: ${e.message} — ${e.path}');
} on AudioMetadataException catch (e) {
  print('Other metadata error: ${e.message}');
}
```

## Switching backends

The TagLib backend is the default. To use the alternative pure-Rust
[`audio_tags_lofty`](https://pub.dev/packages/audio_tags_lofty) backend:

```yaml
dependencies:
  audio_tags: ^0.1.0
  audio_tags_lofty: ^0.1.0
```

Per-instance:

```dart
import 'package:audio_tags/audio_tags.dart';
import 'package:audio_tags_lofty/audio_tags_lofty.dart';

final service = AudioMetadataService(backend: LoftyAudioMetadataBackend());
```

Globally (affects every `AudioMetadataService()` constructed without an
explicit backend):

```dart
AudioMetadataConfig.instance.defaultBackend = LoftyAudioMetadataBackend();
```

## Supported formats

The default TagLib backend supports:

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

The Lofty backend covers a similar set with slightly different platform
trade-offs — see its
[package page](https://pub.dev/packages/audio_tags_lofty) for details.

## Capability reporting

Backends report what they support at runtime:

```dart
final caps = await service.capabilities();
print('Read: ${caps.canReadFromFile}, Write: ${caps.canWriteToFile}');
print('Pictures: read=${caps.canReadPictures}, write=${caps.canWritePictures}');
print('Supported formats: ${caps.supportedFormats}');
```

## Platform support

Prebuilt binaries are shipped for: macOS (arm64, x64), Linux x64, Windows x64,
iOS arm64, Android (arm, arm64, x64). On other platforms the build hook falls
back to building from source (requires a C++ toolchain for TagLib, or Rust for
Lofty).

## Related packages

- [`audio_tags_interface`](https://pub.dev/packages/audio_tags_interface) —
  Backend interface and data models. Depend on this if you're authoring a
  custom backend.
- [`audio_tags_taglib`](https://pub.dev/packages/audio_tags_taglib) — TagLib
  (C++) backend. Bundled here by default.
- [`audio_tags_lofty`](https://pub.dev/packages/audio_tags_lofty) — Lofty
  (Rust) backend. Pure-Rust alternative.

## Issues

Report bugs or request features at
[github.com/birjuvachhani/audio_tags/issues](https://github.com/birjuvachhani/audio_tags/issues).
