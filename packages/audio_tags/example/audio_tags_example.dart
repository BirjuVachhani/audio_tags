// Example: read and write audio metadata with the default TagLib backend.
//
// A single import of `package:audio_tags/audio_tags.dart` covers everything.

import 'dart:io';

import 'package:audio_tags/audio_tags.dart';

Future<void> main() async {
  final service = AudioMetadataService();

  // ── Read ────────────────────────────────────────────────────────────────
  final doc = await service.read(
    'song.mp3',
    options: const AudioReadOptions(readPictures: true),
  );
  print('${doc.metadata.title} — ${doc.metadata.artist}');
  print('Album:    ${doc.metadata.album} (${doc.metadata.year})');
  print('Duration: ${doc.properties?.duration}');
  print('Format:   ${doc.format} + ${doc.container}');

  // Save the front cover, if present.
  final cover = doc.frontCover;
  if (cover != null) {
    await File('cover.jpg').writeAsBytes(cover.data);
    print('Saved cover.jpg (${cover.data.length} bytes)');
  }

  // ── Write ───────────────────────────────────────────────────────────────
  await service.write(
    'song.mp3',
    AudioMetadataPatch(
      setFields: {
        AudioTagField.title: 'New Title',
        AudioTagField.artist: 'New Artist',
      },
    ),
  );

  // ── Capability reporting ───────────────────────────────────────────────
  final caps = await service.capabilities();
  print(
    'Pictures: read=${caps.canReadPictures}, write=${caps.canWritePictures}',
  );
  print('Formats:  ${caps.supportedFormats}');
}
