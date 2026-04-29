## 0.1.0

Initial release.

- User-facing package — re-exports `audio_tags_interface` and
  `audio_tags_taglib` so a single `package:audio_tags/audio_tags.dart`
  import covers everything most users need.
- TagLib backend pre-configured as the default.
- `AudioMetadataService` — high-level read/write facade with `read()`,
  `write()`, `readBytes()`, `writeBytes()`, and `capabilities()`.
- `AudioMetadataConfig` — global default-backend singleton with per-instance
  override.
- Full embedded-picture support across MP3, FLAC, MP4, Vorbis, Opus, WAV,
  and AIFF — read, write, replace, remove. All standard picture types.
- In-memory bytes API (`readBytes` / `writeBytes`) with automatic
  temporary-file fallback for backends that lack native byte-level I/O.
- Native asset build hook with prebuilt binaries — no C++ toolchain required
  on supported platforms.
