import '../../features/player/domain/models/transcript_segment.dart';

/// Helper to generate SubRip (.SRT) and Plain Text (.TXT) exports from transcript segments.
abstract final class SrtExportHelper {
  /// Converts milliseconds to SRT timestamp format: HH:MM:SS,mmm
  static String formatSrtTimestamp(int ms) {
    final hours = ms ~/ 3600000;
    final minutes = (ms % 3600000) ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;

    final hStr = hours.toString().padLeft(2, '0');
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    final msStr = millis.toString().padLeft(3, '0');

    return '$hStr:$mStr:$sStr,$msStr';
  }

  /// Generates a valid SubRip (.SRT) subtitle document string.
  static String generateSrt(List<TranscriptSegment> segments) {
    final buffer = StringBuffer();

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final index = i + 1;
      final startStr = formatSrtTimestamp(segment.startMs);
      final endStr = formatSrtTimestamp(segment.endMs);

      buffer.writeln(index);
      buffer.writeln('$startStr --> $endStr');
      buffer.writeln('[${segment.speakerId}] ${segment.text}');
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }

  /// Generates a clean plain text transcript format.
  static String generatePlainText(List<TranscriptSegment> segments) {
    final buffer = StringBuffer();

    for (final segment in segments) {
      final timeStr = segment.formattedStartTime;
      buffer.writeln('[$timeStr] ${segment.speakerId}: ${segment.text}');
    }

    return buffer.toString().trimRight();
  }
}
