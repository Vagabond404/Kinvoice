import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/rms_calculator.dart';

void main() {
  group('RmsCalculator & Audio Algorithms Verification', () {
    test('Zero/Empty buffer returns zero RMS amplitude', () {
      final emptyBuffer = Uint8List(0);
      expect(RmsCalculator.calculateNormalizedRms(emptyBuffer), 0.0);

      final singleByte = Uint8List(1);
      expect(RmsCalculator.calculateNormalizedRms(singleByte), 0.0);
    });

    test('Digital silence (all zeros) returns zero RMS amplitude', () {
      final silenceBuffer = Uint8List(16000 * 2); // 1 second of 16-bit zeros
      final rms = RmsCalculator.calculateNormalizedRms(silenceBuffer);
      expect(rms, 0.0);
      expect(RmsCalculator.isVoiceDetected(rms), isFalse);
    });

    test('Full-scale alternating square wave approaches maximum amplitude', () {
      const sampleCount = 1000;
      final bytes = Uint8List(sampleCount * 2);
      final byteData = ByteData.sublistView(bytes);

      for (int i = 0; i < sampleCount; i++) {
        final val = i.isEven ? 32767 : -32768;
        byteData.setInt16(i * 2, val, Endian.little);
      }

      final rms = RmsCalculator.calculateNormalizedRms(bytes);
      expect(rms, greaterThan(0.95));
      expect(RmsCalculator.isVoiceDetected(rms), isTrue);
    });

    test('Synthetic 440Hz Sine wave produces expected non-zero RMS amplitude', () {
      const sampleRate = 16000;
      const durationMs = 100;
      final sampleCount = (sampleRate * (durationMs / 1000)).round();
      final bytes = Uint8List(sampleCount * 2);
      final byteData = ByteData.sublistView(bytes);

      // Generate 440Hz tone with 0.5 peak amplitude
      for (int i = 0; i < sampleCount; i++) {
        final sampleFloat = 0.5 * math.sin(2 * math.pi * 440 * (i / sampleRate));
        final sampleInt = (sampleFloat * 32767).round().clamp(-32768, 32767);
        byteData.setInt16(i * 2, sampleInt, Endian.little);
      }

      final rms = RmsCalculator.calculateNormalizedRms(bytes);
      expect(rms, greaterThan(0.5));
      expect(rms, lessThanOrEqualTo(1.0));
      expect(RmsCalculator.isVoiceDetected(rms), isTrue);
    });

    test('VAD Voice Activity Detection accurately thresholds silence vs speech', () {
      // 1. Ambient noise (very low amplitude ~0.01)
      final lowNoiseBytes = Uint8List(320); // 10ms
      final byteData = ByteData.sublistView(lowNoiseBytes);
      for (int i = 0; i < 160; i++) {
        byteData.setInt16(i * 2, 80, Endian.little); // low noise floor
      }
      final noiseRms = RmsCalculator.calculateNormalizedRms(lowNoiseBytes);
      expect(RmsCalculator.isVoiceDetected(noiseRms), isFalse);

      // 2. Active voice level
      final speechBytes = Uint8List(320);
      final speechData = ByteData.sublistView(speechBytes);
      for (int i = 0; i < 160; i++) {
        speechData.setInt16(i * 2, 4500, Endian.little); // moderate speech level
      }
      final speechRms = RmsCalculator.calculateNormalizedRms(speechBytes);
      expect(RmsCalculator.isVoiceDetected(speechRms), isTrue);
    });

    test('Decibels conversion maps correctly between 0.0 and 1.0', () {
      expect(RmsCalculator.calculateDecibels(0.0), -60.0);
      expect(RmsCalculator.calculateDecibels(1.0), 0.0);

      final midDb = RmsCalculator.calculateDecibels(0.5);
      expect(midDb, closeTo(-6.02, 0.1));
    });
  });
}
