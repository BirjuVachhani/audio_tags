/// Core interface and data models for audio metadata backends.
library;

export 'src/model/audio_chapter.dart';
export 'src/model/audio_metadata.dart';
export 'src/model/audio_metadata_document.dart';
export 'src/model/audio_metadata_patch.dart';
export 'src/model/audio_picture.dart';
export 'src/model/audio_properties.dart';
export 'src/model/audio_raw_tag.dart';
export 'src/model/audio_read_options.dart';
export 'src/model/audio_tag_field.dart';
export 'src/model/audio_write_options.dart';

export 'src/backend/audio_backend_capabilities.dart';
export 'src/backend/audio_metadata_backend.dart';
export 'src/backend/audio_metadata_backend_registry.dart';

export 'src/errors/audio_metadata_exception.dart';
