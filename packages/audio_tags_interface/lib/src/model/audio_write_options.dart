/// Options for writing audio metadata.
final class AudioWriteOptions {
  /// Whether to strip other tags not referenced in the patch.
  final bool stripOtherTags;

  const AudioWriteOptions({this.stripOtherTags = false});
}
