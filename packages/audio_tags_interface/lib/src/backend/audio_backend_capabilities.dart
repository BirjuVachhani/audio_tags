import 'package:meta/meta.dart';

/// Describes the capabilities of an audio metadata backend.
@immutable
final class AudioBackendCapabilities {
  /// The version of the underlying backend engine (e.g. '2.2.1' for TagLib).
  final String? backendVersion;
  final bool canReadFromFile;
  final bool canReadFromBytes;
  final bool canWriteToFile;
  final bool canWriteToBytes;

  /// Whether the backend can read embedded pictures.
  final bool canReadPictures;

  /// Whether the backend can add, remove, or replace embedded pictures.
  final bool canWritePictures;

  /// Whether the backend can read chapter markers.
  final bool canReadChapters;

  /// Whether the backend exposes raw tag fields (full property-map view).
  final bool canReadRawTags;

  /// File extensions (lowercase, no leading dot) the backend can read.
  final Set<String> supportedFormats;

  /// File extensions (lowercase, no leading dot) the backend can write.
  final Set<String> writableFormats;

  const AudioBackendCapabilities({
    this.backendVersion,
    required this.canReadFromFile,
    required this.canReadFromBytes,
    required this.canWriteToFile,
    required this.canWriteToBytes,
    required this.canReadPictures,
    required this.canWritePictures,
    this.canReadChapters = false,
    this.canReadRawTags = true,
    required this.supportedFormats,
    required this.writableFormats,
  });

  /// Whether this backend can read the given format extension (lowercase, no
  /// leading dot — e.g. `mp3`, `flac`).
  bool supportsRead(String extension) =>
      supportedFormats.contains(extension.toLowerCase());

  /// Whether this backend can write the given format extension.
  bool supportsWrite(String extension) =>
      writableFormats.contains(extension.toLowerCase());

  @override
  String toString() =>
      'AudioBackendCapabilities(version: $backendVersion, '
      'read: $supportedFormats, write: $writableFormats, '
      'pictures r/w: $canReadPictures/$canWritePictures)';
}
