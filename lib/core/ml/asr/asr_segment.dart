import 'package:flutter/foundation.dart';
import '../../../features/player/domain/models/transcript_segment.dart';
import 'word_timestamp.dart';

/// Structured transcript segment produced by an on-device ASR model.
/// Contains word-level timestamps and formatted punctuation/capitalization.
@immutable
class AsrSegment {
  const AsrSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.confidence,
    this.words = const [],
    this.speakerId,
  })  : assert(startMs >= 0, 'startMs must be non-negative'),
        assert(endMs >= startMs, 'endMs must be greater than or equal to startMs');

  final int startMs;
  final int endMs;
  final String text;
  final double confidence;
  final List<WordTimestamp> words;
  final String? speakerId;

  int get durationMs => endMs - startMs;

  AsrSegment copyWith({
    int? startMs,
    int? endMs,
    String? text,
    double? confidence,
    List<WordTimestamp>? words,
    String? speakerId,
  }) {
    return AsrSegment(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      words: words ?? this.words,
      speakerId: speakerId ?? this.speakerId,
    );
  }

  /// Formats raw model text with proper capitalization and terminal punctuation.
  static String formatPunctuationAndCapitalization(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return '';

    // Split sentences using standard delimiters while keeping track
    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (int i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];

      if (capitalizeNext && char.trim().isNotEmpty) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
      }

      if (char == '.' || char == '!' || char == '?') {
        capitalizeNext = true;
      }
    }

    var result = buffer.toString().trim();

    // Ensure sentence ends with punctuation if missing
    if (result.isNotEmpty) {
      final lastChar = result[result.length - 1];
      if (lastChar != '.' && lastChar != '!' && lastChar != '?') {
        result = '$result.';
      }
    }

    return result;
  }

  /// Converts this ASR segment to the Kinvoice SQLite [TranscriptSegment] entity.
  TranscriptSegment toTranscriptSegment({
    required String id,
    required String recordingId,
    String defaultSpeaker = 'Speaker 1',
  }) {
    return TranscriptSegment(
      id: id,
      recordingId: recordingId,
      startMs: startMs,
      endMs: endMs,
      speakerId: speakerId ?? defaultSpeaker,
      text: text,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'start_ms': startMs,
      'end_ms': endMs,
      'text': text,
      'confidence': confidence,
      'words': words.map((w) => w.toMap()).toList(),
      'speaker_id': speakerId,
    };
  }

  factory AsrSegment.fromMap(Map<String, dynamic> map) {
    final wordsRaw = map['words'] as List<dynamic>? ?? [];
    return AsrSegment(
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      text: map['text'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      words: wordsRaw
          .map((w) => WordTimestamp.fromMap(Map<String, dynamic>.from(w as Map)))
          .toList(),
      speakerId: map['speaker_id'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsrSegment &&
          runtimeType == other.runtimeType &&
          startMs == other.startMs &&
          endMs == other.endMs &&
          text == other.text &&
          speakerId == other.speakerId &&
          listEquals(words, other.words);

  @override
  int get hashCode => Object.hash(startMs, endMs, text, speakerId, Object.hashAll(words));

  @override
  String toString() =>
      'AsrSegment(${startMs}ms-${endMs}ms, speaker: "$speakerId", text: "$text")';
}
