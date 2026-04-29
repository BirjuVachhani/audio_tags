import 'dart:io';

import 'package:audio_tags_interface/audio_tags_interface.dart';

import 'lofty_bindings.dart';

/// Audio metadata backend powered by Lofty (lofty-rs) via FFI.
final class LoftyAudioMetadataBackend implements AudioMetadataBackend {
  static const Set<String> _supportedFormats = {
    'mp3',
    'flac',
    'ogg',
    'oga',
    'opus',
    'mp4',
    'm4a',
    'm4b',
    'aac',
    'wav',
    'aiff',
    'aif',
    'ape',
    'mpc',
    'wv',
    'spx',
  };

  static const Set<String> _writableFormats = {
    'mp3',
    'flac',
    'ogg',
    'oga',
    'opus',
    'mp4',
    'm4a',
    'm4b',
    'aac',
    'wav',
    'aiff',
    'aif',
    'ape',
    'mpc',
    'wv',
  };

  @override
  String get id => 'lofty';

  @override
  String get version => LoftyBindings.version;

  @override
  bool get supportsReading => true;

  @override
  bool get supportsWriting => true;

  @override
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  ) async {
    _validateExists(path, forRead: true);
    try {
      return LoftyBindings.readFile(path, options);
    } on AudioMetadataException {
      rethrow;
    } catch (e) {
      throw _classifyReadFailure(path, e.toString(), cause: e);
    }
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async {
    throw const AudioOperationUnsupportedException(
      'Lofty backend does not support reading from in-memory bytes. Use '
      'AudioMetadataService.readBytes() to fall back to a temporary file.',
    );
  }

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    _validateExists(path, forRead: false);
    if (patch.isEmpty) return;
    final LoftyWriteResult result;
    try {
      result = LoftyBindings.writeFile(path, patch, options);
    } catch (e) {
      throw AudioMetadataWriteException(
        'Failed to write metadata',
        path: path,
        cause: e,
      );
    }
    if (result.ok) return;
    throw _classifyWriteFailure(path, result);
  }

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    throw const AudioOperationUnsupportedException(
      'Lofty backend does not support writing to in-memory bytes. Use '
      'AudioMetadataService.writeBytes() to fall back to a temporary file.',
    );
  }

  @override
  Future<AudioBackendCapabilities> getCapabilities() async {
    return AudioBackendCapabilities(
      backendVersion: version,
      canReadFromFile: true,
      canReadFromBytes: false,
      canWriteToFile: true,
      canWriteToBytes: false,
      canReadPictures: true,
      canWritePictures: true,
      canReadChapters: false,
      canReadRawTags: true,
      supportedFormats: _supportedFormats,
      writableFormats: _writableFormats,
    );
  }

  // ---- Helpers -----------------------------------------------------------

  static void _validateExists(String path, {required bool forRead}) {
    final file = File(path);
    if (!file.existsSync()) {
      if (forRead) {
        throw AudioMetadataReadException('File does not exist', path: path);
      }
      throw AudioMetadataWriteException('File does not exist', path: path);
    }
  }

  AudioMetadataException _classifyReadFailure(
    String path,
    String nativeMessage, {
    Object? cause,
  }) {
    final lower = nativeMessage.toLowerCase();
    if (lower.contains('recognize') ||
        lower.contains('unknown file format') ||
        lower.contains('unsupported')) {
      return AudioFormatUnsupportedException(
        'Could not recognise audio format',
        path: path,
        cause: cause,
      );
    }
    return AudioMetadataReadException(
      nativeMessage.isEmpty ? 'Failed to read metadata' : nativeMessage,
      path: path,
      cause: cause,
    );
  }

  AudioMetadataException _classifyWriteFailure(
    String path,
    LoftyWriteResult result,
  ) {
    final msg = result.message.isEmpty
        ? 'Write failed (code ${result.code})'
        : result.message;
    return switch (result.code) {
      -1 => AudioMetadataReadException(msg, path: path),
      -2 => AudioFormatUnsupportedException(msg, path: path),
      -3 => AudioMetadataWriteException('Invalid patch: $msg', path: path),
      -4 => AudioMetadataWriteException(msg, path: path),
      -5 => AudioMetadataWriteException(
        'Picture operation failed: $msg',
        path: path,
      ),
      _ => AudioMetadataWriteException(msg, path: path),
    };
  }
}
