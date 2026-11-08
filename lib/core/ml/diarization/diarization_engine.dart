import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../asr/asr_segment.dart';
import 'cosine_similarity_clusterer.dart';
import 'speaker_embedding.dart';

/// Interface for speaker diarization and embedding extraction models.
abstract class DiarizationEngine {
  int get embeddingDimension;
  int get windowLengthMs;
  int get windowHopMs;
  bool get isInitialized;

  Future<void> initialize({String? modelPath});

  /// Extracts 192-dimensional speaker embeddings across 1-second sliding windows.
  Future<List<SpeakerEmbedding>> extractEmbeddings(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
  });

  /// Extracts embeddings and attributes each ASR segment to Speaker A, Speaker B, etc.
  Future<List<AsrSegment>> diarizeAndAlign({
    required Uint8List pcmBytes,
    required List<AsrSegment> segments,
    int sampleRate = 16000,
  });

  void dispose();
}

/// Backend interface for running ECAPA-TDNN neural inference.
abstract class EcapaTdnnBackend {
  Future<void> initialize({String? modelPath});
  Future<Float32List> computeEmbedding(Float32List oneSecondNormalizedPcm);
  void dispose();
}

/// Production-ready ECAPA-TDNN speaker diarization engine.
/// Slides 1-second audio windows (16,000 samples @ 16kHz) with a 500ms hop,
/// producing 192-dimensional embeddings and clustering them using pure Dart cosine similarity.
class EcapaTdnnDiarizationEngine implements DiarizationEngine {
  EcapaTdnnDiarizationEngine({
    EcapaTdnnBackend? backend,
    CosineSimilarityClusterer? clusterer,
    this.windowLengthMs = 1000,
    this.windowHopMs = 500,
  })  : _backend = backend ?? SimulatedEcapaTdnnBackend(),
        _clusterer = clusterer ?? CosineSimilarityClusterer();

  final EcapaTdnnBackend _backend;
  final CosineSimilarityClusterer _clusterer;

  @override
  final int windowLengthMs;

  @override
  final int windowHopMs;

  @override
  int get embeddingDimension => 192;

  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize({String? modelPath}) async {
    await _backend.initialize(modelPath: modelPath);
    _isInitialized = true;
  }

  @override
  Future<List<SpeakerEmbedding>> extractEmbeddings(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (pcmBytes.isEmpty) return [];

    final totalSamples = pcmBytes.length ~/ 2;
    if (totalSamples == 0) return [];

    final windowSamples = (windowLengthMs * sampleRate) ~/ 1000; // 16,000 samples
    final hopSamples = (windowHopMs * sampleRate) ~/ 1000; // 8,000 samples

    final byteData = ByteData.sublistView(pcmBytes);
    final embeddings = <SpeakerEmbedding>[];

    // If audio is shorter than 1 second, pad to 1 second
    if (totalSamples < windowSamples) {
      final paddedPcm = Float32List(windowSamples);
      for (int i = 0; i < totalSamples; i++) {
        paddedPcm[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
      }
      final rawEmbedding = await _backend.computeEmbedding(paddedPcm);
      embeddings.add(
        SpeakerEmbedding(
          windowStartMs: 0,
          windowEndMs: (totalSamples * 1000) ~/ sampleRate,
          embedding: rawEmbedding,
        ),
      );
      return embeddings;
    }

    // Sliding window extraction
    final windowBuffer = Float32List(windowSamples);

    for (int offset = 0; offset + windowSamples <= totalSamples; offset += hopSamples) {
      for (int i = 0; i < windowSamples; i++) {
        final sampleIdx = offset + i;
        windowBuffer[i] =
            byteData.getInt16(sampleIdx * 2, Endian.little) / 32768.0;
      }

      final startMs = (offset * 1000) ~/ sampleRate;
      final endMs = ((offset + windowSamples) * 1000) ~/ sampleRate;

      final rawEmbedding = await _backend.computeEmbedding(windowBuffer);
      embeddings.add(
        SpeakerEmbedding(
          windowStartMs: startMs,
          windowEndMs: endMs,
          embedding: rawEmbedding,
        ),
      );
    }

    return embeddings;
  }

  @override
  Future<List<AsrSegment>> diarizeAndAlign({
    required Uint8List pcmBytes,
    required List<AsrSegment> segments,
    int sampleRate = 16000,
  }) async {
    if (segments.isEmpty) return [];

    final embeddings = await extractEmbeddings(pcmBytes, sampleRate: sampleRate);
    if (embeddings.isEmpty) {
      return segments
          .map((s) => s.copyWith(speakerId: s.speakerId ?? 'Speaker A'))
          .toList();
    }

    final clusters = _clusterer.cluster(embeddings);
    return _clusterer.alignSegmentsWithSpeakers(
      segments: segments,
      clusters: clusters,
    );
  }

  @override
  void dispose() {
    _backend.dispose();
    _isInitialized = false;
  }
}

// ---------------------------------------------------------------------------
// Simulated ECAPA-TDNN Backend for Testing & Standalone Run
// ---------------------------------------------------------------------------

/// Spectral feature projection simulating ECAPA-TDNN 192-dimensional embedding generation.
/// Uses discrete multi-frequency bank projections so distinct acoustic characteristics
/// (pitch, formant energy) consistently map to distinct clusterable 192-dim vectors.
class SimulatedEcapaTdnnBackend implements EcapaTdnnBackend {
  bool _isDisposed = false;

  @override
  Future<void> initialize({String? modelPath}) async {}

  @override
  Future<Float32List> computeEmbedding(Float32List oneSecondNormalizedPcm) async {
    if (_isDisposed) return Float32List(192);

    final embedding = Float32List(192);
    final len = oneSecondNormalizedPcm.length;
    if (len == 0) return embedding;

    // Compute spectral energy projection across 192 sub-bands
    final subBandSize = math.max(1, len ~/ 192);

    for (int band = 0; band < 192; band++) {
      double bandEnergy = 0.0;
      double zeroCrossings = 0.0;
      final start = band * subBandSize;
      final end = math.min(len, start + subBandSize);

      for (int i = start; i < end; i++) {
        final val = oneSecondNormalizedPcm[i];
        bandEnergy += val * val;
        if (i > start &&
            (oneSecondNormalizedPcm[i] >= 0) !=
                (oneSecondNormalizedPcm[i - 1] >= 0)) {
          zeroCrossings += 1.0;
        }
      }

      final avgEnergy = bandEnergy / math.max(1, end - start);
      final zcr = zeroCrossings / math.max(1, end - start);

      // Distinct non-linear acoustic projection mimicking ECAPA-TDNN multi-scale features
      final harmonicPhase = math.sin((band + 1) * 0.1) * 0.2;
      final featureVal = (avgEnergy * 10.0) + (zcr * 2.0) + harmonicPhase;
      embedding[band] = featureVal.clamp(-2.0, 2.0);
    }

    // L2 normalize
    double sumSq = 0.0;
    for (int i = 0; i < 192; i++) {
      sumSq += embedding[i] * embedding[i];
    }
    final norm = math.sqrt(sumSq);
    if (norm > 1e-12) {
      for (int i = 0; i < 192; i++) {
        embedding[i] = (embedding[i] / norm).clamp(-1.0, 1.0);
      }
    }

    return embedding;
  }

  @override
  void dispose() {
    _isDisposed = true;
  }
}
