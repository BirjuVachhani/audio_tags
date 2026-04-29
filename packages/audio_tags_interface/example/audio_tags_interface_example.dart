// Example: implementing a minimal read-only AudioMetadataBackend.
//
// This is the contract every backend implements. End users should depend on
// `audio_tags` instead — this package is for backend authors.

import 'package:audio_tags_interface/audio_tags_interface.dart';

final class _ExampleBackend implements AudioMetadataBackend {
  @override
  String get id => 'example';

  @override
  String? get version => '0.0.1';

  @override
  bool get supportsReading => true;

  @override
  bool get supportsWriting => false;

  @override
  Future<AudioMetadataDocument> readFromFile(
    String path,
    AudioReadOptions options,
  ) async {
    return AudioMetadataDocument(
      metadata: const AudioMetadata(title: 'Example title'),
      backendId: id,
    );
  }

  @override
  Future<AudioMetadataDocument> readFromBytes(
    List<int> bytes,
    AudioReadOptions options,
  ) async => throw UnsupportedError('$id does not support readFromBytes');

  @override
  Future<void> writeToFile(
    String path,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async => throw UnsupportedError('$id is read-only');

  @override
  Future<List<int>> writeToBytes(
    List<int> bytes,
    AudioMetadataPatch patch,
    AudioWriteOptions options,
  ) async => throw UnsupportedError('$id is read-only');

  @override
  Future<AudioBackendCapabilities> getCapabilities() async {
    return const AudioBackendCapabilities(
      backendVersion: '0.0.1',
      canReadFromFile: true,
      canReadFromBytes: false,
      canWriteToFile: false,
      canWriteToBytes: false,
      canReadPictures: false,
      canWritePictures: false,
      supportedFormats: {'mp3'},
      writableFormats: {},
    );
  }
}

Future<void> main() async {
  final backend = _ExampleBackend();
  final doc = await backend.readFromFile('song.mp3', const AudioReadOptions());
  print('Title via ${backend.id}: ${doc.metadata.title}');
}
