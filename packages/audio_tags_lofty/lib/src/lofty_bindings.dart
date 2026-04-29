import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:ffi/ffi.dart';

// Native function signatures — names must match Rust symbols.
// ignore_for_file: non_constant_identifier_names

@Native<Pointer<Utf8> Function()>(
  assetId: 'package:audio_tags_lofty/src/lofty_shim.dart',
)
external Pointer<Utf8> lofty_version();

@Native<Pointer<Utf8> Function()>(
  assetId: 'package:audio_tags_lofty/src/lofty_shim.dart',
)
external Pointer<Utf8> lofty_last_error();

@Native<Pointer<Utf8> Function(Pointer<Utf8>, Int32, Int32, Int32, Int32)>(
  assetId: 'package:audio_tags_lofty/src/lofty_shim.dart',
)
external Pointer<Utf8> lofty_read_file(
  Pointer<Utf8> path,
  int readProperties,
  int readPictures,
  int readChapters,
  int readRawTags,
);

@Native<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>(
  assetId: 'package:audio_tags_lofty/src/lofty_shim.dart',
)
external int lofty_write_file(Pointer<Utf8> path, Pointer<Utf8> patchJson);

@Native<Void Function(Pointer<Utf8>)>(
  assetId: 'package:audio_tags_lofty/src/lofty_shim.dart',
)
external void lofty_free_string(Pointer<Utf8> str);

/// Result of a write call — error code plus optional message.
final class LoftyWriteResult {
  final int code;
  final String message;
  const LoftyWriteResult(this.code, this.message);
  bool get ok => code == 0;
}

/// Internal FFI bridge to the Lofty Rust shim.
///
/// Converts between Dart types and the JSON-based native protocol.
final class LoftyBindings {
  LoftyBindings._();

  /// The version of the underlying Lofty library.
  static String get version => lofty_version().toDartString();

  /// Last error recorded by the most recent shim call on this thread.
  static String get lastError {
    final ptr = lofty_last_error();
    if (ptr == nullptr) return '';
    return ptr.toDartString();
  }

  /// Read metadata from a file using the Lofty native shim.
  static AudioMetadataDocument readFile(String path, AudioReadOptions options) {
    final pathNative = path.toNativeUtf8();
    Pointer<Utf8> resultPtr;
    try {
      resultPtr = lofty_read_file(
        pathNative,
        options.readProperties ? 1 : 0,
        options.readPictures ? 1 : 0,
        options.readChapters ? 1 : 0,
        options.readRawTags ? 1 : 0,
      );
    } finally {
      malloc.free(pathNative);
    }

    if (resultPtr == nullptr) {
      throw _LoftyNativeFailure(lastError);
    }

    final jsonStr = resultPtr.toDartString();
    lofty_free_string(resultPtr);

    final json = jsonDecode(jsonStr) as Map<String, Object?>;
    return _parseDocument(json);
  }

  /// Write metadata to a file using the Lofty native shim.
  static LoftyWriteResult writeFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) {
    final pathNative = path.toNativeUtf8();
    final patchJson = jsonEncode(_encodePatch(patch, options));
    final patchNative = patchJson.toNativeUtf8();

    int result;
    try {
      result = lofty_write_file(pathNative, patchNative);
    } finally {
      malloc.free(pathNative);
      malloc.free(patchNative);
    }

    return LoftyWriteResult(result, lastError);
  }

  // ---- JSON decoding ------------------------------------------------------

  static AudioMetadataDocument _parseDocument(Map<String, Object?> json) {
    final metaJson = json['metadata'] as Map<String, Object?>? ?? const {};
    final propsJson = json['properties'] as Map<String, Object?>?;
    final picturesJson = json['pictures'] as List<Object?>? ?? const [];
    final rawTagsJson = json['rawTags'] as List<Object?>? ?? const [];

    final format = json['format'] as String?;
    final container = json['container'] as String?;

    return AudioMetadataDocument(
      metadata: _parseMetadata(metaJson),
      properties: propsJson != null ? _parseProperties(propsJson) : null,
      pictures: picturesJson
          .cast<Map<String, Object?>>()
          .map(_parsePicture)
          .toList(growable: false),
      // Lofty does not implement chapters; always empty.
      chapters: const [],
      rawTags: rawTagsJson
          .cast<Map<String, Object?>>()
          .map(_parseRawTag)
          .toList(growable: false),
      format: (format == null || format.isEmpty || format == 'unknown')
          ? null
          : format,
      container:
          (container == null || container.isEmpty || container == 'unknown')
          ? null
          : container,
      backendId: 'lofty',
    );
  }

  static AudioMetadata _parseMetadata(Map<String, Object?> json) {
    final extrasRaw =
        (json['extras'] as Map<String, Object?>?) ?? const <String, Object?>{};
    final extras = <String, Object?>{};
    extrasRaw.forEach((key, value) {
      if (value is List) {
        if (value.length == 1) {
          extras[key] = value.first;
        } else {
          extras[key] = List<String>.from(value.cast<Object>());
        }
      } else {
        extras[key] = value;
      }
    });

    return AudioMetadata(
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      albumArtist: json['albumArtist'] as String?,
      genre: json['genre'] as String?,
      comment: json['comment'] as String?,
      composer: json['composer'] as String?,
      lyricist: json['lyricist'] as String?,
      grouping: json['grouping'] as String?,
      year: json['year'] as int?,
      trackNumber: json['trackNumber'] as int?,
      trackTotal: json['trackTotal'] as int?,
      discNumber: json['discNumber'] as int?,
      discTotal: json['discTotal'] as int?,
      lyrics: json['lyrics'] as String?,
      extras: extras,
    );
  }

  static AudioProperties _parseProperties(Map<String, Object?> json) {
    final durationMs = json['durationMs'] as int?;
    return AudioProperties(
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      bitrate: json['bitrate'] as int?,
      sampleRate: json['sampleRate'] as int?,
      channels: json['channels'] as int?,
      bitDepth: json['bitDepth'] as int?,
    );
  }

  static AudioPicture _parsePicture(Map<String, Object?> json) {
    final typeIndex = json['type'] as int? ?? 0;
    final dataBase64 = json['data'] as String? ?? '';
    final clamped = typeIndex
        .clamp(0, AudioPictureType.values.length - 1)
        .toInt();
    return AudioPicture(
      type: AudioPictureType.values[clamped],
      mimeType: json['mimeType'] as String?,
      description: json['description'] as String?,
      data: dataBase64.isEmpty ? Uint8List(0) : base64Decode(dataBase64),
    );
  }

  static AudioRawTag _parseRawTag(Map<String, Object?> json) {
    final fieldsJson = json['fields'] as Map<String, Object?>? ?? const {};
    final fields = <String, List<String>>{};
    fieldsJson.forEach((k, v) {
      if (v is List) {
        fields[k] = v.cast<String>().toList();
      }
    });
    return AudioRawTag(
      tagType: json['tagType'] as String? ?? 'unknown',
      fields: fields,
    );
  }

  // ---- JSON encoding ------------------------------------------------------

  static Map<String, Object?> _encodePatch(
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) {
    return {
      'setFields': patch.setFields.map(
        (key, value) =>
            MapEntry(_tagFieldName(key), _normalizeFieldValue(value)),
      ),
      'clearFields': patch.clearFields.map(_tagFieldName).toList(),
      'rawMutations': patch.rawMutations.map(
        (key, value) => MapEntry(key, _normalizeFieldValue(value)),
      ),
      'pictureOperations': patch.pictureOperations
          .map(_encodePictureOp)
          .toList(),
      'stripOtherTags': options.stripOtherTags,
    };
  }

  static Object? _normalizeFieldValue(Object? value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is List) {
      return value
          .map((e) => e is num || e is String ? e : e.toString())
          .toList();
    }
    return value.toString();
  }

  static Map<String, Object?> _encodePictureOp(AudioPictureOperation op) {
    return switch (op) {
      RemoveAllPicturesOperation() => {'op': 'removeAll'},
      RemovePicturesByTypeOperation(:final type) => {
        'op': 'removeByType',
        'type': type.index,
      },
      AddPictureOperation(:final picture) => {
        'op': 'add',
        'picture': {
          'type': picture.type.index,
          if (picture.mimeType != null) 'mimeType': picture.mimeType,
          if (picture.description != null) 'description': picture.description,
          'data': base64Encode(picture.data),
        },
      },
    };
  }

  static String _tagFieldName(AudioTagField field) {
    return switch (field) {
      AudioTagField.title => 'title',
      AudioTagField.artist => 'artist',
      AudioTagField.album => 'album',
      AudioTagField.albumArtist => 'albumArtist',
      AudioTagField.genre => 'genre',
      AudioTagField.comment => 'comment',
      AudioTagField.composer => 'composer',
      AudioTagField.lyricist => 'lyricist',
      AudioTagField.grouping => 'grouping',
      AudioTagField.year => 'year',
      AudioTagField.trackNumber => 'trackNumber',
      AudioTagField.trackTotal => 'trackTotal',
      AudioTagField.discNumber => 'discNumber',
      AudioTagField.discTotal => 'discTotal',
      AudioTagField.lyrics => 'lyrics',
    };
  }
}

final class _LoftyNativeFailure implements Exception {
  final String message;
  const _LoftyNativeFailure(this.message);
  @override
  String toString() => 'LoftyNativeFailure: $message';
}
