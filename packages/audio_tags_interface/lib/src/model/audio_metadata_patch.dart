import 'package:meta/meta.dart';

import 'audio_picture.dart';
import 'audio_tag_field.dart';

/// Describes requested edits to audio metadata.
///
/// All fields are optional. An empty patch is a no-op.
///
/// Mutation precedence within a single write:
///   1. [pictureOperations] are applied in order against the file's picture
///      list. To replace artwork, queue a [RemoveAllPicturesOperation]
///      followed by an [AddPictureOperation].
///   2. [setFields] writes (or, when the value is `null`, clears) the named
///      normalized fields.
///   3. [clearFields] removes the named normalized fields. Equivalent to
///      `setFields: {field: null}`.
///   4. [rawMutations] writes (or clears, on `null` value) arbitrary
///      property-map keys. Useful for fields not represented in
///      [AudioTagField] such as `ISRC`, `MUSICBRAINZ_*`, or `REPLAYGAIN_*`.
@immutable
final class AudioMetadataPatch {
  /// Fields to set. Values are usually `String` or `int`; pass `null` to
  /// clear a field. Lists of strings are accepted and written as multi-value
  /// where the underlying tag format supports it.
  final Map<AudioTagField, Object?> setFields;

  /// Fields to remove from the file.
  final Set<AudioTagField> clearFields;

  /// Picture add/remove operations to apply in order.
  final List<AudioPictureOperation> pictureOperations;

  /// Arbitrary property-map mutations. Keys are upper-case property-map names
  /// (e.g. `ISRC`, `MUSICBRAINZ_TRACKID`). Values may be `String`,
  /// `List<String>`, a number, or `null` (to clear).
  final Map<String, Object?> rawMutations;

  const AudioMetadataPatch({
    this.setFields = const {},
    this.clearFields = const {},
    this.pictureOperations = const [],
    this.rawMutations = const {},
  });

  /// Whether this patch contains any changes.
  bool get isEmpty =>
      setFields.isEmpty &&
      clearFields.isEmpty &&
      pictureOperations.isEmpty &&
      rawMutations.isEmpty;

  bool get isNotEmpty => !isEmpty;

  AudioMetadataPatch copyWith({
    Map<AudioTagField, Object?>? setFields,
    Set<AudioTagField>? clearFields,
    List<AudioPictureOperation>? pictureOperations,
    Map<String, Object?>? rawMutations,
  }) {
    return AudioMetadataPatch(
      setFields: setFields ?? this.setFields,
      clearFields: clearFields ?? this.clearFields,
      pictureOperations: pictureOperations ?? this.pictureOperations,
      rawMutations: rawMutations ?? this.rawMutations,
    );
  }
}
