import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/transcript_segment.dart';

/// Interactive segmented transcript tile supporting tap-to-seek,
/// real-time playback highlight, and speaker renaming trigger.
class TranscriptSegmentTile extends StatelessWidget {
  const TranscriptSegmentTile({
    super.key,
    required this.segment,
    required this.isActive,
    required this.onTap,
    required this.onRenameSpeaker,
  });

  final TranscriptSegment segment;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<String> onRenameSpeaker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.accent.withValues(alpha: isDark ? 0.16 : 0.08)
            : (isDark
                ? AppColors.surfaceContainerDark
                : AppColors.surfaceLight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppColors.accent
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Speaker Name Chip & Time Range Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speaker Chip with Edit Action
                    InkWell(
                      onTap: () => onRenameSpeaker(segment.speakerId),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_rounded,
                              size: 13,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              segment.speakerId,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_rounded,
                              size: 11,
                              color: AppColors.accent.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Timestamp Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceContainerLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        segment.formattedTimeRange,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'Inter',
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Spoken Transcript Text
                Text(
                  segment.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
