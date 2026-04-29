import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Type of embedded picture in audio metadata.
///
/// Indices match the ID3v2 APIC frame picture type values, which are also used
/// by FLAC `METADATA_BLOCK_PICTURE` blocks.
enum AudioPictureType {
  other,
  fileIcon,
  otherFileIcon,
  frontCover,
  backCover,
  leafletPage,
  media,
  leadArtist,
  artist,
  conductor,
  band,
  composer,
  lyricist,
  recordingLocation,
  duringRecording,
  duringPerformance,
  movieScreenCapture,
  colouredFish,
  illustration,
  bandLogo,
  publisherLogo,
}

/// Represents an embedded picture in an audio file.
@immutable
final class AudioPicture {
  final AudioPictureType type;
  final String? mimeType;
  final String? description;
  final Uint8List data;

  const AudioPicture({
    required this.type,
    this.mimeType,
    this.description,
    required this.data,
  });

  AudioPicture copyWith({
    AudioPictureType? type,
    Object? mimeType = _sentinel,
    Object? description = _sentinel,
    Uint8List? data,
  }) {
    return AudioPicture(
      type: type ?? this.type,
      mimeType: identical(mimeType, _sentinel)
          ? this.mimeType
          : mimeType as String?,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
      data: data ?? this.data,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! AudioPicture) return false;
    if (type != other.type ||
        mimeType != other.mimeType ||
        description != other.description ||
        data.length != other.data.length) {
      return false;
    }
    for (var i = 0; i < data.length; i++) {
      if (data[i] != other.data[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(type, mimeType, description, data.length);

  @override
  String toString() =>
      'AudioPicture(type: $type, mimeType: $mimeType, '
      'description: $description, ${data.length} bytes)';
}

const Object _sentinel = Object();

/// Operations that can be performed on pictures during a write.
sealed class AudioPictureOperation {
  const AudioPictureOperation();
}

/// Add a picture to the file.
///
/// Pictures are added without modifying existing ones, except that most
/// formats only allow a single picture of any given [AudioPictureType.frontCover]
/// or [AudioPictureType.backCover] — adding one of these will replace any
/// existing picture of the same type.
final class AddPictureOperation extends AudioPictureOperation {
  final AudioPicture picture;
  const AddPictureOperation(this.picture);

  @override
  bool operator ==(Object other) =>
      other is AddPictureOperation && picture == other.picture;

  @override
  int get hashCode => Object.hash('add', picture);
}

/// Remove all pictures of a given type.
final class RemovePicturesByTypeOperation extends AudioPictureOperation {
  final AudioPictureType type;
  const RemovePicturesByTypeOperation(this.type);

  @override
  bool operator ==(Object other) =>
      other is RemovePicturesByTypeOperation && type == other.type;

  @override
  int get hashCode => Object.hash('removeByType', type);
}

/// Remove all pictures.
final class RemoveAllPicturesOperation extends AudioPictureOperation {
  const RemoveAllPicturesOperation();

  @override
  bool operator ==(Object other) => other is RemoveAllPicturesOperation;

  @override
  int get hashCode => 'removeAll'.hashCode;
}
