import 'package:meta/meta.dart';

/// A raw tag container as returned by the backend.
///
/// Represents a single tag type (e.g., ID3v2, Vorbis comment) with its
/// raw key-value fields before normalization.
@immutable
final class AudioRawTag {
  /// The tag-format identifier — one of `ID3v1`, `ID3v2`, `MP4`,
  /// `VorbisComments`, `RIFF`, `APE`, `AIFFText`, or `properties` for the
  /// backend's normalized property-map view.
  final String tagType;

  /// Field key/value map. Values are lists because tag formats may store
  /// multiple values per key (e.g. multiple `ARTIST` entries in Vorbis).
  final Map<String, List<String>> fields;

  const AudioRawTag({required this.tagType, this.fields = const {}});

  AudioRawTag copyWith({String? tagType, Map<String, List<String>>? fields}) {
    return AudioRawTag(
      tagType: tagType ?? this.tagType,
      fields: fields ?? this.fields,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! AudioRawTag) return false;
    if (tagType != other.tagType) return false;
    if (fields.length != other.fields.length) return false;
    for (final entry in fields.entries) {
      final otherList = other.fields[entry.key];
      if (otherList == null || otherList.length != entry.value.length) {
        return false;
      }
      for (var i = 0; i < entry.value.length; i++) {
        if (entry.value[i] != otherList[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(tagType, Object.hashAllUnordered(fields.keys));

  @override
  String toString() => 'AudioRawTag($tagType, ${fields.length} fields)';
}
