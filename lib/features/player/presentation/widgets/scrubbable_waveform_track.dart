import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Scrubbable interactive audio waveform track supporting drag-to-seek and tap-to-seek.
class ScrubbableWaveformTrack extends StatefulWidget {
  const ScrubbableWaveformTrack({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    required this.onSeek,
    this.seed = 42,
  });

  final Duration currentPosition;
  final Duration totalDuration;
  final ValueChanged<Duration> onSeek;
  final int seed;

  @override
  State<ScrubbableWaveformTrack> createState() =>
      _ScrubbableWaveformTrackState();
}

class _ScrubbableWaveformTrackState extends State<ScrubbableWaveformTrack> {
  double? _dragFraction;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleSeek(Offset localPosition, double totalWidth) {
    final fraction = (localPosition.dx / totalWidth).clamp(0.0, 1.0);
    final totalMs = widget.totalDuration.inMilliseconds;
    if (totalMs > 0) {
      final targetMs = (totalMs * fraction).round();
      widget.onSeek(Duration(milliseconds: targetMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final totalMs = widget.totalDuration.inMilliseconds;
    final currentMs = widget.currentPosition.inMilliseconds;
    final progressFraction = totalMs > 0
        ? (_dragFraction ?? (currentMs / totalMs).clamp(0.0, 1.0))
        : 0.0;

    return Column(
      children: [
        // Waveform Container
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _dragFraction = (details.localPosition.dx / trackWidth).clamp(
                    0.0,
                    1.0,
                  );
                });
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _dragFraction = (details.localPosition.dx / trackWidth).clamp(
                    0.0,
                    1.0,
                  );
                });
              },
              onHorizontalDragEnd: (details) {
                if (_dragFraction != null) {
                  _handleSeek(
                    Offset(_dragFraction! * trackWidth, 0),
                    trackWidth,
                  );
                  setState(() {
                    _dragFraction = null;
                  });
                }
              },
              onTapDown: (details) {
                _handleSeek(details.localPosition, trackWidth);
              },
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceContainerDark
                      : AppColors.surfaceContainerLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
                child: CustomPaint(
                  size: Size(trackWidth, 40),
                  painter: _ScrubbableWaveformPainter(
                    progressFraction: progressFraction,
                    seed: widget.seed,
                    activeColor: AppColors.accent,
                    inactiveColor: isDark
                        ? AppColors.textSecondaryDark.withValues(alpha: 0.35)
                        : AppColors.textSecondaryLight.withValues(alpha: 0.35),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),

        // Duration Timers Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(widget.currentPosition),
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
            Text(
              _formatDuration(widget.totalDuration),
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScrubbableWaveformPainter extends CustomPainter {
  const _ScrubbableWaveformPainter({
    required this.progressFraction,
    required this.seed,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progressFraction;
  final int seed;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const int barCount = 48;
    const double barWidth = 3.0;
    final double spacing = (size.width - (barCount * barWidth)) / (barCount - 1);
    final double centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      final double barCenterFraction = (i + 0.5) / barCount;
      final bool isPlayed = barCenterFraction <= progressFraction;

      final paint = Paint()
        ..color = isPlayed ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      // Deterministic bar height from seed and index
      final int value = ((seed * (i + 7) * 43) % 100).abs();
      final double normalized = 0.2 + (value / 100.0) * 0.8;
      final double barHeight = size.height * normalized;
      final double top = centerY - (barHeight / 2);
      final double left = i * (barWidth + spacing);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(1.5),
      );

      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubbableWaveformPainter oldDelegate) {
    return oldDelegate.progressFraction != progressFraction ||
        oldDelegate.seed != seed ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
