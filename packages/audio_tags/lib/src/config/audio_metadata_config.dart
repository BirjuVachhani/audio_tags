import 'package:audio_tags_interface/audio_tags_interface.dart';
import 'package:audio_tags_taglib/audio_tags_taglib.dart';

/// Global configuration for the audio metadata library.
final class AudioMetadataConfig {
  AudioMetadataConfig._();

  static final AudioMetadataConfig instance = AudioMetadataConfig._();

  /// The default backend used when no backend is explicitly provided.
  AudioMetadataBackend defaultBackend = TaglibAudioMetadataBackend();
}
