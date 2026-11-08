import 'dart:math' as math;
import 'dart:typed_data';
import '../asr/asr_segment.dart';
import 'speaker_embedding.dart';

/// Cluster of speaker embeddings sharing a common voice identity.
class SpeakerCluster {
  SpeakerCluster({
    required this.label,
    required SpeakerEmbedding initialEmbedding,
  })  : _embeddings = [initialEmbedding],
        _sumVector = Float32List.fromList(initialEmbedding.normalizedEmbedding),
        centroid = Float32List.fromList(initialEmbedding.normalizedEmbedding);

  final String label;
  final List<SpeakerEmbedding> _embeddings;
  final Float32List _sumVector;
  Float32List centroid;

  List<SpeakerEmbedding> get embeddings => List.unmodifiable(_embeddings);
  int get count => _embeddings.length;

  /// Incorporates a new embedding and recalculates the cluster centroid.
  void addEmbedding(SpeakerEmbedding embedding) {
    _embeddings.add(embedding);

    // Incrementally update running vector sum
    for (int i = 0; i < 192; i++) {
      _sumVector[i] += embedding.normalizedEmbedding[i];
    }

    // Re-normalize centroid to unit length
    double sumSq = 0.0;
    for (int i = 0; i < 192; i++) {
      sumSq += _sumVector[i] * _sumVector[i];
    }
    final norm = math.sqrt(sumSq);
    if (norm > 1e-12) {
      for (int i = 0; i < 192; i++) {
        centroid[i] = _sumVector[i] / norm;
      }
    }
  }

  /// Computes cosine similarity between an embedding and this cluster's centroid.
  double similarityTo(SpeakerEmbedding embedding) {
    double dot = 0.0;
    for (int i = 0; i < 192; i++) {
      dot += centroid[i] * embedding.normalizedEmbedding[i];
    }
    return dot.clamp(-1.0, 1.0);
  }
}

/// Pure Dart cosine similarity clustering engine for speaker diarization.
/// Automatically partitions 192-dimensional embeddings into "Speaker A", "Speaker B",
/// "Speaker C", etc. and aligns speaker labels with ASR transcript segments.
class CosineSimilarityClusterer {
  CosineSimilarityClusterer({
    this.similarityThreshold = 0.68,
  }) : assert(similarityThreshold >= -1.0 && similarityThreshold <= 1.0,
            'similarityThreshold must be between -1.0 and 1.0');

  /// Threshold above which an embedding is considered to belong to an existing speaker.
  final double similarityThreshold;

  /// Pure mathematical cosine similarity between two 192-dim vectors.
  static double computeCosineSimilarity(Float32List a, Float32List b) {
    assert(a.length == 192 && b.length == 192, 'Vectors must be 192 dimensions');

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < 192; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denom = math.sqrt(normA) * math.sqrt(normB);
    if (denom < 1e-12) return 0.0;

    return (dot / denom).clamp(-1.0, 1.0);
  }

  /// Automatically clusters a sequence of 192-dimensional speaker embeddings.
  List<SpeakerCluster> cluster(List<SpeakerEmbedding> embeddings) {
    if (embeddings.isEmpty) return [];

    final clusters = <SpeakerCluster>[];

    for (final embedding in embeddings) {
      if (clusters.isEmpty) {
        clusters.add(
          SpeakerCluster(
            label: _getSpeakerLabel(0),
            initialEmbedding: embedding,
          ),
        );
        continue;
      }

      // Find closest existing cluster
      int bestClusterIdx = -1;
      double highestSim = -1.0;

      for (int i = 0; i < clusters.length; i++) {
        final sim = clusters[i].similarityTo(embedding);
        if (sim > highestSim) {
          highestSim = sim;
          bestClusterIdx = i;
        }
      }

      if (highestSim >= similarityThreshold && bestClusterIdx != -1) {
        // Assign to existing speaker
        clusters[bestClusterIdx].addEmbedding(embedding);
      } else {
        // Spawn new speaker identity
        final newLabel = _getSpeakerLabel(clusters.length);
        clusters.add(
          SpeakerCluster(
            label: newLabel,
            initialEmbedding: embedding,
          ),
        );
      }
    }

    return clusters;
  }

  /// Aligns speaker clusters with ASR transcript segments based on temporal overlap.
  List<AsrSegment> alignSegmentsWithSpeakers({
    required List<AsrSegment> segments,
    required List<SpeakerCluster> clusters,
  }) {
    if (segments.isEmpty) return [];
    if (clusters.isEmpty) {
      // Default to "Speaker A" if no clusters exist
      return segments
          .map((s) => s.copyWith(speakerId: s.speakerId ?? 'Speaker A'))
          .toList();
    }

    // Flatten all embeddings with their assigned cluster label
    final labeledEmbeddings = <_LabeledEmbedding>[];
    for (final cluster in clusters) {
      for (final emb in cluster.embeddings) {
        labeledEmbeddings.add(_LabeledEmbedding(emb, cluster.label));
      }
    }

    final alignedSegments = <AsrSegment>[];

    for (final segment in segments) {
      // Find all embeddings overlapping with this segment [startMs, endMs]
      final speakerDurations = <String, int>{};

      for (final item in labeledEmbeddings) {
        final overlapStart = math.max(segment.startMs, item.embedding.windowStartMs);
        final overlapEnd = math.min(segment.endMs, item.embedding.windowEndMs);
        final overlapMs = overlapEnd - overlapStart;

        if (overlapMs > 0) {
          speakerDurations[item.speakerLabel] =
              (speakerDurations[item.speakerLabel] ?? 0) + overlapMs;
        }
      }

      String chosenSpeaker;
      if (speakerDurations.isNotEmpty) {
        // Select speaker with maximum overlapping milliseconds
        String maxSpeaker = clusters.first.label;
        int maxOverlap = -1;
        speakerDurations.forEach((speaker, duration) {
          if (duration > maxOverlap) {
            maxOverlap = duration;
            maxSpeaker = speaker;
          }
        });
        chosenSpeaker = maxSpeaker;
      } else {
        // No direct temporal overlap: find the temporally closest embedding
        _LabeledEmbedding? closest;
        int minDistance = 0x7FFFFFFF;

        for (final item in labeledEmbeddings) {
          final centerSegment = (segment.startMs + segment.endMs) ~/ 2;
          final centerWindow =
              (item.embedding.windowStartMs + item.embedding.windowEndMs) ~/ 2;
          final dist = (centerSegment - centerWindow).abs();
          if (dist < minDistance) {
            minDistance = dist;
            closest = item;
          }
        }

        chosenSpeaker = closest?.speakerLabel ?? clusters.first.label;
      }

      alignedSegments.add(segment.copyWith(speakerId: chosenSpeaker));
    }

    return alignedSegments;
  }

  /// Convenience pipeline: clusters embeddings and aligns with ASR segments in one call.
  List<AsrSegment> clusterAndAlign({
    required List<AsrSegment> segments,
    required List<SpeakerEmbedding> embeddings,
  }) {
    final clusters = cluster(embeddings);
    return alignSegmentsWithSpeakers(segments: segments, clusters: clusters);
  }

  static String _getSpeakerLabel(int index) {
    if (index < 26) {
      return 'Speaker ${String.fromCharCode(65 + index)}'; // Speaker A, Speaker B, ...
    }
    return 'Speaker ${index + 1}';
  }
}

class _LabeledEmbedding {
  const _LabeledEmbedding(this.embedding, this.speakerLabel);
  final SpeakerEmbedding embedding;
  final String speakerLabel;
}
