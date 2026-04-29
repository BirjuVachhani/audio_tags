import 'dart:typed_data';

import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:test/test.dart';

void main() {
  // -------------------------------------------------------------------------
  // Data model tests
  // -------------------------------------------------------------------------

  group('AudioMetadata', () {
    test('default constructor has all null/empty fields', () {
      const m = AudioMetadata();
      expect(m.title, isNull);
      expect(m.artist, isNull);
      expect(m.album, isNull);
      expect(m.albumArtist, isNull);
      expect(m.genre, isNull);
      expect(m.comment, isNull);
      expect(m.composer, isNull);
      expect(m.lyricist, isNull);
      expect(m.grouping, isNull);
      expect(m.year, isNull);
      expect(m.trackNumber, isNull);
      expect(m.trackTotal, isNull);
      expect(m.discNumber, isNull);
      expect(m.discTotal, isNull);
      expect(m.lyrics, isNull);
      expect(m.extras, isEmpty);
    });

    test('constructor populates all fields', () {
      const m = AudioMetadata(
        title: 'T',
        artist: 'A',
        album: 'Al',
        albumArtist: 'AA',
        genre: 'G',
        comment: 'C',
        composer: 'Co',
        lyricist: 'L',
        grouping: 'Gr',
        year: 2020,
        trackNumber: 1,
        trackTotal: 10,
        discNumber: 2,
        discTotal: 3,
        lyrics: 'Lyrics',
        extras: {'key': 'value'},
      );
      expect(m.title, 'T');
      expect(m.artist, 'A');
      expect(m.album, 'Al');
      expect(m.albumArtist, 'AA');
      expect(m.genre, 'G');
      expect(m.comment, 'C');
      expect(m.composer, 'Co');
      expect(m.lyricist, 'L');
      expect(m.grouping, 'Gr');
      expect(m.year, 2020);
      expect(m.trackNumber, 1);
      expect(m.trackTotal, 10);
      expect(m.discNumber, 2);
      expect(m.discTotal, 3);
      expect(m.lyrics, 'Lyrics');
      expect(m.extras, {'key': 'value'});
    });
  });

  group('AudioProperties', () {
    test('default constructor has all null fields', () {
      const p = AudioProperties();
      expect(p.duration, isNull);
      expect(p.bitrate, isNull);
      expect(p.sampleRate, isNull);
      expect(p.channels, isNull);
      expect(p.bitDepth, isNull);
    });

    test('constructor populates all fields', () {
      const p = AudioProperties(
        duration: Duration(seconds: 120),
        bitrate: 256,
        sampleRate: 48000,
        channels: 2,
        bitDepth: 24,
      );
      expect(p.duration, Duration(seconds: 120));
      expect(p.bitrate, 256);
      expect(p.sampleRate, 48000);
      expect(p.channels, 2);
      expect(p.bitDepth, 24);
    });
  });

  group('AudioPicture', () {
    test('all picture types exist', () {
      expect(AudioPictureType.values.length, 21);
      expect(AudioPictureType.values, contains(AudioPictureType.frontCover));
      expect(AudioPictureType.values, contains(AudioPictureType.backCover));
      expect(AudioPictureType.values, contains(AudioPictureType.bandLogo));
    });

    test('constructor populates fields', () {
      final pic = AudioPicture(
        type: AudioPictureType.frontCover,
        mimeType: 'image/jpeg',
        description: 'Album art',
        data: Uint8List.fromList([0xFF, 0xD8]),
      );
      expect(pic.type, AudioPictureType.frontCover);
      expect(pic.mimeType, 'image/jpeg');
      expect(pic.description, 'Album art');
      expect(pic.data, [0xFF, 0xD8]);
    });
  });

  group('AudioPictureOperation', () {
    test('AddPictureOperation holds picture', () {
      final pic = AudioPicture(
        type: AudioPictureType.other,
        data: Uint8List(0),
      );
      final op = AddPictureOperation(pic);
      expect(op, isA<AudioPictureOperation>());
      expect(op.picture, same(pic));
    });

    test('RemovePicturesByTypeOperation holds type', () {
      const op = RemovePicturesByTypeOperation(AudioPictureType.backCover);
      expect(op, isA<AudioPictureOperation>());
      expect(op.type, AudioPictureType.backCover);
    });

    test('RemoveAllPicturesOperation is constructible', () {
      const op = RemoveAllPicturesOperation();
      expect(op, isA<AudioPictureOperation>());
    });

    test('sealed class exhaustiveness via switch', () {
      AudioPictureOperation op = const RemoveAllPicturesOperation();
      final result = switch (op) {
        AddPictureOperation() => 'add',
        RemovePicturesByTypeOperation() => 'removeByType',
        RemoveAllPicturesOperation() => 'removeAll',
      };
      expect(result, 'removeAll');
    });
  });

  group('AudioTagField', () {
    test('all 15 standard fields exist', () {
      expect(AudioTagField.values.length, 15);
    });
  });

  group('AudioMetadata.copyWith', () {
    test('returns identical metadata when no fields supplied', () {
      const m = AudioMetadata(title: 'T', artist: 'A', year: 2024);
      expect(m.copyWith(), equals(m));
    });

    test('overrides only the named field', () {
      const m = AudioMetadata(title: 'Old', artist: 'A');
      final m2 = m.copyWith(title: 'New');
      expect(m2.title, 'New');
      expect(m2.artist, 'A');
    });

    test('explicitly clears a field with null', () {
      const m = AudioMetadata(title: 'T', artist: 'A');
      final m2 = m.copyWith(title: null);
      expect(m2.title, isNull);
      expect(m2.artist, 'A');
    });

    test('equality and hashCode', () {
      const a = AudioMetadata(title: 'T', year: 2024);
      const b = AudioMetadata(title: 'T', year: 2024);
      const c = AudioMetadata(title: 'T', year: 2025);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('AudioPicture.copyWith and equality', () {
    test('equality compares bytes', () {
      final p1 = AudioPicture(
        type: AudioPictureType.frontCover,
        mimeType: 'image/jpeg',
        data: Uint8List.fromList([1, 2, 3]),
      );
      final p2 = AudioPicture(
        type: AudioPictureType.frontCover,
        mimeType: 'image/jpeg',
        data: Uint8List.fromList([1, 2, 3]),
      );
      final p3 = AudioPicture(
        type: AudioPictureType.frontCover,
        mimeType: 'image/jpeg',
        data: Uint8List.fromList([1, 2, 4]),
      );
      expect(p1, equals(p2));
      expect(p1, isNot(equals(p3)));
    });
  });

  group('AudioMetadataPatch', () {
    test('isEmpty / isNotEmpty', () {
      expect(const AudioMetadataPatch().isEmpty, isTrue);
      expect(const AudioMetadataPatch().isNotEmpty, isFalse);
      const p = AudioMetadataPatch(setFields: {AudioTagField.title: 'X'});
      expect(p.isEmpty, isFalse);
      expect(p.isNotEmpty, isTrue);
    });
  });

  group('AudioRawTag', () {
    test('default fields map is empty', () {
      const tag = AudioRawTag(tagType: 'ID3v2');
      expect(tag.tagType, 'ID3v2');
      expect(tag.fields, isEmpty);
    });

    test('fields populated correctly', () {
      const tag = AudioRawTag(
        tagType: 'Vorbis',
        fields: {
          'TITLE': ['Song'],
          'ARTIST': ['Band'],
        },
      );
      expect(tag.fields['TITLE'], ['Song']);
      expect(tag.fields['ARTIST'], ['Band']);
    });
  });

  group('AudioMetadataDocument', () {
    test('minimal document', () {
      const doc = AudioMetadataDocument(
        metadata: AudioMetadata(),
        backendId: 'test',
      );
      expect(doc.metadata.title, isNull);
      expect(doc.properties, isNull);
      expect(doc.pictures, isEmpty);
      expect(doc.rawTags, isEmpty);
      expect(doc.format, isNull);
      expect(doc.container, isNull);
      expect(doc.backendId, 'test');
    });

    test('fully populated document', () {
      final doc = AudioMetadataDocument(
        metadata: AudioMetadata(title: 'Song'),
        properties: AudioProperties(bitrate: 320),
        pictures: [
          AudioPicture(type: AudioPictureType.frontCover, data: Uint8List(0)),
        ],
        rawTags: [AudioRawTag(tagType: 'ID3v2')],
        format: 'mp3',
        container: 'MPEG',
        backendId: 'taglib',
      );
      expect(doc.metadata.title, 'Song');
      expect(doc.properties!.bitrate, 320);
      expect(doc.pictures, hasLength(1));
      expect(doc.rawTags, hasLength(1));
    });
  });

  group('AudioReadOptions', () {
    test('defaults', () {
      const opts = AudioReadOptions();
      expect(opts.readProperties, isTrue);
      expect(opts.readPictures, isFalse);
      expect(opts.readRawTags, isFalse);
    });
  });

  group('AudioWriteOptions', () {
    test('defaults', () {
      const opts = AudioWriteOptions();
      expect(opts.stripOtherTags, isFalse);
    });
  });

  group('AudioMetadataPatch', () {
    test('default patch is empty', () {
      const patch = AudioMetadataPatch();
      expect(patch.setFields, isEmpty);
      expect(patch.clearFields, isEmpty);
      expect(patch.pictureOperations, isEmpty);
      expect(patch.rawMutations, isEmpty);
    });

    test('patch with all fields populated', () {
      final patch = AudioMetadataPatch(
        setFields: {AudioTagField.title: 'New', AudioTagField.year: 2025},
        clearFields: {AudioTagField.comment},
        pictureOperations: [const RemoveAllPicturesOperation()],
        rawMutations: {'CUSTOM': 'value'},
      );
      expect(patch.setFields, hasLength(2));
      expect(patch.clearFields, contains(AudioTagField.comment));
      expect(patch.pictureOperations, hasLength(1));
      expect(patch.rawMutations['CUSTOM'], 'value');
    });
  });

  // -------------------------------------------------------------------------
  // Error model tests
  // -------------------------------------------------------------------------

  group('AudioMetadataException', () {
    test('sealed exception hierarchy', () {
      const e1 = AudioFormatUnsupportedException('unsupported');
      const e2 = AudioMetadataReadException('read failed');
      const e3 = AudioMetadataWriteException('write failed');
      const e4 = AudioBackendUnavailableException('unavailable');

      expect(e1, isA<AudioMetadataException>());
      expect(e2, isA<AudioMetadataException>());
      expect(e3, isA<AudioMetadataException>());
      expect(e4, isA<AudioMetadataException>());
      expect(e1, isA<Exception>());
    });

    test('toString includes type and message', () {
      const e = AudioMetadataReadException('file not found');
      expect(e.toString(), contains('AudioMetadataReadException'));
      expect(e.toString(), contains('file not found'));
    });

    test('exhaustive switch on sealed type', () {
      AudioMetadataException e = const AudioMetadataWriteException('fail');
      final result = switch (e) {
        AudioFormatUnsupportedException() => 'format',
        AudioMetadataReadException() => 'read',
        AudioMetadataWriteException() => 'write',
        AudioBackendUnavailableException() => 'unavailable',
        AudioOperationUnsupportedException() => 'op-unsupported',
      };
      expect(result, 'write');
    });

    test('exception captures path and cause', () {
      const cause = FormatException('bad');
      const e = AudioMetadataReadException(
        'failed',
        path: '/tmp/song.mp3',
        cause: cause,
      );
      expect(e.path, '/tmp/song.mp3');
      expect(e.cause, cause);
      expect(e.toString(), contains('/tmp/song.mp3'));
    });
  });

  // -------------------------------------------------------------------------
  // Backend abstraction tests
  // -------------------------------------------------------------------------

  group('AudioBackendCapabilities', () {
    test('all fields accessible', () {
      const caps = AudioBackendCapabilities(
        canReadFromFile: true,
        canReadFromBytes: false,
        canWriteToFile: true,
        canWriteToBytes: false,
        canReadPictures: true,
        canWritePictures: false,
        supportedFormats: {'mp3', 'flac', 'ogg'},
        writableFormats: {'mp3'},
      );
      expect(caps.canReadFromFile, isTrue);
      expect(caps.canReadFromBytes, isFalse);
      expect(caps.supportedFormats, hasLength(3));
      expect(caps.backendVersion, isNull);
    });
  });

  group('AudioMetadataBackendRegistry', () {
    late AudioMetadataBackendRegistry registry;

    setUp(() {
      registry = AudioMetadataBackendRegistry.instance;
    });

    tearDown(() {
      registry.unregister('test_fake');
      registry.unregister('test_another');
    });

    test('register and create backend', () {
      final backend = _FakeBackend();
      registry.register('test_fake', () => backend);

      expect(registry.isRegistered('test_fake'), isTrue);
      expect(registry.create('test_fake'), same(backend));
    });

    test('unregister removes backend', () {
      registry.register('test_fake', () => _FakeBackend());
      registry.unregister('test_fake');
      expect(registry.isRegistered('test_fake'), isFalse);
    });

    test('create throws for unknown backend', () {
      expect(() => registry.create('nonexistent'), throwsStateError);
    });

    test('re-registering overwrites factory', () {
      var callCount = 0;
      registry.register('test_fake', () {
        callCount = 1;
        return _FakeBackend();
      });
      registry.register('test_fake', () {
        callCount = 2;
        return _FakeBackend();
      });
      registry.create('test_fake');
      expect(callCount, 2);
    });
  });
}

// Minimal fake for registry tests within this package.
final class _FakeBackend implements AudioMetadataBackend {
  @override
  String get id => 'fake';
  @override
  String? get version => null;
  @override
  bool get supportsReading => true;
  @override
  bool get supportsWriting => false;
  @override
  Future<AudioMetadataDocument> readFromFile(String p, AudioReadOptions o) =>
      throw UnimplementedError();
  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> b,
    AudioReadOptions o,
  ) => throw UnimplementedError();
  @override
  Future<void> writeToFile(
    String p,
    AudioMetadataPatch pa,
    AudioWriteOptions o,
  ) => throw UnimplementedError();
  @override
  Future<List<int>> writeToBytes(
    List<int> b,
    AudioMetadataPatch pa,
    AudioWriteOptions o,
  ) => throw UnimplementedError();
  @override
  Future<AudioBackendCapabilities> getCapabilities() =>
      throw UnimplementedError();
}
