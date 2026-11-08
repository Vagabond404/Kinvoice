import 'package:flutter/material.dart';
import '../../../../core/services/app_preferences_service.dart';
import '../../../../core/services/recording_notification_service.dart';
import '../../../../core/theme/app_colors.dart';

/// 3-step First-Launch Onboarding & Privacy Agreement screen for Kinvoice:
/// 1. Welcome to Kinvoice & Core Value Proposition ("Your Ambient Voice Second Brain").
/// 2. 100% On-Device Privacy Guarantee (Voice data, transcripts, and AI embeddings NEVER leave the phone).
/// 3. Permissions Request Step (`RECORD_AUDIO`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE_MICROPHONE`).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onCompleted,
    this.preferencesService,
    this.notificationService,
  });

  final VoidCallback onCompleted;
  final AppPreferencesService? preferencesService;
  final RecordingNotificationService? notificationService;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  late final AppPreferencesService _prefs;
  late final RecordingNotificationService _notifService;

  int _currentPage = 0;
  bool _privacyAccepted = true;
  bool _isRequestingPermissions = false;

  @override
  void initState() {
    super.initState();
    _prefs = widget.preferencesService ?? AppPreferencesService.instance;
    _notifService =
        widget.notificationService ?? RecordingNotificationService.instance;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    if (_currentPage < 2) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    if (_isRequestingPermissions) return;
    setState(() {
      _isRequestingPermissions = true;
    });

    await _notifService.requestAllPermissions();
    await _prefs.setHasCompletedOnboarding(true);

    if (!mounted) return;
    setState(() {
      _isRequestingPermissions = false;
    });
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Top Progress Indicator Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(3, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 8),
                        height: 6,
                        width: isActive ? 28 : 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.accent
                              : AppColors.accent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  if (_currentPage < 2)
                    TextButton(
                      onPressed: () {
                        _pageController.animateToPage(
                          2,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),

            // 3 Onboarding Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildWelcomePage(theme, isDark),
                  _buildPrivacyGuaranteePage(theme, isDark),
                  _buildPermissionsPage(theme, isDark),
                ],
              ),
            ),

            // Bottom Action Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: (_currentPage == 1 && !_privacyAccepted) ||
                          _isRequestingPermissions
                      ? null
                      : _nextStep,
                  child: _isRequestingPermissions
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          _currentPage == 0
                              ? 'Continue'
                              : (_currentPage == 1
                                  ? 'I Agree & Continue'
                                  : 'Grant Permissions & Start Kinvoice'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF4F46E5),
                  Color(0xFF9333EA),
                  Color(0xFFEC4899),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 58,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to Kinvoice',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Your Ambient Voice Second Brain',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Capture every meeting, spontaneous idea, and bilingual conversation effortlessly with studio-grade 16kHz audio, real-time Silero VAD, and instant semantic memory search.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.bolt_rounded,
            title: '24/7 Ambient & Studio Capture',
            subtitle:
                'Hands-free voice activity detection or 1-tap studio recording.',
          ),
          const SizedBox(height: 12),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.translate_rounded,
            title: 'Multilingual On-Device AI',
            subtitle:
                'Supports English, French, and Khmer with speaker diarization.',
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyGuaranteePage(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.success,
              size: 50,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '100% On-Device Privacy Guarantee',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'Your voice data, transcripts, speaker signatures, and AI vector embeddings NEVER leave your phone.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.memory_rounded,
            title: 'Zero Cloud Uploads',
            subtitle:
                'All ONNX neural models run locally on your smartphone CPU/NPU.',
          ),
          const SizedBox(height: 12),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.folder_special_rounded,
            title: 'Transparent Local Vault',
            subtitle:
                'Your audio files are stored in your device Documents/Kinvoice folder under your full control.',
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: _privacyAccepted,
            onChanged: (val) {
              setState(() {
                _privacyAccepted = val ?? false;
              });
            },
            activeColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'I understand that my recordings are stored locally on my device and I am responsible for backing them up.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsPage(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic_external_on_rounded,
              color: AppColors.accent,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Essential System Permissions',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'To capture crystal-clear audio and keep recording reliably when your screen is locked, Kinvoice requests the following permissions:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.mic_rounded,
            title: 'Microphone Access (RECORD_AUDIO)',
            subtitle:
                'Required to capture 16kHz studio voice notes and ambient speech.',
          ),
          const SizedBox(height: 12),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.notifications_active_rounded,
            title: 'Ongoing Notification (POST_NOTIFICATIONS)',
            subtitle:
                'Displays the live HH:MM:SS timer with Pause/Resume & Stop controls on your lockscreen.',
          ),
          const SizedBox(height: 12),
          _buildFeatureTile(
            theme,
            isDark,
            icon: Icons.graphic_eq_rounded,
            title: 'Background Audio Service (FOREGROUND_SERVICE_MICROPHONE)',
            subtitle:
                'Prevents Android from interrupting long meetings when you switch apps.',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTile(
    ThemeData theme,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceContainerDark
            : AppColors.surfaceContainerLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
