import 'dart:io';
import 'dart:typed_data';

import 'package:audio_tags/audio_tags.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fake backend for service layer testing
// ---------------------------------------------------------------------------

final class FakeAudioMetadataBackend implements AudioMetadataBackend {
  @override
  String get id => 'fake';

  @override
  String? get version => '1.0.0-fake';

  @override
  bool get supportsReading => true;

  @override
  bool get supportsWriting => true;

  final List<String> readPaths = [];
  final List<String> writePaths = [];
  final List<AudioMetadataPatch> writePatches = [];
  final List<AudioReadOptions> readOptions = [];

  @override
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  ) async {
    readPaths.add(path);
    readOptions.add(options);
    return AudioMetadataDocument(
      metadata: AudioMetadata(
        title: 'Test Title',
        artist: 'Test Artist',
        album: 'Test Album',
        albumArtist: 'Test Album Artist',
        genre: 'Rock',
        comment: 'A comment',
        composer: 'Test Composer',
        lyricist: 'Test Lyricist',
        grouping: 'Test Group',
        year: 2024,
        trackNumber: 1,
        trackTotal: 12,
        discNumber: 1,
        discTotal: 2,
        lyrics: 'La la la',
        extras: {'ISRC': 'US1234567890'},
      ),
      properties: options.readProperties
          ? AudioProperties(
              duration: Duration(minutes: 3, seconds: 45),
              bitrate: 320,
              sampleRate: 44100,
              channels: 2,
              bitDepth: 16,
            )
          : null,
      pictures: options.readPictures
          ? [
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                description: 'Cover',
                data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
              ),
            ]
          : [],
      rawTags: options.readRawTags
          ? [
              AudioRawTag(
                tagType: 'ID3v2',
                fields: {
                  'TITLE': ['Test Title'],
                  'ARTIST': ['Test Artist'],
                },
              ),
            ]
          : [],
      format: 'mp3',
      container: 'MPEG',
      backendId: id,
    );
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async {
    throw UnsupportedError('Fake backend does not support bytes');
  }

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    writePaths.add(path);
    writePatches.add(patch);
  }

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async {
    throw UnsupportedError('Fake backend does not support bytes');
  }

  @override
  Future<AudioBackendCapabilities> getCapabilities() async {
    return AudioBackendCapabilities(
      canReadFromFile: true,
      canReadFromBytes: false,
      canWriteToFile: true,
      canWriteToBytes: false,
      canReadPictures: true,
      canWritePictures: false,
      supportedFormats: {'mp3', 'flac'},
      writableFormats: {'mp3'},
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String get fixturesPath {
  // Fixtures live in the taglib package.
  final dir = Directory('../audio_tags_taglib/test/fixtures');
  if (dir.existsSync()) return dir.absolute.path;
  return Directory('test/fixtures').absolute.path;
}

String copyFixture(String name) {
  final src = File('$fixturesPath/$name');
  final dst = File('$fixturesPath/${name.replaceAll('.', '_copy.')}');
  src.copySync(dst.path);
  addTearDown(() {
    if (dst.existsSync()) dst.deleteSync();
  });
  return dst.path;
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  group('AudioMetadataConfig', () {
    test('instance is singleton', () {
      expect(AudioMetadataConfig.instance, same(AudioMetadataConfig.instance));
    });

    test('default backend is TagLib', () {
      final config = AudioMetadataConfig.instance;
      expect(config.defaultBackend, isA<TaglibAudioMetadataBackend>());
      expect(config.defaultBackend.id, 'taglib');
    });

    test('default backend can be overridden and restored', () {
      final config = AudioMetadataConfig.instance;
      final original = config.defaultBackend;
      final fake = FakeAudioMetadataBackend();

      config.defaultBackend = fake;
      expect(config.defaultBackend, same(fake));
      expect(config.defaultBackend.id, 'fake');

      config.defaultBackend = original;
      expect(config.defaultBackend.id, 'taglib');
    });
  });

  group('AudioMetadataService', () {
    late FakeAudioMetadataBackend backend;
    late AudioMetadataService service;

    setUp(() {
      backend = FakeAudioMetadataBackend();
      service = AudioMetadataService(backend: backend);
    });

    test('backend getter exposes the backend', () {
      expect(service.backend, same(backend));
    });

    test('uses global default if no backend provided', () {
      final config = AudioMetadataConfig.instance;
      final original = config.defaultBackend;
      final fake = FakeAudioMetadataBackend();
      config.defaultBackend = fake;

      final defaultService = AudioMetadataService();
      expect(defaultService.backend, same(fake));

      config.defaultBackend = original;
    });

    test('read returns full metadata from backend', () async {
      final doc = await service.read('song.mp3');

      expect(doc.metadata.title, 'Test Title');
      expect(doc.metadata.artist, 'Test Artist');
      expect(doc.backendId, 'fake');
      expect(backend.readPaths, ['song.mp3']);
    });

    test('read includes properties by default', () async {
      final doc = await service.read('song.flac');
      expect(doc.properties, isNotNull);
      expect(doc.properties!.bitrate, 320);
    });

    test('read can skip properties', () async {
      final doc = await service.read(
        'song.mp3',
        options: AudioReadOptions(readProperties: false),
      );
      expect(doc.properties, isNull);
    });

    test('read with readPictures returns pictures', () async {
      final doc = await service.read(
        'song.mp3',
        options: AudioReadOptions(readPictures: true),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.type, AudioPictureType.frontCover);
    });

    test('read with readRawTags returns raw tags', () async {
      final doc = await service.read(
        'song.mp3',
        options: AudioReadOptions(readRawTags: true),
      );
      expect(doc.rawTags, hasLength(1));
      expect(doc.rawTags.first.tagType, 'ID3v2');
    });

    test('write delegates to backend', () async {
      final patch = AudioMetadataPatch(
        setFields: {AudioTagField.title: 'New Title'},
        clearFields: {AudioTagField.comment},
      );
      await service.write('song.mp3', patch);

      expect(backend.writePaths, ['song.mp3']);
      expect(
        backend.writePatches.last.setFields[AudioTagField.title],
        'New Title',
      );
    });

    test('write with empty patch succeeds', () async {
      await service.write('song.mp3', const AudioMetadataPatch());
      expect(backend.writePaths, ['song.mp3']);
    });

    test('multiple sequential reads', () async {
      await service.read('a.mp3');
      await service.read('b.flac');
      await service.read('c.ogg');
      expect(backend.readPaths, ['a.mp3', 'b.flac', 'c.ogg']);
    });
  });

  // -------------------------------------------------------------------------
  // End-to-end integration (through real TagLib backend)
  // -------------------------------------------------------------------------

  group('AudioMetadataService integration', () {
    late AudioMetadataService service;

    setUp(() {
      service = AudioMetadataService(backend: TaglibAudioMetadataBackend());
    });

    test('read via service returns same as direct backend', () async {
      final doc = await service.read('$fixturesPath/test.mp3');

      expect(doc.metadata.title, 'Test Title');
      expect(doc.metadata.artist, 'Test Artist');
      expect(doc.properties, isNotNull);
      expect(doc.properties!.sampleRate, 44100);
    });

    test('write and read via service', () async {
      final path = copyFixture('writable.mp3');

      await service.write(
        path,
        const AudioMetadataPatch(
          setFields: {
            AudioTagField.title: 'Service Title',
            AudioTagField.artist: 'Service Artist',
          },
        ),
      );

      final doc = await service.read(path);
      expect(doc.metadata.title, 'Service Title');
      expect(doc.metadata.artist, 'Service Artist');
    });

    test('readBytes falls back to temp file', () async {
      final bytes = await File('$fixturesPath/test.mp3').readAsBytes();

      final doc = await service.readBytes(bytes, extensionHint: 'mp3');
      expect(doc.metadata.title, 'Test Title');
      expect(doc.metadata.artist, 'Test Artist');
    });

    test('writeBytes returns modified bytes', () async {
      final original = await File('$fixturesPath/writable.mp3').readAsBytes();

      final modified = await service.writeBytes(
        original,
        const AudioMetadataPatch(
          setFields: {AudioTagField.title: 'Bytes Roundtrip'},
        ),
        extensionHint: 'mp3',
      );

      // The output bytes should themselves be readable.
      final doc = await service.readBytes(modified, extensionHint: 'mp3');
      expect(doc.metadata.title, 'Bytes Roundtrip');
      expect(modified.length, isPositive);
    });

    test('capabilities() returns the backend caps', () async {
      final caps = await service.capabilities();
      expect(caps.canWritePictures, isTrue);
      expect(caps.canReadPictures, isTrue);
    });
  });

  group('AudioMetadataService picture round-trip', () {
    late AudioMetadataService service;
    setUp(() => service = AudioMetadataService());

    test('add cover via service round-trips', () async {
      final path = copyFixture('writable.mp3');
      final cover = Uint8List.fromList([
        // Minimal PNG header + 1x1 transparent
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      await service.write(
        path,
        AudioMetadataPatch(
          pictureOperations: [
            AddPictureOperation(
              AudioPicture(
                type: AudioPictureType.frontCover,
                mimeType: 'image/png',
                data: cover,
              ),
            ),
          ],
        ),
      );

      final doc = await service.read(
        path,
        options: const AudioReadOptions(readPictures: true),
      );
      expect(doc.frontCover, isNotNull);
      expect(doc.frontCover!.data, cover);
    });
  });
}
