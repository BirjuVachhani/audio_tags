## 0.4.0

Production-readiness release. Closes the picture/lyrics/extras feature gap and
makes both backends honest about their capabilities.

### TagLib backend
- **Pictures (cover art): full read and write** for MP3 (ID3v2 APIC), FLAC,
  MP4 (M4A/M4B `covr` atom), Vorbis, Opus, WAV, AIFF — all 21 picture types.
- `AddPictureOperation`, `RemovePicturesByTypeOperation`,
  `RemoveAllPicturesOperation` are now wired through to the C++ shim.
- File `format` and tag `container` (e.g. `ID3v2.4`, `VorbisComments`, `MP4`)
  populated on every read.
- `AudioMetadata.extras` populated with non-normalized property-map fields.
- `trackTotal` / `discTotal` round-trip correctly on ID3v2 by combining into
  the `N/T` form expected by standard ID3v2 readers.
- `AudioWriteOptions.stripOtherTags` is now honored.
- Bit depth reported in `AudioProperties` for FLAC, WAV, AIFF, MP4, WV, APE.
- New `taglib_last_error()` C entry point so Dart-side errors carry a
  human-readable native message.
- Native errors classified as `AudioMetadataReadException`,
  `AudioFormatUnsupportedException`, `AudioMetadataWriteException`.
- Capability flags now reflect reality (`canWritePictures: true`).
- Static linking for macOS prebuilts; new `build_macos.sh`.
- Build hook now uses the right SHA tool per host (`shasum` vs `sha256sum`).

### Lofty backend
- Picture write (Add / RemoveByType / RemoveAll) wired through to lofty.
- Format / container detection.
- Raw mutations supported for the standard property-map keys
  (ISRC, MusicBrainz, ReplayGain, copyright, label, …).
- `extras` populated.
- Raw-tag keys now use the property-map convention (`TITLE`, `ARTIST`, …)
  instead of Rust enum Debug names. Cross-backend raw-tag tests pass.
- ISO 8601 dates parse cleanly into `year`.
- `lyrics` writes USLT for ID3v2 (via `UnsyncLyrics`); read fallback covers
  Vorbis `LYRICS` too.
- `lofty_last_error()` mirrors the TagLib shim.
- macOS prebuilts (arm64 + x64) rebuilt with the new shim.

### Public API (`audio_tags` / `audio_tags_interface`)
- `AudioMetadataService.readBytes()` and `writeBytes()` for in-memory
  workflows (temp-file fallback when the backend doesn't support bytes).
- `AudioMetadataService.capabilities()`.
- `AudioMetadataDocument.frontCover` / `pictureOfType()` accessors.
- `AudioMetadataPatch.isEmpty` / `isNotEmpty`.
- `AudioOperationUnsupportedException` added to the sealed hierarchy.
- All exception subclasses gain `path` and `cause` fields.
- `==`, `hashCode`, `toString`, `copyWith` on every data-model class.
- `AudioBackendCapabilities` gains `canReadChapters` and `canReadRawTags`,
  plus `supportsRead()` / `supportsWrite()` helpers.
- `setFields` / `rawMutations` accept `List<String>` for multi-value writes.

### Release housekeeping
- LICENSE file added (MIT, with TagLib LGPL and Lofty MIT notices).
- Per-package CHANGELOG.md.
- `publish_to: none` removed; pub.dev metadata (repository, topics) added.
- Build dependencies pinned (`code_assets`, `hooks`, `native_toolchain_c`).

### Tests
- 139 tests across the four packages — interface (34), TagLib (53), Lofty
  (33), audio_tags (19). New coverage: pictures r/w on MP3/FLAC/MP4,
  format/container detection, extras, all-15-fields round-trip on MP3 + FLAC,
  Unicode round-trip, `trackTotal` ID3v2 fix, error classification,
  in-memory bytes API.

## 0.3.0

- Added `audio_tags_lofty` package — Lofty (Rust) backend via FFI.
- Full read and write support for MP3, FLAC, OGG, MP4, WAV, AIFF, and more.
- Prebuilt binaries for macOS (arm64/x64), iOS (arm64), Android (arm64/arm/x64).
- Build hook with Cargo fallback for source builds.
- 20 integration tests against real audio fixtures.

## 0.2.0

- Refactored to monorepo with Dart pub workspace.
- Split into three packages: `audio_tags_interface`, `audio_tags_taglib`, `audio_tags`.
- Renamed user-facing package from `audio_metadata` to `audio_tags`.
- Backend interface and models extracted to `audio_tags_interface` for backend authors.
- TagLib backend isolated in `audio_tags_taglib` with its own native assets and build hook.
- `audio_tags` re-exports everything — single import for end users.
- All type names preserved (`AudioMetadata`, `AudioMetadataService`, etc.).

## 0.1.0

- Initial release with Phase 1 implementation.
- Backend-agnostic architecture with `AudioMetadataBackend` interface.
- Normalized Dart data model (`AudioMetadata`, `AudioProperties`,
  `AudioPicture`, `AudioMetadataDocument`, `AudioMetadataPatch`).
- `AudioMetadataService` high-level API for reading and writing.
- `AudioMetadataConfig` for global backend selection.
- `AudioMetadataBackendRegistry` for dynamic backend registration.
- Sealed `AudioMetadataException` hierarchy.
- Default TagLib backend with FFI bridge and JSON-based native protocol.
- C++ shim supporting read/write via TagLib's PropertyMap API.
- Native asset build hook with prebuilt binary support.
- Full read/write round-trip for common metadata fields.
- Raw tag field access and raw mutations for arbitrary property map keys.
- Audio properties: duration, bitrate, sample rate, channels.
- Smart parsing of combined "N/T" track and disc number formats.
