import '../model/audio_metadata_document.dart';
import '../model/audio_metadata_patch.dart';
import '../model/audio_read_options.dart';
import '../model/audio_write_options.dart';
import 'audio_backend_capabilities.dart';

/// Interface that all audio metadata backends must implement.
abstract interface class AudioMetadataBackend {
  /// Unique identifier for this backend (e.g. 'taglib', 'lofty').
  String get id;

  /// The version of the underlying backend engine (e.g. '2.2.1').
  ///
  /// Returns `null` if the backend does not report a version.
  String? get version;

  /// Whether this backend supports reading metadata.
  bool get supportsReading;

  /// Whether this backend supports writing metadata.
  bool get supportsWriting;

  /// Read metadata from a file on disk.
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  );

  /// Read metadata from raw bytes in memory.
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  );

  /// Write metadata to a file on disk.
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  );

  /// Write metadata to raw bytes in memory.
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  );

  /// Query the capabilities of this backend.
  Future<AudioBackendCapabilities> getCapabilities();
}
