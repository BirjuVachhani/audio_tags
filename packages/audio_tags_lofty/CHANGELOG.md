## 0.1.0

Initial release.

- Lofty (Rust) backend exposed as `LoftyAudioMetadataBackend` via FFI to a
  Rust `cdylib` shim over [lofty-rs](https://github.com/Serial-ATA/lofty-rs).
- Read and write of common metadata fields across MP3, FLAC, OGG (Vorbis,
  Opus, Speex), MP4 / M4A / M4B / AAC, WAV, AIFF, APE, Musepack, and
  WavPack.
- Embedded-picture read and write across MP3, FLAC, MP4, Vorbis, Opus, WAV,
  and AIFF via `AddPictureOperation`, `RemovePicturesByTypeOperation`, and
  `RemoveAllPicturesOperation`. MIME type sniffed from the bytes when not
  supplied.
- File `format` and tag `container` populated on every read.
- `AudioMetadata.extras` populated with non-normalized fields (ISRC,
  MusicBrainz IDs, ReplayGain, copyright, label, ...).
- Raw-tag keys use the property-map convention (`TITLE`, `ARTIST`,
  `MUSICBRAINZ_TRACKID`, ...) so they match the TagLib backend output.
- ISO 8601 dates such as `"2024-03-15"` parse cleanly into `year: 2024`.
- Lyrics write to USLT for ID3v2 via `ItemKey::UnsyncLyrics`; reads fall
  back through both UnsyncLyrics and Lyrics for cross-format support.
- `AudioWriteOptions.stripOtherTags` removes non-primary tag containers.
- Native errors mapped to typed exceptions
  (`AudioMetadataReadException`, `AudioFormatUnsupportedException`,
  `AudioMetadataWriteException`) carrying the file path and a native-side
  message via the `lofty_last_error` C entry point.
- Native asset build hook with prebuilt binaries and a Cargo fallback that
  builds the cdylib from source on platforms without a prebuilt.
- Prebuilt binaries: macOS (arm64, x64), iOS (arm64), Android (arm, arm64,
  x64), Linux (x64), Windows (x64).
- Build scripts (`build_macos.sh`, `build_linux.sh`, `build_windows.ps1`)
  for producing prebuilts locally.
