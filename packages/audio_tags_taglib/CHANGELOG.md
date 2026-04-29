## 0.1.0

Initial release.

- TagLib (C++) backend exposed as `TaglibAudioMetadataBackend` via FFI.
- Read and write of common metadata fields across MP3, FLAC, OGG (Vorbis,
  Opus, Speex), MP4 / M4A / M4B / AAC, WAV, AIFF, WMA / ASF, APE, Musepack,
  WavPack, DSF, DFF, and TrueAudio.
- Full embedded-picture read and write for ID3v2 (MP3), FLAC, MP4, Vorbis,
  Opus, WAV, and AIFF. All standard picture types (front cover, back cover,
  band logo, illustration, leaflet, ...) round-trip cleanly. MIME type
  sniffed from the bytes when not supplied (jpeg, png, gif, bmp, tiff).
- File `format` (`mp3`, `flac`, ...) and tag `container` (`ID3v2.4`,
  `VorbisComments`, `MP4`, ...) populated on every read.
- `AudioMetadata.extras` populated with non-normalized property-map fields
  (ISRC, MusicBrainz IDs, ReplayGain, copyright, label, ...).
- `trackTotal` and `discTotal` round-trip correctly on ID3v2 (MP3) via the
  `N/T` form expected by standard ID3v2 readers.
- Bit depth surfaced in `AudioProperties` for FLAC, WAV, AIFF, MP4, WavPack,
  and APE.
- Chapter reading (ID3v2 CHAP / CTOC frames).
- Raw-tag read and write.
- Native errors mapped to typed exceptions
  (`AudioMetadataReadException`, `AudioFormatUnsupportedException`,
  `AudioMetadataWriteException`) carrying the file path and a native-side
  message via the `taglib_last_error` C entry point.
- `AudioWriteOptions.stripOtherTags` strips legacy ID3v1 and APE tags from
  MP3, ID3 from FLAC, INFO from WAV.
- Native asset build hook with three-tier resolution: prebuilt binary →
  system TagLib (detected via Homebrew, apt, or pkg-config) → download and
  build TagLib 2.2.1 source via CMake.
- Prebuilt binaries: macOS (arm64, x64), iOS (arm64), Android (arm, arm64,
  x64).
- Build scripts (`build_macos.sh`, `build_linux.sh`, `build_windows.ps1`)
  for producing prebuilts locally.
