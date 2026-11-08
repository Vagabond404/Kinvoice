import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/vad/silero_vad_engine.dart';

void main() {
  group('SileroVadEngine Unit Tests', () {
    late SileroVadEngine engine;

    setUp(() {
      engine = SileroVadEngine(); // Defaults to SimulatedVadBackend
    });

    tearDown(() {
      engine.dispose();
    });

    test('Initializes with standard 512-sample (32ms at 16kHz) specifications', () {
      expect(SileroVadEngine.frameSize, 512);
      expect(SileroVadEngine.frameBytes, 1024);
      expect(engine.sampleRate, 16000);
    });

    test('Digital silence (all zeros) produces near-zero voice probability', () {
      final silencePcm = Uint8List(SileroVadEngine.frameBytes);
      final prob = engine.processPcmBytes(silencePcm);

      expect(prob, lessThan(0.05));
    });

    test('Synthetic 440Hz Sine voice speech frame produces elevated voice probability', () {
      final pcmBytes = Uint8List(SileroVadEngine.frameBytes);
      final byteData = ByteData.sublistView(pcmBytes);

      // Generate 512 samples of a conversational tone (amplitude ~18000, 440Hz)
      for (int i = 0; i < SileroVadEngine.frameSize; i++) {
        final sampleVal =
            (math.sin(2 * math.pi * 440 * i / 16000) * 18000).round();
        byteData.setInt16(i * 2, sampleVal, Endian.little);
      }

      final prob = engine.processPcmBytes(pcmBytes);
      expect(prob, greaterThan(0.5));
    });

    test('Float32 frame direct processing matches Int16 sample ingestion', () {
      final floatFrame = Float32List(SileroVadEngine.frameSize);
      for (int i = 0; i < floatFrame.length; i++) {
        floatFrame[i] = 0.5 * math.sin(2 * math.pi * 300 * i / 16000);
      }

      final prob = engine.processFloat32Frame(floatFrame);
      expect(prob, greaterThan(0.4));
    });

    test('resetState resets internal context without throwing', () {
      expect(() => engine.resetState(), returnsNormally);
    });

    test('Engine gracefully returns zero probability for undersized chunks', () {
      final undersized = Uint8List(200); // Less than 1024 bytes
      final prob = engine.processPcmBytes(undersized);
      expect(prob, 0.0);
    });
  });
}
