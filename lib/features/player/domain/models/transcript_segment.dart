import 'package:flutter/foundation.dart';

/// Immutable domain model representing an attributed audio transcript segment.
@immutable
class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.recordingId,
    required this.startMs,
    required this.endMs,
    required this.speakerId,
    required this.text,
  });

  final String id;
  final String recordingId;
  final int startMs;
  final int endMs;
  final String speakerId;
  final String text;

  /// Duration of this spoken segment in milliseconds.
  int get durationMs => endMs - startMs;

  /// Formatted start timestamp mm:ss.
  String get formattedStartTime => _formatMs(startMs);

  /// Formatted end timestamp mm:ss.
  String get formattedEndTime => _formatMs(endMs);

  /// Formatted timestamp range (e.g., "00:12 - 00:18").
  String get formattedTimeRange => '$formattedStartTime - $formattedEndTime';

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }

  /// Converts this segment to a database map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recording_id': recordingId,
      'start_ms': startMs,
      'end_ms': endMs,
      'speaker_id': speakerId,
      'text': text,
    };
  }

  /// Constructs a segment from a database map.
  factory TranscriptSegment.fromMap(Map<String, dynamic> map) {
    return TranscriptSegment(
      id: map['id'] as String,
      recordingId: map['recording_id'] as String,
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      speakerId: map['speaker_id'] as String,
      text: map['text'] as String,
    );
  }

  TranscriptSegment copyWith({
    String? id,
    String? recordingId,
    int? startMs,
    int? endMs,
    String? speakerId,
    String? text,
  }) {
    return TranscriptSegment(
      id: id ?? this.id,
      recordingId: recordingId ?? this.recordingId,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      speakerId: speakerId ?? this.speakerId,
      text: text ?? this.text,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranscriptSegment &&
        other.id == id &&
        other.recordingId == recordingId &&
        other.startMs == startMs &&
        other.endMs == endMs &&
        other.speakerId == speakerId &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(
    id,
    recordingId,
    startMs,
    endMs,
    speakerId,
    text,
  );

  @override
  String toString() {
    return 'TranscriptSegment(id: $id, speaker: $speakerId, time: $formattedTimeRange, text: "$text")';
  }
}
