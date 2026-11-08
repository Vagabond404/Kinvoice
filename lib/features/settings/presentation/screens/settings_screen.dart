import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/ml/vad/ambient_monitoring_service.dart';
import '../../../../core/ml/vad/battery_optimization_policy.dart';
import '../../../../core/theme/app_colors.dart';
import 'model_hub_screen.dart';

/// The Settings & Model Hub screen of Kinvoice.
/// Allows configuration of AI models, acoustic parameters, voice profiles, and theme modes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.ambientService,
  });

  final AmbientMonitoringService? ambientService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AmbientMonitoringService _ambientService;
  StreamSubscription<bool>? _stateSub;
  StreamSubscription<dynamic>? _metricsSub;

  bool _ambientListening = false;
  bool _batteryOptimization = true;
  AmbientPowerMode _powerMode = AmbientPowerMode.active;

  @override
  void initState() {
    super.initState();
    _ambientService = widget.ambientService ?? AmbientMonitoringService();
    _ambientListening = _ambientService.isAmbientModeEnabled;
    _powerMode = _ambientService.currentPowerMode;

    _stateSub = _ambientService.ambientStateStream.listen((active) {
      if (mounted) {
        setState(() {
          _ambientListening = active;
        });
      }
    });

    _metricsSub = _ambientService.metricsStream.listen((metrics) {
      if (mounted && metrics.powerMode != _powerMode) {
        setState(() {
          _powerMode = metrics.powerMode;
        });
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _metricsSub?.cancel();
    if (widget.ambientService == null) {
      _ambientService.dispose();
    }
    super.dispose();
  }

  Future<void> _onToggleAmbient(bool value) async {
    setState(() {
      _ambientListening = value;
    });

    if (value) {
      await _ambientService.startAmbientMonitoring();
    } else {
      await _ambientService.stopAmbientMonitoring();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Ambient Voice Ear Activated (Foreground Service Running)'
              : 'Ambient Voice Ear Deactivated',
        ),
        backgroundColor: value ? AppColors.success : AppColors.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tune_rounded,
                      color: AppColors.accent,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Settings & Models',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // On-Device Privacy Badge Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: AppColors.success,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '100% On-Device Privacy',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Voice data and AI embeddings never leave this device.',
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
                  ),
                ),
              ),
            ),

            // Section: Ambient Acoustic Engine & Silero VAD
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Acoustic Engine & VAD',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _ambientListening,
                        onChanged: _onToggleAmbient,
                        title: const Text('Passive Ambient Listener'),
                        subtitle: Text(
                          _ambientListening
                              ? (_powerMode == AmbientPowerMode.sleep
                                  ? 'Sleep Mode (Silence > 30s) • Low Power'
                                  : 'Active • Background Silero VAD v5 (<0.5% battery)')
                              : 'Paused • Toggle to enable continuous hands-free capture',
                        ),
                        activeTrackColor: AppColors.accent,
                        secondary: Icon(
                          _ambientListening
                              ? Icons.hearing_rounded
                              : Icons.hearing_disabled_rounded,
                          color: _ambientListening
                              ? AppColors.accent
                              : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        value: _batteryOptimization,
                        onChanged: (val) {
                          setState(() {
                            _batteryOptimization = val;
                          });
                        },
                        title: const Text('Low Battery Auto-Throttle'),
                        subtitle: const Text(
                          'Defers transcription when battery drops below 20%',
                        ),
                        activeTrackColor: AppColors.accent,
                        secondary: const Icon(
                          Icons.battery_saver_rounded,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Section: AI Model Hub
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text(
                  'AI Model Hub',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.psychology_rounded,
                          color: AppColors.accent,
                        ),
                        title: const Text('Silero VAD v5 (ONNX)'),
                        subtitle: const Text('2 MB • 32ms Frame Slicing • Active'),
                        trailing: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.accent,
                        ),
                        title: const Text('Moonshine Base (4-bit ONNX)'),
                        subtitle: const Text('38 MB • ⚡ 5x Real-Time • Ready'),
                        trailing: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.language_rounded),
                        title: const Text('Meta MMS Khmer 🇰🇭'),
                        subtitle: const Text('42 MB • Available for download'),
                        trailing: OutlinedButton(
                          onPressed: () {},
                          child: const Text('Get'),
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.hub_rounded, color: AppColors.accent),
                        title: const Text('Manage Models & BYOK Keys'),
                        subtitle: const Text('Download weights, configure Groq/Ollama/OpenAI, and export backup'),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ModelHubScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}
