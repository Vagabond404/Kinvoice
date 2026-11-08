import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Dynamic live waveform painter rendering fluid multi-harmonic sine waves
/// and reactive equalizer bars responding smoothly to RMS amplitude.
class LiveWaveformPainter extends CustomPainter {
  const LiveWaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.isVoiceDetected,
    this.primaryColor = AppColors.accent,
    this.voiceActiveColor = AppColors.success,
  });

  /// Continuous phase offset driven by an AnimationController (0.0 to 2*pi).
  final double phase;

  /// Normalized audio RMS amplitude (0.0 to 1.0).
  final double amplitude;

  /// Whether active voice is detected via VAD.
  final bool isVoiceDetected;

  final Color primaryColor;
  final Color voiceActiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final activeColor = isVoiceDetected ? voiceActiveColor : primaryColor;
    final centerY = size.height / 2;

    // Draw background ambient glow
    final glowRadius = (size.height * 0.45) * (0.4 + amplitude * 0.6);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          activeColor.withValues(alpha: 0.18 + amplitude * 0.22),
          activeColor.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(center: Offset(size.width / 2, centerY), radius: glowRadius),
      );
    canvas.drawCircle(Offset(size.width / 2, centerY), glowRadius, glowPaint);

    // 1. Draw 32 Central Equalizer Bars
    _drawEqualizerBars(canvas, size, activeColor);

    // 2. Draw Multi-Layer Fluid Harmonic Sine Waves
    _drawHarmonicWave(
      canvas: canvas,
      size: size,
      phaseOffset: phase,
      frequency: 2.2,
      amplitudeMultiplier: 0.85,
      color: activeColor.withValues(alpha: 0.75),
      strokeWidth: 2.5,
    );

    _drawHarmonicWave(
      canvas: canvas,
      size: size,
      phaseOffset: phase + math.pi / 2,
      frequency: 3.4,
      amplitudeMultiplier: 0.55,
      color: activeColor.withValues(alpha: 0.4),
      strokeWidth: 1.8,
    );

    _drawHarmonicWave(
      canvas: canvas,
      size: size,
      phaseOffset: phase + math.pi,
      frequency: 1.6,
      amplitudeMultiplier: 0.35,
      color: activeColor.withValues(alpha: 0.25),
      strokeWidth: 1.4,
    );
  }

  void _drawEqualizerBars(Canvas canvas, Size size, Color activeColor) {
    const int barCount = 34;
    const double barWidth = 3.0;
    final double spacing = (size.width - (barCount * barWidth)) / (barCount - 1);
    final double centerY = size.height / 2;

    final barPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.6 + amplitude * 0.4)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      // Gaussian distribution envelope tapering towards screen edges
      final double normX = (i - (barCount / 2)) / (barCount / 2);
      final double envelope = math.exp(-normX * normX * 2.2);

      // Procedural harmonic heights
      final double oscillation =
          (math.sin(i * 0.6 + phase * 2.0) + 1.0) * 0.5;
      final double dynamicHeight =
          (6.0 + (size.height * 0.42 * amplitude * envelope * oscillation))
              .clamp(4.0, size.height * 0.85);

      final double left = i * (barWidth + spacing);
      final double top = centerY - (dynamicHeight / 2);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, dynamicHeight),
        const Radius.circular(2.0),
      );

      canvas.drawRRect(rrect, barPaint);
    }
  }

  void _drawHarmonicWave({
    required Canvas canvas,
    required Size size,
    required double phaseOffset,
    required double frequency,
    required double amplitudeMultiplier,
    required Color color,
    required double strokeWidth,
  }) {
    final wavePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final centerY = size.height / 2;
    final maxWaveHeight = (size.height * 0.38) * (0.15 + amplitude * 0.85);

    path.moveTo(0, centerY);

    for (double x = 0; x <= size.width; x += 4) {
      final double progress = x / size.width;
      // Windowing function (Hanning window) to anchor edges at 0
      final double window = 0.5 * (1 - math.cos(2 * math.pi * progress));

      final double y = centerY +
          math.sin((progress * frequency * 2 * math.pi) + phaseOffset) *
              maxWaveHeight *
              amplitudeMultiplier *
              window;

      path.lineTo(x, y);
    }

    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant LiveWaveformPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.isVoiceDetected != isVoiceDetected ||
        oldDelegate.primaryColor != primaryColor;
  }
}
