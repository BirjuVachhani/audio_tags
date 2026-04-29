## 0.1.0

Initial release.

- Backend interface (`AudioMetadataBackend`) with file and bytes read/write,
  capability reporting, and sealed exception hierarchy.
- Normalized data models: `AudioMetadata`, `AudioMetadataDocument`,
  `AudioMetadataPatch`, `AudioPicture`, `AudioProperties`, `AudioRawTag`,
  `AudioChapter`, `AudioReadOptions`, `AudioWriteOptions`.
- Sealed `AudioPictureOperation` (`AddPictureOperation`,
  `RemovePicturesByTypeOperation`, `RemoveAllPicturesOperation`).
- 15 standard tag fields enumerated in `AudioTagField`. `setFields` and
  `rawMutations` accept `String` or `List<String>` for multi-value fields.
- `AudioBackendCapabilities` with read/write, picture, chapter, and raw-tag
  flags plus `supportsRead()` / `supportsWrite()` helpers.
- Sealed exception hierarchy: `AudioMetadataException`,
  `AudioFormatUnsupportedException`, `AudioMetadataReadException`,
  `AudioMetadataWriteException`, `AudioOperationUnsupportedException`,
  `AudioBackendUnavailableException`. All carry optional `path` and `cause`.
- `AudioMetadataDocument.frontCover` and `pictureOfType()` accessors.
- Stable `==`, `hashCode`, `toString`, and `copyWith` on every data class.
- `AudioMetadataBackendRegistry` for runtime backend lookup.
