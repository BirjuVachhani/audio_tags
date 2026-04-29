// Example: using the TagLib backend directly.
//
// Most users should depend on `audio_tags` instead — it includes this backend
// pre-configured. Use this package directly only if you want the TagLib
// backend without the service layer.

import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:audio_tags_taglib/audio_tags_taglib.dart';

Future<void> main() async {
  final backend = TaglibAudioMetadataBackend();
  print('TagLib version: ${backend.version}');

  final doc = await backend.readFromFile(
    'song.mp3',
    const AudioReadOptions(readPictures: true),
  );
  print('Title:  ${doc.metadata.title}');
  print('Artist: ${doc.metadata.artist}');
  print('Album:  ${doc.metadata.album} (${doc.metadata.year})');
  print('Format: ${doc.format} + ${doc.container}');
  print('Cover:  ${doc.frontCover != null ? 'embedded' : 'none'}');

  await backend.writeToFile(
    'song.mp3',
    const AudioMetadataPatch(setFields: {AudioTagField.title: 'New Title'}),
    const AudioWriteOptions(),
  );
}
