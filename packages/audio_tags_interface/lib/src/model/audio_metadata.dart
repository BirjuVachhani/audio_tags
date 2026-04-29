import 'package:meta/meta.dart';

/// Normalized common metadata fields for an audio file.
@immutable
final class AudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final String? comment;
  final String? composer;
  final String? lyricist;
  final String? grouping;
  final int? year;
  final int? trackNumber;
  final int? trackTotal;
  final int? discNumber;
  final int? discTotal;
  final String? lyrics;

  /// Non-normalized fields preserved from the file's tags.
  ///
  /// Keys are upper-case property-map names (e.g. `ISRC`,
  /// `MUSICBRAINZ_TRACKID`, `REPLAYGAIN_TRACK_GAIN`). Values are either a
  /// single `String` or a `List<String>` for multi-value fields.
  final Map<String, Object?> extras;

  const AudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.comment,
    this.composer,
    this.lyricist,
    this.grouping,
    this.year,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.discTotal,
    this.lyrics,
    this.extras = const {},
  });

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass [unsetX] sentinels (e.g. [unsetTitle]) to explicitly clear a field
  /// to `null`. Omitting a parameter leaves the existing value in place.
  AudioMetadata copyWith({
    Object? title = _sentinel,
    Object? artist = _sentinel,
    Object? album = _sentinel,
    Object? albumArtist = _sentinel,
    Object? genre = _sentinel,
    Object? comment = _sentinel,
    Object? composer = _sentinel,
    Object? lyricist = _sentinel,
    Object? grouping = _sentinel,
    Object? year = _sentinel,
    Object? trackNumber = _sentinel,
    Object? trackTotal = _sentinel,
    Object? discNumber = _sentinel,
    Object? discTotal = _sentinel,
    Object? lyrics = _sentinel,
    Map<String, Object?>? extras,
  }) {
    return AudioMetadata(
      title: identical(title, _sentinel) ? this.title : title as String?,
      artist: identical(artist, _sentinel) ? this.artist : artist as String?,
      album: identical(album, _sentinel) ? this.album : album as String?,
      albumArtist: identical(albumArtist, _sentinel)
          ? this.albumArtist
          : albumArtist as String?,
      genre: identical(genre, _sentinel) ? this.genre : genre as String?,
      comment: identical(comment, _sentinel)
          ? this.comment
          : comment as String?,
      composer: identical(composer, _sentinel)
          ? this.composer
          : composer as String?,
      lyricist: identical(lyricist, _sentinel)
          ? this.lyricist
          : lyricist as String?,
      grouping: identical(grouping, _sentinel)
          ? this.grouping
          : grouping as String?,
      year: identical(year, _sentinel) ? this.year : year as int?,
      trackNumber: identical(trackNumber, _sentinel)
          ? this.trackNumber
          : trackNumber as int?,
      trackTotal: identical(trackTotal, _sentinel)
          ? this.trackTotal
          : trackTotal as int?,
      discNumber: identical(discNumber, _sentinel)
          ? this.discNumber
          : discNumber as int?,
      discTotal: identical(discTotal, _sentinel)
          ? this.discTotal
          : discTotal as int?,
      lyrics: identical(lyrics, _sentinel) ? this.lyrics : lyrics as String?,
      extras: extras ?? this.extras,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AudioMetadata &&
        title == other.title &&
        artist == other.artist &&
        album == other.album &&
        albumArtist == other.albumArtist &&
        genre == other.genre &&
        comment == other.comment &&
        composer == other.composer &&
        lyricist == other.lyricist &&
        grouping == other.grouping &&
        year == other.year &&
        trackNumber == other.trackNumber &&
        trackTotal == other.trackTotal &&
        discNumber == other.discNumber &&
        discTotal == other.discTotal &&
        lyrics == other.lyrics &&
        _mapEquals(extras, other.extras);
  }

  @override
  int get hashCode => Object.hash(
    title,
    artist,
    album,
    albumArtist,
    genre,
    comment,
    composer,
    lyricist,
    grouping,
    year,
    trackNumber,
    trackTotal,
    discNumber,
    discTotal,
    lyrics,
    Object.hashAllUnordered(extras.keys),
  );

  @override
  String toString() =>
      'AudioMetadata(title: $title, artist: $artist, '
      'album: $album, year: $year, track: $trackNumber/$trackTotal)';
}

const Object _sentinel = Object();

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (!b.containsKey(k)) return false;
    final av = a[k];
    final bv = b[k];
    if (av is List && bv is List) {
      if (av.length != bv.length) return false;
      for (var i = 0; i < av.length; i++) {
        if (av[i] != bv[i]) return false;
      }
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}
