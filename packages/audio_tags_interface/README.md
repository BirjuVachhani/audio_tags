# audio_tags_interface

Core interface and data models for the `audio_tags` ecosystem. This package
defines the contract that all audio metadata backends must implement.

## When to use this package

- **Backend authors**: Depend on this package to implement a custom backend.
- **End users**: You don't need this package directly. Use `audio_tags` instead
  — it re-exports everything from here.

## Install

```yaml
dependencies:
  audio_tags_interface: ^0.1.0
```

## What's included

### Data models

- `AudioMetadata` — normalized common tag fields (title, artist, album, ...)
- `AudioMetadataDocument` — complete read result (metadata + properties + pictures + raw tags)
- `AudioMetadataPatch` — describes edits for write operations
- `AudioProperties` — audio stream properties (duration, bitrate, sample rate, channels)
- `AudioPicture` / `AudioPictureType` — embedded picture data
- `AudioPictureOperation` (sealed) — `AddPictureOperation`, `RemovePicturesByTypeOperation`, `RemoveAllPicturesOperation`
- `AudioRawTag` — raw tag container with key-value fields
- `AudioReadOptions` / `AudioWriteOptions` — operation configuration
- `AudioTagField` — enum of 15 standard metadata field names

### Backend interface

- `AudioMetadataBackend` — the abstract interface all backends implement
- `AudioBackendCapabilities` — capability descriptor (supported formats, operations)
- `AudioMetadataBackendRegistry` — singleton factory registry for dynamic backend lookup

### Error types

- `AudioMetadataException` (sealed base)
- `AudioFormatUnsupportedException`
- `AudioMetadataReadException`
- `AudioMetadataWriteException`
- `AudioBackendUnavailableException`

## Implementing a backend

```dart
import 'package:audio_tags_interface/audio_tags_interface.dart';

final class MyBackend implements AudioMetadataBackend {
  @override
  String get id => 'my_backend';

  @override
  String? get version => '1.0.0';

  @override
  bool get supportsReading => true;

  @override
  bool get supportsWriting => false;

  @override
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  ) async {
    // Parse the file and return an AudioMetadataDocument.
    return AudioMetadataDocument(
      metadata: AudioMetadata(title: 'Parsed title'),
      backendId: id,
    );
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async =>
      throw UnsupportedError('$id does not support bytes');

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async =>
      throw UnsupportedError('$id does not support writing');

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async =>
      throw UnsupportedError('$id does not support writing');

  @override
  Future<AudioBackendCapabilities> getCapabilities() async {
    return AudioBackendCapabilities(
      backendVersion: version,
      canReadFromFile: true,
      canReadFromBytes: false,
      canWriteToFile: false,
      canWriteToBytes: false,
      canReadPictures: false,
      canWritePictures: false,
      supportedFormats: {'mp3', 'flac'},
      writableFormats: {},
    );
  }
}
```

### Backend contract

Every backend must:

- Populate `AudioMetadataDocument` according to the `AudioReadOptions` flags
- Set `backendId` to the backend's `id` on every returned document
- Translate failures into `AudioMetadataException` subclasses
- Throw `UnsupportedError` for unimplemented operations
- Report accurate capabilities via `getCapabilities()`
- Preserve unmodified fields during writes (non-destructive)

See the [audio_tags repository](https://github.com/birjuvachhani/audio_tags#readme)
for the full backend guide and architecture overview.

## Related packages

- [`audio_tags`](https://pub.dev/packages/audio_tags) — User-facing package, batteries included.
- [`audio_tags_taglib`](https://pub.dev/packages/audio_tags_taglib) — TagLib (C++) backend.
- [`audio_tags_lofty`](https://pub.dev/packages/audio_tags_lofty) — Lofty (Rust) backend.

## Issues

Report bugs or request features at
[github.com/birjuvachhani/audio_tags/issues](https://github.com/birjuvachhani/audio_tags/issues).
