import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Top hero card with an animated gradient border, greeting ("Capture your mind"),
/// and a pulsing record action button.
class HeroQuickRecordCard extends StatefulWidget {
  const HeroQuickRecordCard({
    super.key,
    required this.isRecording,
    required this.onRecordTap,
  });

  final bool isRecording;
  final VoidCallback onRecordTap;

  @override
  State<HeroQuickRecordCard> createState() => _HeroQuickRecordCardState();
}

class _HeroQuickRecordCardState extends State<HeroQuickRecordCard>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _borderRotationController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulsing button animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Continuous subtle rotating gradient border
    _borderRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _borderRotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _borderRotationController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: SweepGradient(
              transform: GradientRotation(
                _borderRotationController.value * 2 * 3.141592653589793,
              ),
              colors: widget.isRecording
                  ? const [
                      AppColors.recording,
                      Color(0xFFF87171),
                      AppColors.warning,
                      AppColors.recording,
                    ]
                  : const [
                      AppColors.accent,
                      Color(0xFF818CF8),
                      Color(0xFFC084FC),
                      AppColors.accent,
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: (widget.isRecording ? AppColors.recording : AppColors.accent)
                    .withValues(alpha: isDark ? 0.25 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2), // 2px border width
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1E1B4B).withValues(alpha: 0.6),
                    AppColors.surfaceDark,
                  ]
                : [
                    const Color(0xFFEEF2FF),
                    AppColors.surfaceLight,
                  ],
          ),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Studio Badge and Audio Quality Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (widget.isRecording
                            ? AppColors.recording
                            : AppColors.accent)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: widget.isRecording
                              ? AppColors.recording
                              : AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.isRecording
                            ? 'RECORDING LIVE'
                            : 'PRO AUDIO STUDIO',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: widget.isRecording
                              ? AppColors.recording
                              : AppColors.accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '48 kHz • 24-bit PCM',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Greeting & Action Area
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capture your mind',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.isRecording
                            ? 'Listening and transcribing on-device in real-time...'
                            : 'Tap record to capture thoughts, meetings, or ambient memories.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Pulsing Record Button
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: widget.onRecordTap,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: widget.isRecording
                                ? const [
                                    Color(0xFFEF4444),
                                    Color(0xFFDC2626),
                                  ]
                                : const [
                                    AppColors.accent,
                                    Color(0xFF4F46E5),
                                  ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (widget.isRecording
                                      ? AppColors.recording
                                      : AppColors.accent)
                                  .withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isRecording
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
