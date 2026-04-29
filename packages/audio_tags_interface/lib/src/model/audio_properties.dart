import 'package:meta/meta.dart';

/// Audio stream properties (codec info, duration, etc).
@immutable
final class AudioProperties {
  final Duration? duration;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final int? bitDepth;

  const AudioProperties({
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.bitDepth,
  });

  AudioProperties copyWith({
    Object? duration = _sentinel,
    Object? bitrate = _sentinel,
    Object? sampleRate = _sentinel,
    Object? channels = _sentinel,
    Object? bitDepth = _sentinel,
  }) {
    return AudioProperties(
      duration: identical(duration, _sentinel)
          ? this.duration
          : duration as Duration?,
      bitrate: identical(bitrate, _sentinel) ? this.bitrate : bitrate as int?,
      sampleRate: identical(sampleRate, _sentinel)
          ? this.sampleRate
          : sampleRate as int?,
      channels: identical(channels, _sentinel)
          ? this.channels
          : channels as int?,
      bitDepth: identical(bitDepth, _sentinel)
          ? this.bitDepth
          : bitDepth as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioProperties &&
      duration == other.duration &&
      bitrate == other.bitrate &&
      sampleRate == other.sampleRate &&
      channels == other.channels &&
      bitDepth == other.bitDepth;

  @override
  int get hashCode =>
      Object.hash(duration, bitrate, sampleRate, channels, bitDepth);

  @override
  String toString() =>
      'AudioProperties(duration: $duration, '
      'bitrate: $bitrate, sampleRate: $sampleRate, channels: $channels, '
      'bitDepth: $bitDepth)';
}

const Object _sentinel = Object();
