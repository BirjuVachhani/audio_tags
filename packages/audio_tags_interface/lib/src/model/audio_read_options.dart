/// Options for reading audio metadata.
final class AudioReadOptions {
  /// Whether to read audio stream properties (duration, bitrate, etc).
  final bool readProperties;

  /// Whether to read embedded pictures.
  final bool readPictures;

  /// Whether to read chapter markers (ID3v2 CHAP frames for MP3).
  final bool readChapters;

  /// Whether to include raw tag data.
  final bool readRawTags;

  const AudioReadOptions({
    this.readProperties = true,
    this.readPictures = false,
    this.readChapters = false,
    this.readRawTags = false,
  });
}
