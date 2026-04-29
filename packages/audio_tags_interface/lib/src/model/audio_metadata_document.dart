import 'package:meta/meta.dart';

import 'audio_chapter.dart';
import 'audio_metadata.dart';
import 'audio_picture.dart';
import 'audio_properties.dart';
import 'audio_raw_tag.dart';

/// Complete parsed view of an audio file's metadata and properties.
@immutable
final class AudioMetadataDocument {
  final AudioMetadata metadata;
  final AudioProperties? properties;
  final List<AudioPicture> pictures;
  final List<AudioChapter> chapters;
  final List<AudioRawTag> rawTags;

  /// File-level format identifier — e.g. `mp3`, `flac`, `ogg-vorbis`,
  /// `opus`, `mp4`, `wav`, `aiff`, `wma`, `ape`, `mpc`, `wv`.
  final String? format;

  /// Tag container identifier — e.g. `ID3v2.4`, `ID3v1`, `MP4`,
  /// `VorbisComments`, `APE`, `RIFF-INFO`. May differ from [format] when
  /// a single file format supports multiple tag containers.
  final String? container;

  /// Identifier of the backend that produced this document (e.g. `taglib`,
  /// `lofty`).
  final String backendId;

  const AudioMetadataDocument({
    required this.metadata,
    this.properties,
    this.pictures = const [],
    this.chapters = const [],
    this.rawTags = const [],
    this.format,
    this.container,
    required this.backendId,
  });

  /// Find the first picture of the given type, or `null` if none exists.
  AudioPicture? pictureOfType(AudioPictureType type) {
    for (final p in pictures) {
      if (p.type == type) return p;
    }
    return null;
  }

  /// Convenience accessor for the front-cover image if present.
  AudioPicture? get frontCover => pictureOfType(AudioPictureType.frontCover);

  AudioMetadataDocument copyWith({
    AudioMetadata? metadata,
    Object? properties = _sentinel,
    List<AudioPicture>? pictures,
    List<AudioChapter>? chapters,
    List<AudioRawTag>? rawTags,
    Object? format = _sentinel,
    Object? container = _sentinel,
    String? backendId,
  }) {
    return AudioMetadataDocument(
      metadata: metadata ?? this.metadata,
      properties: identical(properties, _sentinel)
          ? this.properties
          : properties as AudioProperties?,
      pictures: pictures ?? this.pictures,
      chapters: chapters ?? this.chapters,
      rawTags: rawTags ?? this.rawTags,
      format: identical(format, _sentinel) ? this.format : format as String?,
      container: identical(container, _sentinel)
          ? this.container
          : container as String?,
      backendId: backendId ?? this.backendId,
    );
  }

  @override
  String toString() =>
      'AudioMetadataDocument(format: $format, '
      'container: $container, backend: $backendId, '
      'pictures: ${pictures.length}, chapters: ${chapters.length})';
}

const Object _sentinel = Object();
