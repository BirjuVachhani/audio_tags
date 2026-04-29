import 'dart:io';
import 'dart:typed_data';

import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:audio_tags_taglib/audio_tags_taglib.dart';
import 'package:test/test.dart';

/// Path to the test fixtures directory.
String get fixturesPath {
  final dir = Directory('test/fixtures');
  if (dir.existsSync()) return dir.absolute.path;
  return Directory('fixtures').absolute.path;
}

/// Copy a fixture so tests that write don't corrupt the originals.
String copyFixture(String name) {
  final src = File('$fixturesPath/$name');
  final dst = File('$fixturesPath/${name.replaceAll('.', '_copy.')}');
  src.copySync(dst.path);
  addTearDown(() {
    if (dst.existsSync()) dst.deleteSync();
  });
  return dst.path;
}

void main() {
  group('TaglibAudioMetadataBackend', () {
    late TaglibAudioMetadataBackend backend;

    setUp(() {
      backend = TaglibAudioMetadataBackend();
    });

    test('id is taglib', () {
      expect(backend.id, 'taglib');
    });

    test('version returns a semver string from native TagLib', () {
      final v = backend.version;
      expect(v, isNotNull);
      expect(v, isNotEmpty);
      expect(v, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('supportsReading is true', () {
      expect(backend.supportsReading, isTrue);
    });

    test('supportsWriting is true', () {
      expect(backend.supportsWriting, isTrue);
    });

    test('reports correct capabilities with version', () async {
      final caps = await backend.getCapabilities();

      expect(caps.backendVersion, isNotNull);
      expect(caps.backendVersion, backend.version);
      expect(caps.canReadFromFile, isTrue);
      expect(caps.canReadFromBytes, isFalse);
      expect(caps.canWriteToFile, isTrue);
      expect(caps.canWriteToBytes, isFalse);
      expect(caps.canReadPictures, isTrue);
      expect(caps.canWritePictures, isTrue);
      expect(caps.canReadChapters, isTrue);
      expect(caps.canReadRawTags, isTrue);
      expect(caps.supportedFormats, containsAll(['mp3', 'flac', 'ogg', 'wav']));
      expect(caps.writableFormats, containsAll(['mp3', 'flac', 'ogg']));
    });

    test('readFromBytes throws AudioOperationUnsupportedException', () {
      expect(
        () => backend.readFromBytes([], const AudioReadOptions()),
        throwsA(isA<AudioOperationUnsupportedException>()),
      );
    });

    test('writeToBytes throws AudioOperationUnsupportedException', () {
      expect(
        () => backend.writeToBytes(
          [],
          const AudioMetadataPatch(),
          const AudioWriteOptions(),
        ),
        throwsA(isA<AudioOperationUnsupportedException>()),
      );
    });

    test('readFromFile throws for nonexistent file', () {
      expect(
        () => backend.readFromFile(
          '/nonexistent/path/file.mp3',
          const AudioReadOptions(),
        ),
        throwsA(isA<AudioMetadataReadException>()),
      );
    });

    test('writeToFile throws for nonexistent file', () {
      expect(
        () => backend.writeToFile(
          '/nonexistent/path/file.mp3',
          const AudioMetadataPatch(),
          const AudioWriteOptions(),
        ),
        throwsA(isA<AudioMetadataWriteException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Integration tests — real TagLib FFI reads
  // -------------------------------------------------------------------------

  group('TagLib integration: read MP3', () {
    late TaglibAudioMetadataBackend backend;

    setUp(() {
      backend = TaglibAudioMetadataBackend();
    });

    test('reads common metadata fields from MP3', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(),
      );

      expect(doc.backendId, 'taglib');
      expect(doc.metadata.title, 'Test Title');
      expect(doc.metadata.artist, 'Test Artist');
      expect(doc.metadata.album, 'Test Album');
      expect(doc.metadata.genre, 'Electronic');
    });

    test('reads audio properties from MP3', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readProperties: true),
      );

      expect(doc.properties, isNotNull);
      expect(doc.properties!.sampleRate, 44100);
      expect(doc.properties!.channels, 1);
      expect(doc.properties!.bitrate, isPositive);
      expect(doc.properties!.duration, isNotNull);
      expect(doc.properties!.duration!.inMilliseconds, greaterThan(0));
    });

    test('reads raw tags from MP3', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readRawTags: true),
      );

      expect(doc.rawTags, isNotEmpty);
      final fields = doc.rawTags.first.fields;
      expect(fields['TITLE'], contains('Test Title'));
      expect(fields['ARTIST'], contains('Test Artist'));
    });

    test('skips properties when readProperties is false', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readProperties: false),
      );
      expect(doc.properties, isNull);
    });

    test('skips raw tags when readRawTags is false', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readRawTags: false),
      );
      expect(doc.rawTags, isEmpty);
    });
  });

  group('TagLib integration: read FLAC', () {
    late TaglibAudioMetadataBackend backend;

    setUp(() {
      backend = TaglibAudioMetadataBackend();
    });

    test('reads common metadata fields from FLAC', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(),
      );

      expect(doc.metadata.title, 'FLAC Title');
      expect(doc.metadata.artist, 'FLAC Artist');
      expect(doc.metadata.album, 'FLAC Album');
      expect(doc.metadata.genre, 'Jazz');
    });

    test('reads audio properties from FLAC', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(readProperties: true),
      );

      expect(doc.properties, isNotNull);
      expect(doc.properties!.sampleRate, 44100);
      expect(doc.properties!.duration!.inMilliseconds, greaterThan(0));
    });
  });

  group('TagLib integration: chapters', () {
    late TaglibAudioMetadataBackend backend;

    setUp(() {
      backend = TaglibAudioMetadataBackend();
    });

    test('reads chapters from chaptered MP3', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/chaptered.mp3',
        const AudioReadOptions(readChapters: true),
      );

      expect(doc.chapters, hasLength(3));

      expect(doc.chapters[0].title, 'Chapter One');
      expect(doc.chapters[0].startTime, Duration.zero);
      expect(doc.chapters[0].endTime, Duration(seconds: 1));

      expect(doc.chapters[1].title, 'Chapter Two');
      expect(doc.chapters[1].startTime, Duration(seconds: 1));
      expect(doc.chapters[1].endTime, Duration(seconds: 2));

      expect(doc.chapters[2].title, 'Chapter Three');
      expect(doc.chapters[2].startTime, Duration(seconds: 2));
      expect(doc.chapters[2].endTime, Duration(seconds: 3));
    });

    test('chapters are in CTOC order', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/chaptered.mp3',
        const AudioReadOptions(readChapters: true),
      );

      expect(doc.chapters[0].elementId, 'ch1');
      expect(doc.chapters[1].elementId, 'ch2');
      expect(doc.chapters[2].elementId, 'ch3');
    });

    test('chapters empty when readChapters is false', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/chaptered.mp3',
        const AudioReadOptions(readChapters: false),
      );

      expect(doc.chapters, isEmpty);
    });

    test('chapters empty for non-chaptered MP3', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readChapters: true),
      );

      expect(doc.chapters, isEmpty);
    });

    test('chapters empty for non-MP3 formats', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(readChapters: true),
      );

      expect(doc.chapters, isEmpty);
    });

    test('chapter offsets are null when 0xFFFFFFFF', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/chaptered.mp3',
        const AudioReadOptions(readChapters: true),
      );

      // Our fixture uses 0xFFFFFFFF for offsets.
      for (final ch in doc.chapters) {
        expect(ch.startOffset, isNull);
        expect(ch.endOffset, isNull);
      }
    });
  });

  group('TagLib integration: write', () {
    late TaglibAudioMetadataBackend backend;

    setUp(() {
      backend = TaglibAudioMetadataBackend();
    });

    test('write then read round-trip for title', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {AudioTagField.title: 'Written Title'},
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'Written Title');
    });

    test('write multiple fields then read', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {
            AudioTagField.title: 'Multi Title',
            AudioTagField.artist: 'Multi Artist',
            AudioTagField.album: 'Multi Album',
            AudioTagField.genre: 'Pop',
            AudioTagField.year: 2025,
            AudioTagField.trackNumber: 7,
          },
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'Multi Title');
      expect(doc.metadata.artist, 'Multi Artist');
      expect(doc.metadata.album, 'Multi Album');
      expect(doc.metadata.genre, 'Pop');
    });

    test('clear fields removes metadata', () async {
      final path = copyFixture('test.mp3');

      var doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, isNotNull);

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(setFields: {AudioTagField.title: null}),
        const AudioWriteOptions(),
      );

      doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, isNull);
    });

    test('raw mutations write arbitrary property map keys', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          rawMutations: {'CUSTOM_FIELD': 'custom_value'},
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readRawTags: true),
      );
      final fields = doc.rawTags.first.fields;
      expect(fields['CUSTOM_FIELD'], contains('custom_value'));
    });

    test('preserves untouched fields on write', () async {
      final path = copyFixture('test.mp3');

      var doc = await backend.readFromFile(path, const AudioReadOptions());
      final originalArtist = doc.metadata.artist;

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {AudioTagField.title: 'Changed Title'},
        ),
        const AudioWriteOptions(),
      );

      doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'Changed Title');
      expect(doc.metadata.artist, originalArtist);
    });
  });

  // -------------------------------------------------------------------------
  // Format / container detection
  // -------------------------------------------------------------------------

  group('TagLib integration: format/container detection', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('MP3 is detected as mp3 + ID3v2.x', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(),
      );
      expect(doc.format, 'mp3');
      expect(doc.container, startsWith('ID3v2'));
    });

    test('FLAC is detected as flac + VorbisComments', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(),
      );
      expect(doc.format, 'flac');
      expect(doc.container, 'VorbisComments');
    });

    test('M4B is detected as mp4 + MP4', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.m4b',
        const AudioReadOptions(),
      );
      expect(doc.format, 'mp4');
      expect(doc.container, 'MP4');
    });
  });

  // -------------------------------------------------------------------------
  // Audio properties (extended)
  // -------------------------------------------------------------------------

  group('TagLib integration: extended audio properties', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('FLAC reports bit depth', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(readProperties: true),
      );
      expect(doc.properties!.bitDepth, 16);
    });
  });

  // -------------------------------------------------------------------------
  // Pictures: read + write round-trip
  // -------------------------------------------------------------------------

  group('TagLib integration: pictures (MP3/ID3v2)', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('clean MP3 has no pictures', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, isEmpty);
    });

    test('add front cover round-trip', () async {
      final path = copyFixture('writable.mp3');
      final cover = _samplePngBytes();

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                description: 'Album art',
                data: cover,
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(1));
      final p = doc.pictures.first;
      expect(p.type, AudioPictureType.frontCover);
      expect(p.mimeType, 'image/png');
      expect(p.description, 'Album art');
      expect(p.data, cover);
    });

    test('add multiple picture types round-trip', () async {
      final path = copyFixture('writable.mp3');
      final front = _samplePngBytes();
      final back = _sampleJpegBytes();
      final logo = _samplePngBytes(seed: 7);

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: front,
              ),
            ),
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.backCover,
                mimeType: 'image/jpeg',
                data: back,
              ),
            ),
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.bandLogo,
                mimeType: 'image/png',
                description: 'Logo',
                data: logo,
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(3));

      final byType = {for (final p in doc.pictures) p.type: p};
      expect(byType[AudioPictureType.frontCover]!.data, front);
      expect(byType[AudioPictureType.backCover]!.data, back);
      expect(byType[AudioPictureType.bandLogo]!.data, logo);
      expect(byType[AudioPictureType.bandLogo]!.description, 'Logo');
    });

    test('removeAll wipes pictures', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: _samplePngBytes(),
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          pictureOperations: [RemoveAllPicturesOperation()],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, isEmpty);
    });

    test('removeByType removes only matching pictures', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: _samplePngBytes(),
              ),
            ),
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.backCover,
                mimeType: 'image/jpeg',
                data: _sampleJpegBytes(),
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          pictureOperations: [
            RemovePicturesByTypeOperation(AudioPictureType.backCover),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.type, AudioPictureType.frontCover);
    });

    test('replace artwork via removeAll + add', () async {
      final path = copyFixture('writable.mp3');
      final original = _samplePngBytes(seed: 1);
      final replacement = _samplePngBytes(seed: 99);

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: original,
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            const RemoveAllPicturesOperation(),
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: replacement,
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.data, replacement);
    });

    test('frontCover convenience getter', () async {
      final path = copyFixture('writable.mp3');
      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.bandLogo,
                mimeType: 'image/png',
                data: _samplePngBytes(seed: 5),
              ),
            ),
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: _samplePngBytes(seed: 6),
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.frontCover, isNotNull);
      expect(doc.frontCover!.type, AudioPictureType.frontCover);
    });

    test('mime sniffed from bytes when omitted', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                data: _sampleJpegBytes(),
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures.first.mimeType, 'image/jpeg');
    });
  });

  group('TagLib integration: pictures (FLAC)', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('add and read picture in FLAC', () async {
      final path = copyFixture('test.flac');
      final cover = _samplePngBytes(seed: 42);

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                description: 'FLAC cover',
                data: cover,
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.type, AudioPictureType.frontCover);
      expect(doc.pictures.first.description, 'FLAC cover');
      expect(doc.pictures.first.data, cover);
    });

    test('removeAll on FLAC', () async {
      final path = copyFixture('test.flac');

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: _samplePngBytes(),
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          pictureOperations: [RemoveAllPicturesOperation()],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, isEmpty);
    });
  });

  group('TagLib integration: pictures (MP4)', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('add cover art to M4B', () async {
      final path = copyFixture('test.m4b');
      final cover = _sampleJpegBytes();

      await backend.writeToFile(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/jpeg',
                data: cover,
              ),
            ),
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.mimeType, 'image/jpeg');
      expect(doc.pictures.first.data, cover);
    });
  });

  // -------------------------------------------------------------------------
  // Comprehensive field round-trips
  // -------------------------------------------------------------------------

  group('TagLib integration: full field round-trip (MP3)', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('all 15 normalized fields round-trip', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {
            AudioTagField.title: 'Title',
            AudioTagField.artist: 'Artist',
            AudioTagField.album: 'Album',
            AudioTagField.albumArtist: 'Album Artist',
            AudioTagField.genre: 'Rock',
            AudioTagField.comment: 'My Comment',
            AudioTagField.composer: 'Composer',
            AudioTagField.lyricist: 'Lyricist',
            AudioTagField.grouping: 'Group',
            AudioTagField.year: 2024,
            AudioTagField.trackNumber: 5,
            AudioTagField.trackTotal: 12,
            AudioTagField.discNumber: 1,
            AudioTagField.discTotal: 2,
            AudioTagField.lyrics: 'la la la',
          },
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'Title');
      expect(doc.metadata.artist, 'Artist');
      expect(doc.metadata.album, 'Album');
      expect(doc.metadata.albumArtist, 'Album Artist');
      expect(doc.metadata.genre, 'Rock');
      expect(doc.metadata.comment, 'My Comment');
      expect(doc.metadata.composer, 'Composer');
      expect(doc.metadata.lyricist, 'Lyricist');
      expect(doc.metadata.grouping, 'Group');
      expect(doc.metadata.year, 2024);
      expect(doc.metadata.trackNumber, 5);
      expect(
        doc.metadata.trackTotal,
        12,
        reason: 'ID3v2 trackTotal must round-trip via N/T',
      );
      expect(doc.metadata.discNumber, 1);
      expect(doc.metadata.discTotal, 2);
      expect(doc.metadata.lyrics, 'la la la');
    });

    test('Unicode (CJK + emoji) round-trip', () async {
      final path = copyFixture('writable.mp3');
      const title = '日本語タイトル 🎵';
      const artist = 'мой исполнитель';

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {AudioTagField.title: title, AudioTagField.artist: artist},
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, title);
      expect(doc.metadata.artist, artist);
    });
  });

  group('TagLib integration: full field round-trip (FLAC)', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('common fields round-trip on FLAC', () async {
      final path = copyFixture('test.flac');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {
            AudioTagField.title: 'F Title',
            AudioTagField.albumArtist: 'F AA',
            AudioTagField.composer: 'F Comp',
            AudioTagField.year: 2020,
            AudioTagField.trackNumber: 3,
            AudioTagField.trackTotal: 9,
            AudioTagField.lyrics: 'flac lyrics line',
          },
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'F Title');
      expect(doc.metadata.albumArtist, 'F AA');
      expect(doc.metadata.composer, 'F Comp');
      expect(doc.metadata.year, 2020);
      expect(doc.metadata.trackNumber, 3);
      expect(doc.metadata.trackTotal, 9);
      expect(doc.metadata.lyrics, 'flac lyrics line');
    });
  });

  // -------------------------------------------------------------------------
  // Extras population
  // -------------------------------------------------------------------------

  group('TagLib integration: extras', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('non-normalized fields surface in extras', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          rawMutations: {
            'ISRC': 'US1234567890',
            'MUSICBRAINZ_TRACKID': 'abc-123',
          },
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.extras['ISRC'], 'US1234567890');
      expect(doc.metadata.extras['MUSICBRAINZ_TRACKID'], 'abc-123');
    });

    test('extras excludes normalized field keys', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {AudioTagField.title: 'T'},
          rawMutations: {'COPYRIGHT': '2024 Some Label'},
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.extras.containsKey('TITLE'), isFalse);
      expect(doc.metadata.extras['COPYRIGHT'], '2024 Some Label');
    });
  });

  // -------------------------------------------------------------------------
  // strip-other-tags
  // -------------------------------------------------------------------------

  group('TagLib integration: stripOtherTags', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('option does not throw and write succeeds', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(setFields: {AudioTagField.title: 'X'}),
        const AudioWriteOptions(stripOtherTags: true),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'X');
    });
  });

  // -------------------------------------------------------------------------
  // Error mapping
  // -------------------------------------------------------------------------

  group('TagLib integration: error classification', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('non-existent file gives AudioMetadataReadException', () {
      expect(
        () => backend.readFromFile(
          '/nonexistent/whatever.mp3',
          const AudioReadOptions(),
        ),
        throwsA(
          isA<AudioMetadataReadException>().having(
            (e) => e.path,
            'path',
            '/nonexistent/whatever.mp3',
          ),
        ),
      );
    });

    test('unrecognized format gives AudioFormatUnsupportedException', () async {
      final tmp = File(
        '${Directory.systemTemp.path}/audio_tags_garbage_${DateTime.now().microsecondsSinceEpoch}.bogusext',
      );
      await tmp.writeAsBytes(List.filled(2048, 0));
      addTearDown(() => tmp.deleteSync());

      expect(
        () => backend.readFromFile(tmp.path, const AudioReadOptions()),
        throwsA(isA<AudioFormatUnsupportedException>()),
      );
    });

    test('write to non-existent file gives AudioMetadataWriteException', () {
      expect(
        () => backend.writeToFile(
          '/nonexistent/whatever.mp3',
          const AudioMetadataPatch(setFields: {AudioTagField.title: 'X'}),
          const AudioWriteOptions(),
        ),
        throwsA(isA<AudioMetadataWriteException>()),
      );
    });

    test('all error types are AudioMetadataException', () {
      const errors = <AudioMetadataException>[
        AudioFormatUnsupportedException('a'),
        AudioMetadataReadException('b'),
        AudioMetadataWriteException('c'),
        AudioBackendUnavailableException('d'),
        AudioOperationUnsupportedException('e'),
      ];
      for (final e in errors) {
        expect(e, isA<AudioMetadataException>());
        expect(e, isA<Exception>());
      }
    });
  });

  // -------------------------------------------------------------------------
  // Empty patch is a no-op
  // -------------------------------------------------------------------------

  group('TagLib integration: empty patch', () {
    late TaglibAudioMetadataBackend backend;
    setUp(() => backend = TaglibAudioMetadataBackend());

    test('empty patch does not modify the file', () async {
      final path = copyFixture('test.mp3');
      final before = await backend.readFromFile(path, const AudioReadOptions());

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(),
        const AudioWriteOptions(),
      );

      final after = await backend.readFromFile(path, const AudioReadOptions());
      expect(after.metadata, equals(before.metadata));
    });
  });
}

// -- Test helpers -----------------------------------------------------------

/// Returns a tiny but valid PNG byte sequence. Differs by [seed] so callers
/// can distinguish payloads when round-tripping multiple pictures.
Uint8List _samplePngBytes({int seed = 0}) {
  // 1x1 transparent PNG, with a trailing seed byte for distinguishability.
  final base = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
    seed & 0xFF,
    (seed >> 8) & 0xFF,
  ];
  return Uint8List.fromList(base);
}

Uint8List _sampleJpegBytes({int seed = 0}) {
  // Minimal SOI/APP0/EOI JPEG with seed bytes inside the comment.
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
    0x00,
    0x01,
    0x01,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
    0xFF,
    0xFE,
    0x00,
    0x06,
    seed & 0xFF,
    (seed >> 8) & 0xFF,
    0x00,
    0x00,
    0xFF,
    0xD9,
  ]);
}
