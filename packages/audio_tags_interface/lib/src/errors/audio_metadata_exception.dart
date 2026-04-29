/// Base exception type for all audio metadata errors.
sealed class AudioMetadataException implements Exception {
  /// Human-readable description of the failure.
  final String message;

  /// Path or identifier of the file the failure relates to, if known.
  final String? path;

  /// The underlying cause if the failure was triggered by another error.
  final Object? cause;

  const AudioMetadataException(this.message, {this.path, this.cause});

  @override
  String toString() {
    final loc = path == null ? '' : ' for "$path"';
    final c = cause == null ? '' : ' (cause: $cause)';
    return '$runtimeType: $message$loc$c';
  }
}

/// Thrown when the file format is not recognised or not supported by the
/// backend.
final class AudioFormatUnsupportedException extends AudioMetadataException {
  const AudioFormatUnsupportedException(
    super.message, {
    super.path,
    super.cause,
  });
}

/// Thrown when the file could not be opened — usually missing, permission
/// denied, or corrupt.
final class AudioMetadataReadException extends AudioMetadataException {
  const AudioMetadataReadException(super.message, {super.path, super.cause});
}

/// Thrown when writing metadata to the file failed.
final class AudioMetadataWriteException extends AudioMetadataException {
  const AudioMetadataWriteException(super.message, {super.path, super.cause});
}

/// Thrown when the requested backend is not registered or cannot be loaded.
final class AudioBackendUnavailableException extends AudioMetadataException {
  const AudioBackendUnavailableException(super.message, {super.cause});
}

/// Thrown when a requested operation is not supported by the active backend.
///
/// Distinct from [UnsupportedError] in that it is part of the
/// [AudioMetadataException] hierarchy, so callers can handle all metadata
/// failures with a single `catch (AudioMetadataException)`.
final class AudioOperationUnsupportedException extends AudioMetadataException {
  const AudioOperationUnsupportedException(super.message, {super.cause});
}
