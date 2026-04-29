Dart Audio Metadata Library Architecture

Goal

Build a Dart-first audio metadata library that:
	•	works in plain Dart and Flutter on native platforms
	•	supports CLI tools, server apps, desktop apps, and mobile apps
	•	uses pluggable backends
	•	defaults to TagLib as the production backend
	•	allows swapping the backend with any compatible implementation
	•	keeps the public Dart API stable even if the backend changes

⸻

Core design principles

1. Dart-first public API

The public package API should feel like a normal idiomatic Dart package.

Users should interact with Dart types such as:
	•	AudioMetadata
	•	AudioPicture
	•	AudioProperties
	•	AudioTagField
	•	AudioMetadataEditor
	•	AudioMetadataBackend

The public API must not leak TagLib-specific or backend-specific concepts unless intentionally exposed through an advanced escape hatch.

⸻

2. Backend-agnostic architecture

The library should support multiple interchangeable backends.

Examples:
	•	TaglibAudioMetadataBackend — default
	•	LoftyAudioMetadataBackend — optional future Rust backend
	•	PureDartAudioMetadataBackend — optional future limited backend
	•	MockAudioMetadataBackend — testing backend
	•	CustomAudioMetadataBackend — user-defined implementation

All backends should conform to the same interface contract.

⸻

3. Stable Dart API, replaceable implementation

The library should be designed so that backend choice is an implementation detail.

This gives several benefits:
	•	the package can start with TagLib and evolve later
	•	specific backends can be optimized for platform or file format needs
	•	tests can run against a fake backend
	•	CLI and Flutter apps can share the same library API

⸻

4. Default backend should be TagLib

TagLib should be the default backend because it is a mature and broad metadata engine.

However, the architecture must never assume that TagLib is the only backend.

The package should make TagLib the default through configuration and package wiring, not by hard-coding TagLib concepts into the public API.

⸻

High-level package layout

The project is a Dart pub workspace (monorepo):

packages/
  audio_tags_interface/          Core interface for backend authors
    lib/
      audio_tags_interface.dart
      src/
        model/                   Data models (AudioMetadata, etc.)
        backend/                 AudioMetadataBackend interface, capabilities, registry
        errors/                  Sealed exception hierarchy
    pubspec.yaml

  audio_tags_taglib/             TagLib backend
    lib/
      audio_tags_taglib.dart
      src/
        taglib_audio_metadata_backend.dart
        taglib_bindings.dart     FFI bridge
    src/                         C shim source (taglib_shim.cpp/.h)
    prebuilt/                    Prebuilt native binaries per platform
    hook/build.dart              Native asset build hook
    build_linux.sh               Build script for Linux prebuilts
    build_windows.ps1            Build script for Windows prebuilts
    pubspec.yaml

  audio_tags/                    User-facing package (batteries-included)
    lib/
      audio_tags.dart            Re-exports interface + taglib + service + config
      src/
        service/                 AudioMetadataService
        config/                  AudioMetadataConfig (default backend = TagLib)
    pubspec.yaml

Dependency flow:

  audio_tags_interface  <──  audio_tags_taglib
           ^                        ^
           └──── audio_tags ────────┘

End users depend on audio_tags. Backend authors depend on audio_tags_interface.

⸻

Public API design

Main entrypoint

library audio_metadata;

export 'src/model/audio_metadata.dart';
export 'src/model/audio_picture.dart';
export 'src/model/audio_properties.dart';
export 'src/model/audio_tag_field.dart';
export 'src/backend/audio_metadata_backend.dart';
export 'src/service/audio_metadata_service.dart';
export 'src/config/audio_metadata_config.dart';


⸻

Backend abstraction

The central abstraction should be an interface like this:

abstract interface class AudioMetadataBackend {
  String get id;
  bool get supportsReading;
  bool get supportsWriting;

  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  );

  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  );

  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  );

  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  );

  Future<AudioBackendCapabilities> getCapabilities();
}

Notes
	•	id identifies the backend, such as taglib, lofty, or pure_dart.
	•	readFromFile and writeToFile are the main workflow for CLI and apps.
	•	readFromBytes and writeToBytes allow in-memory workflows where feasible.
	•	getCapabilities lets callers detect backend limitations at runtime.

⸻

Service layer

The service layer should be what most users call.

final class AudioMetadataService {
  AudioMetadataService({AudioMetadataBackend? backend})
      : _backend = backend ?? AudioMetadataConfig.instance.defaultBackend;

  final AudioMetadataBackend _backend;

  Future<AudioMetadataDocument> read(String path, {AudioReadOptions? options}) {
    return _backend.readFromFile(path, options ?? const AudioReadOptions());
  }

  Future<void> write(
    String path,
    AudioMetadataPatch patch, {
    AudioWriteOptions? options,
  }) {
    return _backend.writeToFile(
      path,
      patch,
      options ?? const AudioWriteOptions(),
    );
  }
}

Why a service layer is useful

It gives a stable place for:
	•	backend selection
	•	default behavior
	•	convenience overloads
	•	validation
	•	future caching or diagnostics

Most users should not need to interact with raw backend classes directly.

⸻

Global and local backend selection

The library should support both:

Global default

AudioMetadataConfig.instance.defaultBackend = TaglibAudioMetadataBackend();

Per-instance override

final service = AudioMetadataService(
  backend: LoftyAudioMetadataBackend(),
);

Scoped override for tests

final service = AudioMetadataService(
  backend: FakeAudioMetadataBackend(),
);

This makes the library ergonomic while still being extensible.

⸻

Configuration model

final class AudioMetadataConfig {
  AudioMetadataConfig._();

  static final AudioMetadataConfig instance = AudioMetadataConfig._();

  AudioMetadataBackend defaultBackend = TaglibAudioMetadataBackend();
}

Design note

Avoid global mutable state in core logic where possible. Global config is useful for convenience, but service-level dependency injection should remain the preferred model for advanced apps and tests.

⸻

Data model

AudioMetadataDocument

Represents the full parsed view of a file.

final class AudioMetadataDocument {
  final AudioMetadata metadata;
  final AudioProperties? properties;
  final List<AudioPicture> pictures;
  final List<AudioRawTag> rawTags;
  final String? format;
  final String? container;
  final String backendId;
}

AudioMetadata

Represents normalized common metadata fields.

final class AudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final String? comment;
  final String? composer;
  final String? lyricist;
  final String? grouping;
  final int? year;
  final int? trackNumber;
  final int? trackTotal;
  final int? discNumber;
  final int? discTotal;
  final String? lyrics;
  final Map<String, Object?> extras;
}

AudioMetadataPatch

Represents requested edits.

final class AudioMetadataPatch {
  final Map<AudioTagField, Object?> setFields;
  final Set<AudioTagField> clearFields;
  final List<AudioPictureOperation> pictureOperations;
  final Map<String, Object?> rawMutations;
}

AudioProperties

final class AudioProperties {
  final Duration? duration;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? bitDepth;
}

AudioPicture

final class AudioPicture {
  final AudioPictureType type;
  final String? mimeType;
  final String? description;
  final List<int> data;
}


⸻

Capability model

Backends will not all support the same formats or operations.

Expose that explicitly.

final class AudioBackendCapabilities {
  final bool canReadFromFile;
  final bool canReadFromBytes;
  final bool canWriteToFile;
  final bool canWriteToBytes;
  final bool canReadPictures;
  final bool canWritePictures;
  final Set<String> supportedFormats;
  final Set<String> writableFormats;
}

This avoids pretending that all backends are equally capable.

⸻

Default TagLib backend

Class shape

final class TaglibAudioMetadataBackend implements AudioMetadataBackend {
  @override
  String get id => 'taglib';

  @override
  bool get supportsReading => true;

  @override
  bool get supportsWriting => true;

  @override
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  ) async {
    // FFI bridge call
    throw UnimplementedError();
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async {
    throw UnsupportedError('TagLib backend initially supports file-based reads only');
  }

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    // FFI bridge call
  }

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    throw UnsupportedError('TagLib backend initially supports file-based writes only');
  }

  @override
  Future<AudioBackendCapabilities> getCapabilities() async {
    throw UnimplementedError();
  }
}

Important design rule

The TagLib backend should convert native results into the common Dart model immediately.

Do not let the rest of the package depend on TagLib-native structures.

⸻

Native bridge boundary

The TagLib-specific code should live behind a narrow internal adapter.

Example layers:

Public Dart API
  -> Service layer
    -> Backend interface
      -> TagLib backend
        -> FFI adapter
          -> Custom C shim
            -> TagLib

Why a C shim is useful

A thin custom C shim gives you:
	•	stable FFI surface for Dart
	•	simpler memory ownership rules
	•	a small, deliberate API
	•	freedom to use more of TagLib internally without exposing C++ complexity directly

The shim should expose only the operations your Dart API actually needs.

⸻

Native result conversion strategy

Prefer returning normalized native payloads that are easy to decode in Dart.

Two good options:

Option A: field-by-field FFI structs

Good for performance-sensitive fixed shapes.

Option B: serialized JSON from native layer

Good for development speed and simpler schema evolution.

Recommended approach

Use:
	•	fixed structs for simple primitives if needed later
	•	JSON payloads for metadata documents in the initial implementation

This keeps the bridge simple while the API stabilizes.

⸻

Backend registry

Allow registering backends dynamically.

final class AudioMetadataBackendRegistry {
  AudioMetadataBackendRegistry._();

  static final instance = AudioMetadataBackendRegistry._();

  final Map<String, AudioMetadataBackend Function()> _factories = {};

  void register(String id, AudioMetadataBackend Function() factory) {
    _factories[id] = factory;
  }

  AudioMetadataBackend create(String id) {
    final factory = _factories[id];
    if (factory == null) {
      throw StateError('No backend registered for $id');
    }
    return factory();
  }
}

Benefit

This lets advanced users provide custom backends without forking the package.

⸻

Error model

Backends should not throw raw native exceptions or opaque FFI failures directly.

Use Dart exceptions such as:

sealed class AudioMetadataException implements Exception {
  final String message;
  const AudioMetadataException(this.message);
}

final class AudioFormatUnsupportedException extends AudioMetadataException {
  const AudioFormatUnsupportedException(super.message);
}

final class AudioMetadataReadException extends AudioMetadataException {
  const AudioMetadataReadException(super.message);
}

final class AudioMetadataWriteException extends AudioMetadataException {
  const AudioMetadataWriteException(super.message);
}

final class AudioBackendUnavailableException extends AudioMetadataException {
  const AudioBackendUnavailableException(super.message);
}

Rule

Every backend should translate implementation-specific failures into these Dart-level exceptions.

⸻

Testing strategy

The architecture should make testing easy.

Unit tests

Use a fake backend:

final class FakeAudioMetadataBackend implements AudioMetadataBackend {
  // returns deterministic in-memory results
}

Integration tests

Run against:
	•	real TagLib backend
	•	fixture files for MP3, FLAC, MP4, Ogg, WAV, and others
	•	round-trip read/write verification

Contract tests

Every backend must pass the same contract suite:
	•	can read common fields
	•	preserves fields not touched by patch
	•	reports unsupported operations consistently
	•	returns correct capability flags

This is critical for making backend swapping trustworthy.

⸻

CLI compatibility

The package should be designed as a plain Dart package first, not a Flutter plugin.

That means:
	•	no Flutter dependency in the core package
	•	all public APIs usable from dart run
	•	file-based workflows should be first-class
	•	asynchronous APIs should work cleanly in CLI tools

Example CLI usage

import 'package:audio_metadata/audio_metadata.dart';

Future<void> main() async {
  final service = AudioMetadataService();

  final doc = await service.read('song.mp3');
  print(doc.metadata.title);

  await service.write(
    'song.mp3',
    AudioMetadataPatch(
      setFields: {
        AudioTagField.title: 'New Title',
      },
      clearFields: {},
      pictureOperations: [],
      rawMutations: {},
    ),
  );
}


⸻

Flutter compatibility

Flutter apps on native platforms should be able to use the same API without any Flutter-specific integration in the core library.

A separate helper package can exist later if UI-specific helpers are useful, but the metadata engine should stay framework-agnostic.

⸻

Web strategy

The backend architecture should acknowledge that web support is different.

Recommended approach:
	•	keep the core API backend-agnostic
	•	do not promise TagLib on web
	•	optionally provide a future web-safe backend
	•	optionally provide a pure Dart read-only backend for limited formats

This means the public package remains future-friendly without overpromising web support from day one.

⸻

Progressive implementation plan

Phase 1

Implement the core package with:
	•	backend abstraction
	•	normalized Dart data model
	•	TagLib backend
	•	file-based read/write
	•	common fields only
	•	integration tests with fixtures

Phase 2

Add:
	•	pictures
	•	richer raw field access
	•	capability reporting
	•	backend registry

Phase 3

Add optional alternate backends:
	•	Lofty backend
	•	pure Dart limited backend
	•	test/mock backend package if split becomes useful

Phase 4

Add platform-specific optimizations and advanced format features.

⸻

Recommended package philosophy

Public promise

The package should promise:
	•	stable Dart API
	•	backend pluggability
	•	TagLib as the default backend
	•	framework-agnostic usage on Dart Native

The package should not promise
	•	identical behavior across every backend
	•	complete capability parity across all platforms
	•	full web support from the first release

Be explicit about backend capability differences.

⸻

Example usage

Default backend

final service = AudioMetadataService();
final doc = await service.read('track.flac');

Explicit TagLib backend

final service = AudioMetadataService(
  backend: TaglibAudioMetadataBackend(),
);

Alternate backend

final service = AudioMetadataService(
  backend: LoftyAudioMetadataBackend(),
);

Global configuration

AudioMetadataConfig.instance.defaultBackend = TaglibAudioMetadataBackend();

Custom backend

final service = AudioMetadataService(
  backend: MyCustomBackend(),
);


⸻

Final recommendation

Build the package as a Dart-first, backend-pluggable metadata library.

Use TagLib as the default backend, but treat it strictly as an internal implementation detail behind a stable Dart interface.

That gives you the best balance of:
	•	immediate reliability
	•	CLI and Flutter compatibility on native platforms
	•	future backend flexibility
	•	long-term maintainability

The most important architectural rule is this:

The public API belongs to Dart. The backend is replaceable.

That single rule will keep the library flexible, testable, and future-proof.