import 'dart:math' as math;
import 'dart:typed_data';

/// High-performance calculator for 16-bit Mono Linear PCM Root Mean Square (RMS)
/// amplitude and Voice Activity Detection (VAD) energy thresholding.
abstract final class RmsCalculator {
  /// Default threshold for active human voice detection from normalized RMS amplitude.
  static const double defaultVoiceThreshold = 0.06;

  /// Computes the normalized RMS amplitude in the range [0.0, 1.0] from raw 16-bit little-endian PCM bytes.
  static double calculateNormalizedRms(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return 0.0;

    final byteData = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.length ~/ 2;

    if (sampleCount == 0) return 0.0;

    double sumSquares = 0.0;
    for (int i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      // Normalized to [-1.0, 1.0]
      final normalized = sample / 32768.0;
      sumSquares += normalized * normalized;
    }

    final rawRms = math.sqrt(sumSquares / sampleCount);

    if (rawRms <= 0.0001) return 0.0;

    // Normal speech has raw RMS between 0.03 and 0.35.
    // Multiplying by 2.8 maps human speech smoothly to [0.08, 1.0] while preserving silence floor.
    final scaled = (rawRms * 2.8).clamp(0.0, 1.0);
    return scaled;
  }

  /// Determines whether speech/voice activity is detected based on [normalizedRms].
  static bool isVoiceDetected(
    double normalizedRms, {
    double threshold = defaultVoiceThreshold,
  }) {
    return normalizedRms >= threshold;
  }

  /// Converts normalized RMS [0.0, 1.0] to a decibel (dBFS) representation [-60.0, 0.0].
  static double calculateDecibels(double normalizedRms) {
    if (normalizedRms <= 0.0001) return -60.0;
    final db = 20 * math.log(normalizedRms) / math.ln10;
    return db.clamp(-60.0, 0.0);
  }
}
