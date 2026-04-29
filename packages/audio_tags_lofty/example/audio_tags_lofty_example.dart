// Example: using the Lofty (Rust) backend.
//
// Use this as an alternative to the default TagLib backend when you want a
// pure-Rust native dependency.

import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:audio_tags_lofty/audio_tags_lofty.dart';

Future<void> main() async {
  final backend = LoftyAudioMetadataBackend();
  print('Lofty version: ${backend.version}');

  final doc = await backend.readFromFile(
    'song.mp3',
    const AudioReadOptions(readPictures: true),
  );
  print('Title:  ${doc.metadata.title}');
  print('Artist: ${doc.metadata.artist}');
  print('Format: ${doc.format} + ${doc.container}');

  await backend.writeToFile(
    'song.mp3',
    const AudioMetadataPatch(setFields: {AudioTagField.title: 'New Title'}),
    const AudioWriteOptions(),
  );
}
