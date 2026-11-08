import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/asr/asr_segment.dart';
import 'package:kinvoice/core/ml/diarization/diarization_engine.dart';

void main() {
  group('EcapaTdnnDiarizationEngine Unit Tests', () {
    late EcapaTdnnDiarizationEngine engine;

    setUp(() {
      engine = EcapaTdnnDiarizationEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('Initializes with ECAPA-TDNN 192-dim specifications and sliding window', () {
      expect(engine.embeddingDimension, 192);
      expect(engine.windowLengthMs, 1000);
      expect(engine.windowHopMs, 500);
    });

    test('Extracts sliding embeddings from 2.5 seconds of 16kHz audio', () async {
      await engine.initialize();
      expect(engine.isInitialized, isTrue);

      // 2.5 seconds = 40,000 samples = 80,000 bytes
      // Expected windows: [0-1000ms], [500-1500ms], [1000-2000ms], [1500-2500ms] -> 4 windows
      final pcm = Uint8List(80000);
      final byteData = ByteData.sublistView(pcm);
      for (int i = 0; i < 40000; i++) {
        final sample = (math.sin(2 * math.pi * 300 * i / 16000) * 12000).round();
        byteData.setInt16(i * 2, sample, Endian.little);
      }

      final embeddings = await engine.extractEmbeddings(pcm);

      expect(embeddings.length, 4);
      expect(embeddings[0].windowStartMs, 0);
      expect(embeddings[0].windowEndMs, 1000);
      expect(embeddings[1].windowStartMs, 500);
      expect(embeddings[1].windowEndMs, 1500);
      expect(embeddings[0].embedding.length, 192);
    });

    test('Audio shorter than 1 second is zero-padded and produces 1 embedding', () async {
      // 0.4 seconds = 6,400 samples = 12,800 bytes
      final shortPcm = Uint8List(12800);
      final embeddings = await engine.extractEmbeddings(shortPcm);

      expect(embeddings.length, 1);
      expect(embeddings.first.windowStartMs, 0);
      expect(embeddings.first.embedding.length, 192);
    });

    test('diarizeAndAlign performs end-to-end speaker clustering and segment tagging', () async {
      // 3 seconds of audio with two distinct tones
      final pcm = Uint8List(96000);
      final byteData = ByteData.sublistView(pcm);

      // Speaker 1: Low frequency 200Hz
      for (int i = 0; i < 24000; i++) {
        final s = (math.sin(2 * math.pi * 200 * i / 16000) * 15000).round();
        byteData.setInt16(i * 2, s, Endian.little);
      }
      // Speaker 2: High frequency 1200Hz
      for (int i = 24000; i < 48000; i++) {
        final s = (math.sin(2 * math.pi * 1200 * i / 16000) * 15000).round();
        byteData.setInt16(i * 2, s, Endian.little);
      }

      const seg1 = AsrSegment(
        startMs: 200,
        endMs: 1200,
        text: 'First segment from low pitch speaker.',
        confidence: 0.94,
      );
      const seg2 = AsrSegment(
        startMs: 1600,
        endMs: 2800,
        text: 'Second segment from high pitch speaker.',
        confidence: 0.92,
      );

      final aligned = await engine.diarizeAndAlign(
        pcmBytes: pcm,
        segments: [seg1, seg2],
      );

      expect(aligned.length, 2);
      expect(aligned[0].speakerId, isNotNull);
      expect(aligned[1].speakerId, isNotNull);
    });
  });
}
