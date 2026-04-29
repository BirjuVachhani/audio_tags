import 'dart:io';
import 'dart:typed_data';

import 'package:audio_tags_interface/audio_tags_interface.dart';

import '../config/audio_metadata_config.dart';

/// High-level service for reading and writing audio metadata.
///
/// Uses the configured default backend unless an explicit backend is provided
/// at construction time.
final class AudioMetadataService {
  AudioMetadataService({AudioMetadataBackend? backend})
    : _backend = backend ?? AudioMetadataConfig.instance.defaultBackend;

  final AudioMetadataBackend _backend;

  /// The backend this service is using.
  AudioMetadataBackend get backend => _backend;

  /// Read metadata from a file at [path].
  Future<AudioMetadataDocument> read(String path, {AudioReadOptions? options}) {
    return _backend.readFromFile(path, options ?? const AudioReadOptions());
  }

  /// Write a [patch] to the file at [path].
  ///
  /// Returns immediately if the patch is empty.
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

  /// Read metadata directly from in-memory [bytes].
  ///
  /// If the active backend supports byte-level reads natively
  /// (`canReadFromBytes == true`), the call is forwarded. Otherwise the bytes
  /// are written to a temporary file (with the optional [extensionHint] —
  /// e.g. `mp3`, `flac` — to help format detection) and read through the
  /// file API instead.
  Future<AudioMetadataDocument> readBytes(
    List<int> bytes, {
    AudioReadOptions? options,
    String? extensionHint,
  }) async {
    final opts = options ?? const AudioReadOptions();
    final caps = await _backend.getCapabilities();
    if (caps.canReadFromBytes) {
      return _backend.readFromBytes(bytes, opts);
    }
    final tmp = await _writeTempFile(bytes, extensionHint);
    try {
      return await _backend.readFromFile(tmp.path, opts);
    } finally {
      _safeDelete(tmp);
    }
  }

  /// Write a [patch] to in-memory [bytes] and return the modified bytes.
  ///
  /// Falls back to a temporary file when the backend does not support
  /// byte-level writes natively.
  Future<Uint8List> writeBytes(
    List<int> bytes,
    AudioMetadataPatch patch, {
    AudioWriteOptions? options,
    String? extensionHint,
  }) async {
    final opts = options ?? const AudioWriteOptions();
    final caps = await _backend.getCapabilities();
    if (caps.canWriteToBytes) {
      final result = await _backend.writeToBytes(bytes, patch, opts);
      return Uint8List.fromList(result);
    }
    final tmp = await _writeTempFile(bytes, extensionHint);
    try {
      await _backend.writeToFile(tmp.path, patch, opts);
      return await tmp.readAsBytes();
    } finally {
      _safeDelete(tmp);
    }
  }

  /// Returns the active backend's capabilities.
  Future<AudioBackendCapabilities> capabilities() => _backend.getCapabilities();

  // ---- Helpers -----------------------------------------------------------

  static Future<File> _writeTempFile(List<int> bytes, String? ext) async {
    final dir = Directory.systemTemp;
    final extension = (ext == null || ext.isEmpty)
        ? 'audio'
        : ext.replaceAll('.', '');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = File('${dir.path}/audio_tags_$stamp.$extension');
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp;
  }

  static void _safeDelete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Best-effort cleanup; swallow.
    }
  }
}
