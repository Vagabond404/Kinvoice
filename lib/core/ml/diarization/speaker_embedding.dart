import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Immutable 192-dimensional speaker embedding vector produced by ECAPA-TDNN
/// from a 1-second (or sub-second) audio window.
@immutable
class SpeakerEmbedding {
  SpeakerEmbedding({
    required this.windowStartMs,
    required this.windowEndMs,
    required Float32List embedding,
  })  : assert(embedding.length == 192,
            'ECAPA-TDNN embedding must be exactly 192 dimensions, got ${embedding.length}'),
        assert(windowStartMs >= 0, 'windowStartMs must be non-negative'),
        assert(windowEndMs >= windowStartMs,
            'windowEndMs must be >= windowStartMs'),
        embedding = Float32List.fromList(embedding),
        normalizedEmbedding = _computeNormalized(embedding);

  final int windowStartMs;
  final int windowEndMs;
  final Float32List embedding;
  final Float32List normalizedEmbedding;

  int get durationMs => windowEndMs - windowStartMs;

  static Float32List _computeNormalized(Float32List vec) {
    double sumSq = 0.0;
    for (int i = 0; i < vec.length; i++) {
      sumSq += vec[i] * vec[i];
    }
    final norm = math.sqrt(sumSq);
    final normalized = Float32List(vec.length);

    if (norm > 1e-12) {
      for (int i = 0; i < vec.length; i++) {
        normalized[i] = vec[i] / norm;
      }
    } else {
      // Degenerate zero vector fallback
      normalized.setAll(0, vec);
    }
    return normalized;
  }

  /// Computes cosine similarity against another normalized embedding vector.
  double cosineSimilarityTo(SpeakerEmbedding other) {
    double dot = 0.0;
    for (int i = 0; i < 192; i++) {
      dot += normalizedEmbedding[i] * other.normalizedEmbedding[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  @override
  String toString() =>
      'SpeakerEmbedding(${windowStartMs}ms-${windowEndMs}ms, dim: 192)';
}
