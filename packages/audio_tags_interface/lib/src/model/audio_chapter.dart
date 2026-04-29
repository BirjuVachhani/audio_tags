import 'package:meta/meta.dart';

/// A chapter marker within an audio file.
@immutable
final class AudioChapter {
  /// Unique element ID for this chapter (format-specific, not human-readable).
  final String elementId;

  /// Chapter start time.
  final Duration startTime;

  /// Chapter end time.
  final Duration endTime;

  /// Start byte offset, or `null` if not available.
  final int? startOffset;

  /// End byte offset, or `null` if not available.
  final int? endOffset;

  /// Human-readable title of this chapter.
  final String? title;

  const AudioChapter({
    required this.elementId,
    required this.startTime,
    required this.endTime,
    this.startOffset,
    this.endOffset,
    this.title,
  });

  AudioChapter copyWith({
    String? elementId,
    Duration? startTime,
    Duration? endTime,
    Object? startOffset = _sentinel,
    Object? endOffset = _sentinel,
    Object? title = _sentinel,
  }) {
    return AudioChapter(
      elementId: elementId ?? this.elementId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startOffset: identical(startOffset, _sentinel)
          ? this.startOffset
          : startOffset as int?,
      endOffset: identical(endOffset, _sentinel)
          ? this.endOffset
          : endOffset as int?,
      title: identical(title, _sentinel) ? this.title : title as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioChapter &&
      elementId == other.elementId &&
      startTime == other.startTime &&
      endTime == other.endTime &&
      startOffset == other.startOffset &&
      endOffset == other.endOffset &&
      title == other.title;

  @override
  int get hashCode =>
      Object.hash(elementId, startTime, endTime, startOffset, endOffset, title);

  @override
  String toString() =>
      'AudioChapter($elementId, $startTime - $endTime, '
      'title: $title)';
}

const Object _sentinel = Object();
