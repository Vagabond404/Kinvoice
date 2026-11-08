import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/asr/asr_segment.dart';
import 'package:kinvoice/core/ml/diarization/cosine_similarity_clusterer.dart';
import 'package:kinvoice/core/ml/diarization/speaker_embedding.dart';

void main() {
  group('Cosine Similarity Pure Mathematical Tests', () {
    test('Identical 192-dimensional vectors yield similarity 1.0', () {
      final vecA = Float32List(192);
      final vecB = Float32List(192);
      for (int i = 0; i < 192; i++) {
        vecA[i] = (i + 1).toDouble();
        vecB[i] = (i + 1).toDouble();
      }

      final sim = CosineSimilarityClusterer.computeCosineSimilarity(vecA, vecB);
      expect((sim - 1.0).abs(), lessThan(1e-5));
    });

    test('Orthogonal 192-dimensional vectors yield similarity 0.0', () {
      final vecA = Float32List(192);
      final vecB = Float32List(192);

      // vecA nonzero only in first 96 dims, vecB nonzero only in last 96 dims
      for (int i = 0; i < 96; i++) {
        vecA[i] = 1.0;
      }
      for (int i = 96; i < 192; i++) {
        vecB[i] = 1.0;
      }

      final sim = CosineSimilarityClusterer.computeCosineSimilarity(vecA, vecB);
      expect(sim.abs(), lessThan(1e-5));
    });

    test('Opposite vectors yield similarity -1.0', () {
      final vecA = Float32List(192);
      final vecB = Float32List(192);
      for (int i = 0; i < 192; i++) {
        vecA[i] = (i + 1).toDouble();
        vecB[i] = -(i + 1).toDouble();
      }

      final sim = CosineSimilarityClusterer.computeCosineSimilarity(vecA, vecB);
      expect((sim - (-1.0)).abs(), lessThan(1e-5));
    });
  });

  group('SpeakerEmbedding Vector Normalization Tests', () {
    test('Ensures vector is exactly 192 dimensions', () {
      expect(
        () => SpeakerEmbedding(
          windowStartMs: 0,
          windowEndMs: 1000,
          embedding: Float32List(128), // Invalid dim
        ),
        throwsAssertionError,
      );

      final valid = SpeakerEmbedding(
        windowStartMs: 0,
        windowEndMs: 1000,
        embedding: Float32List(192),
      );
      expect(valid.embedding.length, 192);
      expect(valid.normalizedEmbedding.length, 192);
    });

    test('Normalized embedding has L2 norm equal to 1.0', () {
      final raw = Float32List(192);
      for (int i = 0; i < 192; i++) {
        raw[i] = (i * 3.5);
      }

      final emb = SpeakerEmbedding(
        windowStartMs: 0,
        windowEndMs: 1000,
        embedding: raw,
      );

      double normSq = 0.0;
      for (int i = 0; i < 192; i++) {
        normSq += emb.normalizedEmbedding[i] * emb.normalizedEmbedding[i];
      }
      expect((normSq - 1.0).abs(), lessThan(1e-4));
    });
  });

  group('CosineSimilarityClusterer Diarization & Alignment Tests', () {
    late CosineSimilarityClusterer clusterer;

    setUp(() {
      clusterer = CosineSimilarityClusterer(similarityThreshold: 0.70);
    });

    SpeakerEmbedding createSyntheticEmbedding({
      required int startMs,
      required int endMs,
      required double baseFrequency,
    }) {
      final raw = Float32List(192);
      for (int i = 0; i < 192; i++) {
        raw[i] = (i % 2 == 0 ? baseFrequency : -baseFrequency) + (i * 0.01);
      }
      return SpeakerEmbedding(
        windowStartMs: startMs,
        windowEndMs: endMs,
        embedding: raw,
      );
    }

    test('Single speaker session assigns all embeddings to Speaker A', () {
      final embeddings = [
        createSyntheticEmbedding(startMs: 0, endMs: 1000, baseFrequency: 2.0),
        createSyntheticEmbedding(startMs: 500, endMs: 1500, baseFrequency: 2.05),
        createSyntheticEmbedding(startMs: 1000, endMs: 2000, baseFrequency: 1.95),
      ];

      final clusters = clusterer.cluster(embeddings);

      expect(clusters.length, 1);
      expect(clusters.first.label, 'Speaker A');
      expect(clusters.first.count, 3);
    });

    test('Two alternating speakers are separated into Speaker A and Speaker B', () {
      // Speaker 1: baseFrequency = 5.0
      // Speaker 2: baseFrequency = -5.0 (orthogonal/distinct acoustic signature)
      final embeddings = [
        createSyntheticEmbedding(startMs: 0, endMs: 1000, baseFrequency: 5.0),
        createSyntheticEmbedding(startMs: 500, endMs: 1500, baseFrequency: 5.1),
        createSyntheticEmbedding(startMs: 2000, endMs: 3000, baseFrequency: -5.0),
        createSyntheticEmbedding(startMs: 2500, endMs: 3500, baseFrequency: -5.1),
      ];

      final clusters = clusterer.cluster(embeddings);

      expect(clusters.length, 2);
      expect(clusters[0].label, 'Speaker A');
      expect(clusters[0].count, 2);
      expect(clusters[1].label, 'Speaker B');
      expect(clusters[1].count, 2);
    });

    test('alignSegmentsWithSpeakers attributes transcript segments based on time overlap', () {
      final embSpeaker1 = [
        createSyntheticEmbedding(startMs: 0, endMs: 1000, baseFrequency: 5.0),
        createSyntheticEmbedding(startMs: 500, endMs: 1500, baseFrequency: 5.0),
      ];
      final embSpeaker2 = [
        createSyntheticEmbedding(startMs: 2000, endMs: 3000, baseFrequency: -5.0),
        createSyntheticEmbedding(startMs: 2500, endMs: 3500, baseFrequency: -5.0),
      ];

      final allEmbeddings = [...embSpeaker1, ...embSpeaker2];
      final clusters = clusterer.cluster(allEmbeddings);

      const seg1 = AsrSegment(
        startMs: 100,
        endMs: 1200,
        text: 'Hello from speaker one.',
        confidence: 0.95,
      );

      const seg2 = AsrSegment(
        startMs: 2100,
        endMs: 3200,
        text: 'Response from speaker two.',
        confidence: 0.93,
      );

      final aligned = clusterer.alignSegmentsWithSpeakers(
        segments: [seg1, seg2],
        clusters: clusters,
      );

      expect(aligned.length, 2);
      expect(aligned[0].speakerId, 'Speaker A');
      expect(aligned[1].speakerId, 'Speaker B');
    });

    test('Fallback attributes temporally closest speaker when segment has zero overlap', () {
      final clusters = clusterer.cluster([
        createSyntheticEmbedding(startMs: 5000, endMs: 6000, baseFrequency: 4.0),
      ]);

      const shortUtterance = AsrSegment(
        startMs: 50,
        endMs: 200, // No direct overlap with 5000ms
        text: 'Quick remark.',
        confidence: 0.88,
      );

      final aligned = clusterer.alignSegmentsWithSpeakers(
        segments: [shortUtterance],
        clusters: clusters,
      );

      expect(aligned.first.speakerId, 'Speaker A');
    });
  });
}
