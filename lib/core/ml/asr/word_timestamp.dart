import 'package:flutter/foundation.dart';

/// Immutable representation of an individual word timestamped by an ASR engine.
@immutable
class WordTimestamp {
  const WordTimestamp({
    required this.word,
    required this.startMs,
    required this.endMs,
    required this.confidence,
  })  : assert(startMs >= 0, 'startMs must be non-negative'),
        assert(endMs >= startMs, 'endMs must be greater than or equal to startMs'),
        assert(confidence >= 0.0 && confidence <= 1.0,
            'confidence must be between 0.0 and 1.0');

  final String word;
  final int startMs;
  final int endMs;
  final double confidence;

  /// Duration of this word in milliseconds.
  int get durationMs => endMs - startMs;

  WordTimestamp copyWith({
    String? word,
    int? startMs,
    int? endMs,
    double? confidence,
  }) {
    return WordTimestamp(
      word: word ?? this.word,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'word': word,
      'start_ms': startMs,
      'end_ms': endMs,
      'confidence': confidence,
    };
  }

  factory WordTimestamp.fromMap(Map<String, dynamic> map) {
    return WordTimestamp(
      word: map['word'] as String,
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      confidence: (map['confidence'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordTimestamp &&
          runtimeType == other.runtimeType &&
          word == other.word &&
          startMs == other.startMs &&
          endMs == other.endMs &&
          (confidence - other.confidence).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(word, startMs, endMs, confidence);

  @override
  String toString() =>
      'WordTimestamp("$word", ${startMs}ms-${endMs}ms, conf: ${confidence.toStringAsFixed(2)})';
}
