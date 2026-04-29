/// A Dart-first audio metadata library with pluggable backends.
library;

// Re-export the full interface so users only need `package:audio_tags`.
export 'package:audio_tags_interface/audio_tags_interface.dart';

// Re-export the default TagLib backend.
export 'package:audio_tags_taglib/audio_tags_taglib.dart';

// Service and config from this package.
export 'src/config/audio_metadata_config.dart';
export 'src/service/audio_metadata_service.dart';
