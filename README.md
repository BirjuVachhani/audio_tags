# audio_tags

A Dart-first audio metadata library with pluggable backends. Read and write
metadata for MP3, FLAC, OGG, MP4, WAV, AIFF, and many more formats. Defaults
to [TagLib](https://taglib.org) as the production backend.

Works with plain Dart and Flutter on native platforms (macOS, Linux, Windows,
iOS, Android). Suitable for CLI tools, server apps, desktop apps, and mobile
apps.

## Features

- Stable, idiomatic Dart API that never leaks backend-specific concepts
- Read and write common metadata fields (title, artist, album, year, lyrics, ...)
- **Full embedded-picture support** — front cover, back cover, band logo, all 21
  picture types — read, write, replace, remove
- Read audio properties (duration, bitrate, sample rate, channels, **bit depth**)
- File `format` and tag `container` detection (e.g. `mp3` + `ID3v2.4`,
  `flac` + `VorbisComments`)
- `extras` map exposes non-normalized fields (ISRC, MusicBrainz IDs,
  ReplayGain, copyright, ...)
- Read and write raw tag fields for advanced use cases
- In-memory bytes API (`readBytes` / `writeBytes`) for non-filesystem workflows
- Chapter-marker reading (ID3v2 CHAP / CTOC frames)
- Pluggable backend architecture with runtime capability reporting
- Global config with per-instance backend override
- Sealed exception hierarchy with file path + cause for structured error handling
- Native asset build hook with prebuilt binaries (no C++ toolchain required on
  supported platforms)

## Supported formats

The default TagLib backend supports:

| Format | Read | Write |
|--------|------|-------|
| MP3 (ID3v1/ID3v2) | Yes | Yes |
| FLAC | Yes | Yes |
| OGG Vorbis | Yes | Yes |
| Opus | Yes | Yes |
| MP4 / M4A / M4B / AAC | Yes | Yes |
| WAV | Yes | Yes |
| AIFF | Yes | Yes |
| WMA / ASF | Yes | Yes |
| APE | Yes | Yes |
| Musepack | Yes | Yes |
| WavPack | Yes | Yes |
| DSF / DFF | Yes | - |
| Speex | Yes | - |
| TrueAudio | Yes | - |

## Quick start

### Install

```yaml
dependencies:
  audio_tags: ^0.4.0
```

Only one import is needed — `audio_tags` re-exports everything:

```dart
import 'package:audio_tags/audio_tags.dart';
```

### Prerequisites

On supported platforms, prebuilt native binaries are included. No C++ toolchain
needed.

If no prebuilt binary is available for your target, the build hook falls back to
compiling from source. In that case, TagLib must be available:

**macOS:** `brew install taglib`
**Linux:** `sudo apt install libtag1-dev`
**Windows:** `vcpkg install taglib`

If TagLib is not installed at all, the hook will download and build it from
source automatically (requires CMake and a C++ compiler).

### Read metadata

```dart
import 'package:audio_tags/audio_tags.dart';

Future<void> main() async {
  final service = AudioMetadataService();

  final doc = await service.read('song.mp3');
  print('Title:    ${doc.metadata.title}');
  print('Artist:   ${doc.metadata.artist}');
  print('Album:    ${doc.metadata.album}');
  print('Year:     ${doc.metadata.year}');
  print('Duration: ${doc.properties?.duration}');
  print('Bitrate:  ${doc.properties?.bitrate} kbps');
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
      AudioTagField.year: 2025,
    },
  ),
);
```

### Clear fields

```dart
await service.write(
  'song.mp3',
  AudioMetadataPatch(
    // Set to null to remove a field.
    setFields: {AudioTagField.comment: null},
    // Or use clearFields.
    clearFields: {AudioTagField.lyrics},
  ),
);
```

### Pictures (cover art)

Read embedded artwork:

```dart
final doc = await service.read(
  'song.mp3',
  options: AudioReadOptions(readPictures: true),
);

final cover = doc.frontCover;          // shorthand for AudioPictureType.frontCover
if (cover != null) {
  print('Cover: ${cover.mimeType} (${cover.data.length} bytes)');
  await File('cover.jpg').writeAsBytes(cover.data);
}

// Or any picture type:
final logo = doc.pictureOfType(AudioPictureType.bandLogo);
```

Add or replace artwork:

```dart
final imageBytes = await File('cover.jpg').readAsBytes();

await service.write(
  'song.mp3',
  AudioMetadataPatch(
    pictureOperations: [
      // Replace any existing front cover, then add the new one.
      const RemovePicturesByTypeOperation(AudioPictureType.frontCover),
      AddPictureOperation(AudioPicture(
        type: AudioPictureType.frontCover,
        mimeType: 'image/jpeg',
        description: 'Album art',
        data: imageBytes,
      )),
    ],
  ),
);
```

Wipe all pictures:

```dart
await service.write(
  'song.mp3',
  const AudioMetadataPatch(
    pictureOperations: [RemoveAllPicturesOperation()],
  ),
);
```

Mime type is sniffed from the bytes (jpeg/png/gif/bmp/tiff) when omitted.

### Lyrics

```dart
await service.write(
  'song.mp3',
  const AudioMetadataPatch(setFields: {
    AudioTagField.lyrics: 'Yesterday, all my troubles seemed so far away...',
  }),
);

final doc = await service.read('song.mp3');
print(doc.metadata.lyrics);
```

### In-memory bytes

For non-filesystem workflows (e.g. mobile document picker, network):

```dart
final bytes = await fetchAudioBytes();

final doc = await service.readBytes(bytes, extensionHint: 'mp3');

final updated = await service.writeBytes(
  bytes,
  AudioMetadataPatch(setFields: {AudioTagField.title: 'Updated'}),
  extensionHint: 'mp3',
);
```

The service falls back to a temporary file when the active backend doesn't
support byte-level I/O natively (both shipped backends use this fallback today).

### Raw tag access

Read the full property map for advanced field access:

```dart
final doc = await service.read(
  'song.flac',
  options: AudioReadOptions(readRawTags: true),
);

for (final tag in doc.rawTags) {
  print('Tag type: ${tag.tagType}');
  for (final entry in tag.fields.entries) {
    print('  ${entry.key}: ${entry.value}');
  }
}
```

Write arbitrary property map keys:

```dart
await service.write(
  'song.flac',
  AudioMetadataPatch(
    rawMutations: {
      'ISRC': 'US1234567890',
      'CUSTOM_FIELD': 'custom value',
    },
  ),
);
```

## Architecture

```
audio_tags (user-facing package)
  -> AudioMetadataService
    -> AudioMetadataBackend (interface, from audio_tags_interface)
      -> TaglibAudioMetadataBackend (from audio_tags_taglib)
        -> TaglibBindings (FFI bridge)
          -> C shim (taglib_shim.cpp)
            -> TagLib C++ library
```

The public API belongs to Dart. The backend is replaceable.

### Backend selection

**Default** (TagLib, zero config):

```dart
final service = AudioMetadataService();
```

**Explicit backend per-instance:**

```dart
final service = AudioMetadataService(
  backend: TaglibAudioMetadataBackend(),
);
```

**Override the global default:**

```dart
AudioMetadataConfig.instance.defaultBackend = MyCustomBackend();
```

**Dynamic registry for lookup by ID:**

```dart
AudioMetadataBackendRegistry.instance.register(
  'custom',
  () => MyCustomBackend(),
);

final backend = AudioMetadataBackendRegistry.instance.create('custom');
```

### Capability reporting

Query what a backend supports at runtime:

```dart
final caps = await backend.getCapabilities();
print('Version:      ${caps.backendVersion}');
print('Reads files:  ${caps.canReadFromFile}');
print('Reads bytes:  ${caps.canReadFromBytes}');
print('Writes files: ${caps.canWriteToFile}');
print('Formats:      ${caps.supportedFormats}');
```

## Implementing a custom backend

To build your own backend, depend on `audio_tags_interface` and implement the
`AudioMetadataBackend` interface:

```yaml
# pubspec.yaml
dependencies:
  audio_tags_interface: ^0.1.0
```

```dart
import 'package:audio_tags_interface/audio_tags_interface.dart';

final class MyCustomBackend implements AudioMetadataBackend {
  @override
  String get id => 'my_custom';

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
    // Your implementation here.
    // Parse the file at [path] and return an AudioMetadataDocument.
    return AudioMetadataDocument(
      metadata: AudioMetadata(
        title: 'Parsed title',
        artist: 'Parsed artist',
      ),
      properties: options.readProperties
          ? AudioProperties(
              duration: Duration(seconds: 180),
              bitrate: 320,
              sampleRate: 44100,
              channels: 2,
            )
          : null,
      backendId: id,
    );
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async {
    // Implement if your backend supports in-memory parsing.
    // Otherwise, throw UnsupportedError.
    throw UnsupportedError('$id does not support reading from bytes');
  }

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    // Implement if your backend supports writing.
    // Otherwise, throw UnsupportedError.
    throw UnsupportedError('$id does not support writing');
  }

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    throw UnsupportedError('$id does not support writing to bytes');
  }

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

### Using your custom backend

```dart
import 'package:audio_tags/audio_tags.dart';
import 'package:my_backend_package/my_backend_package.dart';

void main() async {
  // Use directly.
  final service = AudioMetadataService(backend: MyCustomBackend());
  final doc = await service.read('song.mp3');

  // Or set as the global default.
  AudioMetadataConfig.instance.defaultBackend = MyCustomBackend();

  // Or register for dynamic lookup.
  AudioMetadataBackendRegistry.instance.register(
    'my_custom',
    () => MyCustomBackend(),
  );
}
```

### Backend contract

Every backend must:

- Return `AudioMetadataDocument` from read operations with all requested
  sections populated (metadata, properties, pictures, rawTags) according to
  the `AudioReadOptions` flags
- Set `backendId` to the backend's `id` on every returned document
- Translate implementation-specific failures into the appropriate
  `AudioMetadataException` subclass:
  - `AudioFormatUnsupportedException` when the file format is not supported
  - `AudioMetadataReadException` when a read operation fails
  - `AudioMetadataWriteException` when a write operation fails
  - `AudioBackendUnavailableException` when the backend cannot initialize
- Throw `UnsupportedError` for operations the backend does not support
  (e.g. `readFromBytes` if the backend only works with files)
- Report accurate capabilities via `getCapabilities()` — do not advertise
  capabilities that are not implemented
- Preserve metadata fields not referenced in a `AudioMetadataPatch` during
  write operations (non-destructive writes)

## Data model

### AudioMetadataDocument

The top-level result from a read operation:

| Field | Type | Description |
|-------|------|-------------|
| `metadata` | `AudioMetadata` | Normalized common metadata fields |
| `properties` | `AudioProperties?` | Audio stream properties |
| `pictures` | `List<AudioPicture>` | Embedded pictures |
| `rawTags` | `List<AudioRawTag>` | Raw tag data |
| `format` | `String?` | File format (e.g. `mp3`, `flac`) |
| `container` | `String?` | Container format |
| `backendId` | `String` | Which backend produced this result |

### AudioMetadata

Normalized common fields:

| Field | Type |
|-------|------|
| `title` | `String?` |
| `artist` | `String?` |
| `album` | `String?` |
| `albumArtist` | `String?` |
| `genre` | `String?` |
| `comment` | `String?` |
| `composer` | `String?` |
| `lyricist` | `String?` |
| `grouping` | `String?` |
| `year` | `int?` |
| `trackNumber` | `int?` |
| `trackTotal` | `int?` |
| `discNumber` | `int?` |
| `discTotal` | `int?` |
| `lyrics` | `String?` |
| `extras` | `Map<String, Object?>` |

### AudioMetadataPatch

Describes requested edits for a write operation:

| Field | Type | Description |
|-------|------|-------------|
| `setFields` | `Map<AudioTagField, Object?>` | Fields to set (null = remove) |
| `clearFields` | `Set<AudioTagField>` | Fields to clear |
| `pictureOperations` | `List<AudioPictureOperation>` | Picture edits |
| `rawMutations` | `Map<String, Object?>` | Arbitrary tag key mutations |

### AudioProperties

| Field | Type |
|-------|------|
| `duration` | `Duration?` |
| `bitrate` | `int?` (kbps) |
| `sampleRate` | `int?` (Hz) |
| `channels` | `int?` |
| `bitDepth` | `int?` |

### AudioTagField

Enum of standard fields used in `AudioMetadataPatch`:

`title`, `artist`, `album`, `albumArtist`, `genre`, `comment`, `composer`,
`lyricist`, `grouping`, `year`, `trackNumber`, `trackTotal`, `discNumber`,
`discTotal`, `lyrics`

### AudioPicture

| Field | Type |
|-------|------|
| `type` | `AudioPictureType` |
| `mimeType` | `String?` |
| `description` | `String?` |
| `data` | `Uint8List` |

### AudioPictureType

21 standard types including `frontCover`, `backCover`, `bandLogo`,
`illustration`, and more.

### AudioReadOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `readProperties` | `bool` | `true` | Include audio stream properties |
| `readPictures` | `bool` | `false` | Include embedded pictures |
| `readChapters` | `bool` | `false` | Include chapter markers (ID3v2 CHAP) |
| `readRawTags` | `bool` | `false` | Include raw tag data |

### AudioWriteOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `stripOtherTags` | `bool` | `false` | Strip tags not referenced in patch |

### AudioBackendCapabilities

| Field | Type | Description |
|-------|------|-------------|
| `backendVersion` | `String?` | Backend engine version |
| `canReadFromFile` | `bool` | Supports file-based reads |
| `canReadFromBytes` | `bool` | Supports in-memory reads |
| `canWriteToFile` | `bool` | Supports file-based writes |
| `canWriteToBytes` | `bool` | Supports in-memory writes |
| `canReadPictures` | `bool` | Supports reading pictures |
| `canWritePictures` | `bool` | Supports writing pictures |
| `canReadChapters` | `bool` | Supports reading chapter markers |
| `canReadRawTags` | `bool` | Exposes raw property-map view |
| `supportedFormats` | `Set<String>` | File extensions that can be read |
| `writableFormats` | `Set<String>` | File extensions that can be written |

## Error handling

All errors are expressed as Dart exceptions with a sealed hierarchy:

```
sealed class AudioMetadataException implements Exception
  +-- AudioFormatUnsupportedException
  +-- AudioMetadataReadException
  +-- AudioMetadataWriteException
  +-- AudioBackendUnavailableException
  +-- AudioOperationUnsupportedException
```

Each subclass carries `message`, optional `path`, and optional `cause`:

```dart
try {
  await service.read('unknown.xyz');
} on AudioFormatUnsupportedException catch (e) {
  print('Unsupported format at ${e.path}: ${e.message}');
}
```

```dart
try {
  await service.read('unknown.xyz');
} on AudioMetadataReadException catch (e) {
  print('Read failed: ${e.message}');
} on AudioMetadataException catch (e) {
  print('Other error: $e');
}
```

Exhaustive switch on the sealed type:

```dart
switch (exception) {
  case AudioFormatUnsupportedException(): // ...
  case AudioMetadataReadException(): // ...
  case AudioMetadataWriteException(): // ...
  case AudioBackendUnavailableException(): // ...
  case AudioOperationUnsupportedException(): // ...
}
```

## Testing with a fake backend

The backend-agnostic design makes testing straightforward. Create a fake that
implements the interface, then inject it:

```dart
import 'package:audio_tags_interface/audio_tags_interface.dart';

final class FakeBackend implements AudioMetadataBackend {
  @override
  String get id => 'fake';

  @override
  String? get version => null;

  @override
  bool get supportsReading => true;

  @override
  bool get supportsWriting => true;

  @override
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  ) async {
    return AudioMetadataDocument(
      metadata: AudioMetadata(title: 'Mock Title'),
      backendId: id,
    );
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async =>
      throw UnsupportedError('fake');

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {}

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async =>
      throw UnsupportedError('fake');

  @override
  Future<AudioBackendCapabilities> getCapabilities() async {
    return AudioBackendCapabilities(
      canReadFromFile: true,
      canReadFromBytes: false,
      canWriteToFile: true,
      canWriteToBytes: false,
      canReadPictures: false,
      canWritePictures: false,
      supportedFormats: {'mp3'},
      writableFormats: {'mp3'},
    );
  }
}
```

```dart
// In your test:
final service = AudioMetadataService(backend: FakeBackend());
final doc = await service.read('test.mp3');
expect(doc.metadata.title, 'Mock Title');
```

## Packages

This is a Dart pub workspace (monorepo) with three packages:

| Package | Purpose | Depends on |
|---------|---------|------------|
| `audio_tags_interface` | Core models, backend interface, errors | nothing |
| `audio_tags_taglib` | TagLib backend (FFI + C shim + prebuilt binaries) | interface |
| `audio_tags` | User-facing package (batteries-included) | interface + taglib |

```
packages/
  audio_tags_interface/
    lib/src/model/               Data model classes
    lib/src/backend/             Backend interface, capabilities, registry
    lib/src/errors/              Sealed exception hierarchy

  audio_tags_taglib/
    lib/src/                     TagLib backend + FFI bindings
    src/                         C shim source (taglib_shim.cpp/.h)
    prebuilt/                    Prebuilt native binaries per platform
    hook/build.dart              Native asset build hook
    build_linux.sh               Linux prebuilt build script
    build_windows.ps1            Windows prebuilt build script

  audio_tags/
    lib/src/service/             AudioMetadataService
    lib/src/config/              AudioMetadataConfig (default = TagLib)
```

End users depend on `audio_tags`. Backend authors depend on `audio_tags_interface`.

## Roadmap

- **Phase 1** (shipped 0.1.0): Core API, TagLib backend, file-based read/write,
  common fields, monorepo split, integration tests
- **Phase 2** (shipped 0.4.0): Lofty (Rust) alternative backend, full picture
  read/write across all supported formats, format/container detection,
  extras, in-memory bytes API, chapter reading, honest capability reporting,
  comprehensive cross-backend test suite
- **Phase 3**: Multi-value field accessors as a first-class API,
  synchronized lyrics (LRC / SYLT) write support, more platform-specific
  optimisations

## License

See [LICENSE](LICENSE) for details.
