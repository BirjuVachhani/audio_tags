import 'dart:io';
import 'dart:typed_data';

import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:audio_tags_lofty/audio_tags_lofty.dart';
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
  group('LoftyAudioMetadataBackend', () {
    late LoftyAudioMetadataBackend backend;

    setUp(() {
      backend = LoftyAudioMetadataBackend();
    });

    test('id is lofty', () {
      expect(backend.id, 'lofty');
    });

    test('version returns a semver-like string', () {
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
      expect(caps.canReadChapters, isFalse);
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
          const AudioMetadataPatch(setFields: {AudioTagField.title: 'X'}),
          const AudioWriteOptions(),
        ),
        throwsA(isA<AudioMetadataWriteException>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Read MP3 / FLAC
  // -------------------------------------------------------------------------

  group('Lofty integration: read MP3', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

    test('reads common metadata fields from MP3', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(),
      );

      expect(doc.backendId, 'lofty');
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
      expect(doc.properties!.duration!.inMilliseconds, greaterThan(0));
    });

    test('reads raw tags from MP3 with property-map style keys', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(readRawTags: true),
      );

      expect(doc.rawTags, isNotEmpty);
      // Cross-backend contract: keys must use the property-map convention,
      // not Rust enum Debug names like "TrackTitle".
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

  group('Lofty integration: read FLAC', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

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

    test('reads audio properties from FLAC including bit depth', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(readProperties: true),
      );

      expect(doc.properties, isNotNull);
      expect(doc.properties!.sampleRate, 44100);
      expect(doc.properties!.bitDepth, 16);
      expect(doc.properties!.duration!.inMilliseconds, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  // Format / container detection
  // -------------------------------------------------------------------------

  group('Lofty integration: format/container detection', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

    test('MP3 detected as mp3 + ID3v2', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.mp3',
        const AudioReadOptions(),
      );
      expect(doc.format, 'mp3');
      expect(doc.container, 'ID3v2');
    });

    test('FLAC detected as flac + VorbisComments', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.flac',
        const AudioReadOptions(),
      );
      expect(doc.format, 'flac');
      expect(doc.container, 'VorbisComments');
    });

    test('M4B detected as mp4 + MP4', () async {
      final doc = await backend.readFromFile(
        '$fixturesPath/test.m4b',
        const AudioReadOptions(),
      );
      expect(doc.format, 'mp4');
      expect(doc.container, 'MP4');
    });
  });

  // -------------------------------------------------------------------------
  // Field round-trip
  // -------------------------------------------------------------------------

  group('Lofty integration: write', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

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

    test('all 15 normalized fields round-trip on MP3', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {
            AudioTagField.title: 'Title',
            AudioTagField.artist: 'Artist',
            AudioTagField.album: 'Album',
            AudioTagField.albumArtist: 'AA',
            AudioTagField.genre: 'Rock',
            AudioTagField.comment: 'Comment',
            AudioTagField.composer: 'Composer',
            AudioTagField.lyricist: 'Lyricist',
            AudioTagField.grouping: 'Group',
            AudioTagField.year: 2024,
            AudioTagField.trackNumber: 5,
            AudioTagField.trackTotal: 12,
            AudioTagField.discNumber: 1,
            AudioTagField.discTotal: 2,
            AudioTagField.lyrics: 'la la',
          },
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.title, 'Title');
      expect(doc.metadata.artist, 'Artist');
      expect(doc.metadata.album, 'Album');
      expect(doc.metadata.albumArtist, 'AA');
      expect(doc.metadata.genre, 'Rock');
      expect(doc.metadata.comment, 'Comment');
      expect(doc.metadata.composer, 'Composer');
      expect(doc.metadata.lyricist, 'Lyricist');
      expect(doc.metadata.grouping, 'Group');
      expect(doc.metadata.year, 2024);
      expect(doc.metadata.trackNumber, 5);
      expect(
        doc.metadata.trackTotal,
        12,
        reason: 'ID3v2 trackTotal must round-trip',
      );
      expect(doc.metadata.discNumber, 1);
      expect(doc.metadata.discTotal, 2);
      expect(doc.metadata.lyrics, 'la la');
    });

    test('all common fields round-trip on FLAC', () async {
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
    });
  });

  // -------------------------------------------------------------------------
  // Pictures
  // -------------------------------------------------------------------------

  group('Lofty integration: pictures (MP3)', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

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

    test('add multiple types round-trip', () async {
      final path = copyFixture('writable.mp3');
      final front = _samplePngBytes(seed: 1);
      final back = _sampleJpegBytes(seed: 2);

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
          ],
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(
        path,
        const AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(2));
      final byType = {for (final p in doc.pictures) p.type: p};
      expect(byType[AudioPictureType.frontCover]!.data, front);
      expect(byType[AudioPictureType.backCover]!.data, back);
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
                data: _samplePngBytes(seed: 1),
              ),
            ),
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.backCover,
                mimeType: 'image/jpeg',
                data: _sampleJpegBytes(seed: 2),
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
  });

  group('Lofty integration: pictures (FLAC)', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

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
      expect(doc.pictures.first.data, cover);
      expect(doc.pictures.first.description, 'FLAC cover');
    });
  });

  // -------------------------------------------------------------------------
  // Extras + raw mutations
  // -------------------------------------------------------------------------

  group('Lofty integration: extras / raw mutations', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

    test('ISRC raw mutation round-trips into extras', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(rawMutations: {'ISRC': 'US1234567890'}),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.extras['ISRC'], 'US1234567890');
    });

    test('extras excludes normalized field keys', () async {
      final path = copyFixture('writable.mp3');

      await backend.writeToFile(
        path,
        const AudioMetadataPatch(
          setFields: {AudioTagField.title: 'T'},
          rawMutations: {'COPYRIGHT': '2024 Label'},
        ),
        const AudioWriteOptions(),
      );

      final doc = await backend.readFromFile(path, const AudioReadOptions());
      expect(doc.metadata.extras.containsKey('TITLE'), isFalse);
      expect(doc.metadata.extras['COPYRIGHT'], '2024 Label');
    });
  });

  // -------------------------------------------------------------------------
  // Error mapping
  // -------------------------------------------------------------------------

  group('Lofty integration: error classification', () {
    late LoftyAudioMetadataBackend backend;
    setUp(() => backend = LoftyAudioMetadataBackend());

    test('unrecognized format gives AudioFormatUnsupportedException', () async {
      final tmp = File(
        '${Directory.systemTemp.path}/audio_tags_lofty_garbage_${DateTime.now().microsecondsSinceEpoch}.bogusext',
      );
      await tmp.writeAsBytes(List.filled(2048, 0));
      addTearDown(() => tmp.deleteSync());

      expect(
        () => backend.readFromFile(tmp.path, const AudioReadOptions()),
        throwsA(isA<AudioFormatUnsupportedException>()),
      );
    });
  });
}

// ---- Test helpers ---------------------------------------------------------

Uint8List _samplePngBytes({int seed = 0}) {
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
