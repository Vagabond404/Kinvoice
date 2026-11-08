import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/recording_summary.dart';

/// Card displaying audio recording metadata, mini waveform, speaker badges, and playback controls.
class RecordingFeedItem extends StatelessWidget {
  const RecordingFeedItem({
    super.key,
    required this.recording,
    required this.isPlaying,
    required this.onFavoriteToggle,
    required this.onPlayToggle,
    this.onTap,
  });

  final RecordingSummary recording;
  final bool isPlaying;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onPlayToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Metadata Row: Timestamp, Speakers Badge, Favorite Star
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        recording.formattedTime,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${recording.speakers.length} ${recording.speakers.length == 1 ? 'Speaker' : 'Speakers'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      recording.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: recording.isFavorite
                          ? AppColors.warning
                          : (isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight),
                    ),
                    onPressed: onFavoriteToggle,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                recording.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Transcript Snippet
              Text(
                recording.transcriptSnippet,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),

              // Waveform and Duration Preview
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceContainerDark
                      : AppColors.surfaceContainerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // Mini Play Button
                    GestureDetector(
                      onTap: onPlayToggle,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? AppColors.accent
                              : (isDark
                                  ? AppColors.surfaceDark
                                  : AppColors.surfaceLight),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                          color: isPlaying ? Colors.white : AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Custom Painted Waveform
                    Expanded(
                      child: CustomPaint(
                        size: const Size(double.infinity, 24),
                        painter: MiniWaveformPainter(
                          seed: recording.id.hashCode,
                          barColor: isPlaying
                              ? AppColors.accent
                              : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                          activeColor: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Duration mm:ss
                    Text(
                      recording.formattedDuration,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Tags Row
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: recording.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDark
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Canvas CustomPainter rendering a static audio waveform preview with vertical rounded bars.
class MiniWaveformPainter extends CustomPainter {
  const MiniWaveformPainter({
    required this.seed,
    required this.barColor,
    required this.activeColor,
  });

  final int seed;
  final Color barColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    const int barCount = 28;
    const double barWidth = 2.5;
    final double spacing = (size.width - (barCount * barWidth)) / (barCount - 1);

    final paint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      // Deterministic pseudo-random bar height based on seed and index
      final int value = ((seed * (i + 1) * 31) % 100).abs();
      final double normalized = 0.2 + (value / 100.0) * 0.8;
      final double barHeight = size.height * normalized;
      final double top = (size.height - barHeight) / 2;
      final double left = i * (barWidth + spacing);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        const Radius.circular(1.5),
      );

      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MiniWaveformPainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.barColor != barColor ||
        oldDelegate.activeColor != activeColor;
  }
}
