import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/database/recording_repository.dart';
import '../../../../core/ml/vad/ambient_monitoring_service.dart';
import '../../../../core/ml/vad/battery_optimization_policy.dart';
import '../../../../core/services/app_preferences_service.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'model_hub_screen.dart';

/// The Settings & Model Hub screen of Kinvoice.
/// Allows configuration of storage paths, audio formats, transcription rules,
/// Silero VAD microphone sensitivity, AI models, and cache clearing.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.ambientService,
    this.preferencesService,
    this.storageService,
    this.repository,
  });

  final AmbientMonitoringService? ambientService;
  final AppPreferencesService? preferencesService;
  final RecordingStorageService? storageService;
  final RecordingRepository? repository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AmbientMonitoringService _ambientService;
  late final AppPreferencesService _prefs;
  late final RecordingStorageService _storageService;
  late final RecordingRepository _repository;

  StreamSubscription<bool>? _stateSub;
  StreamSubscription<dynamic>? _metricsSub;

  bool _ambientListening = false;
  AmbientPowerMode _powerMode = AmbientPowerMode.active;
  String _storagePath = '/storage/emulated/0/Documents/Kinvoice/Recordings';

  static const Map<String, String> _languageOptions = {
    'en': 'English',
    'km': 'Khmer',
    'fr': 'French',
    'auto': 'Auto-detect',
  };

  @override
  void initState() {
    super.initState();
    _ambientService = widget.ambientService ?? AmbientMonitoringService();
    _prefs = widget.preferencesService ?? AppPreferencesService.instance;
    _storageService = widget.storageService ?? RecordingStorageService.instance;
    _repository = widget.repository ?? RecordingRepository();

    _ambientListening = _ambientService.isAmbientModeEnabled;
    _powerMode = _ambientService.currentPowerMode;

    _prefs.init();
    _resolveStoragePath();

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

  Future<void> _resolveStoragePath() async {
    try {
      final path = await _storageService.getRecordingsDirectoryPath();
      if (mounted && path.isNotEmpty) {
        setState(() {
          _storagePath = path;
        });
      }
    } catch (_) {}
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

  Future<void> _copyStoragePath() async {
    await Clipboard.setData(ClipboardData(text: _storagePath));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Storage path copied: $_storagePath'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmClearAllRecordings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Recordings & Cache?'),
        content: const Text(
          'This will permanently delete all local voice recordings, transcripts, and vector search indexes from your device. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.recording,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storageService.clearAllRecordingsAndCache();
      await _repository.clearAllRecordings();

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All recordings, transcripts, and cache cleared.'),
          backgroundColor: AppColors.recording,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _prefs,
          builder: (context, _) {
            final selectedFormat = _prefs.audioFormat;
            final autoTranscribe = _prefs.autoTranscribeOnSave;
            final primaryLanguage = _prefs.primaryLanguage;
            final wordTimestamps = _prefs.wordLevelTimestamps;
            final vadSensitivity = _prefs.vadSensitivity;
            final vadThreshold = _prefs.sileroVadThreshold;
            final vadLabel = _prefs.vadSensitivityLabel;
            final batteryThrottle = _prefs.lowBatteryAutoThrottle;
            final themeModeCode = _prefs.themeModeCode;

            return CustomScrollView(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.mic_external_on_rounded,
                                          size: 20,
                                          color: AppColors.accent,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Microphone Sensitivity',
                                          style: theme.textTheme.bodyLarge,
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$vadLabel (Threshold ${vadThreshold.toStringAsFixed(2)})',
                                        style: const TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: vadSensitivity,
                                  min: 0.0,
                                  max: 1.0,
                                  divisions: 2,
                                  label: vadLabel,
                                  activeColor: AppColors.accent,
                                  onChanged: (val) {
                                    _prefs.setVadSensitivity(val);
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Low',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                      Text(
                                        'Medium',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                      Text(
                                        'High',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          SwitchListTile(
                            value: batteryThrottle,
                            onChanged: (val) {
                              _prefs.setLowBatteryAutoThrottle(val);
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
                          const ListTile(
                            leading: Icon(
                              Icons.psychology_rounded,
                              color: AppColors.accent,
                            ),
                            title: Text('Silero VAD v5 (ONNX)'),
                            subtitle:
                                Text('2 MB • 32ms Frame Slicing • Active'),
                            trailing: Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          const ListTile(
                            leading: Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.accent,
                            ),
                            title: Text('Moonshine Base (4-bit ONNX)'),
                            subtitle:
                                Text('38 MB • ⚡ 5x Real-Time • Ready'),
                            trailing: Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(Icons.language_rounded),
                            title: const Text('Meta MMS Khmer 🇰🇭'),
                            subtitle:
                                const Text('42 MB • Available for download'),
                            trailing: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ModelHubScreen(),
                                  ),
                                );
                              },
                              child: const Text('Get'),
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(
                              Icons.hub_rounded,
                              color: AppColors.accent,
                            ),
                            title: const Text('Manage Models & BYOK Keys'),
                            subtitle: const Text(
                              'Download weights, configure Groq/Ollama/OpenAI, and export backup',
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                            ),
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

                // Section: Storage Settings
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'Storage Settings',
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
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.folder_special_rounded,
                                      color: AppColors.accent,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Recording Storage Location',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                OutlinedButton.icon(
                                  onPressed: _copyStoragePath,
                                  icon: const Icon(Icons.copy_rounded, size: 16),
                                  label: const Text('Copy Path'),
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.surfaceContainerDark
                                    : AppColors.surfaceContainerLight,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? AppColors.borderDark
                                      : AppColors.borderLight,
                                ),
                              ),
                              child: SelectableText(
                                _storagePath,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Section: Audio Recording Format
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'Audio Recording Format',
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
                      child: RadioGroup<AudioRecordingFormat>(
                        groupValue: selectedFormat,
                        onChanged: (val) {
                          if (val != null) {
                            _prefs.setAudioFormat(val);
                          }
                        },
                        child: const Column(
                          children: [
                            RadioListTile<AudioRecordingFormat>(
                              value: AudioRecordingFormat.standardM4a,
                              activeColor: AppColors.accent,
                              title: Text(
                                'Standard Voice (AAC / M4A)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Lightweight compressed audio (~1MB/min)',
                              ),
                            ),
                            Divider(indent: 16, endIndent: 16),
                            RadioListTile<AudioRecordingFormat>(
                              value: AudioRecordingFormat.proWav,
                              activeColor: AppColors.accent,
                              title: Text(
                                'Pro Audio Studio (PCM WAV 16kHz, 16-bit Mono)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Uncompressed studio stream for maximum AI accuracy',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Section: Transcription Engine & Language
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'Transcription Engine & Language',
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
                            value: autoTranscribe,
                            onChanged: (val) {
                              _prefs.setAutoTranscribeOnSave(val);
                            },
                            title: const Text(
                              'Auto-transcribe immediately after saving',
                            ),
                            subtitle: const Text(
                              'Automatically runs on-device ASR & speaker diarization',
                            ),
                            activeTrackColor: AppColors.accent,
                            secondary: const Icon(
                              Icons.bolt_rounded,
                              color: AppColors.accent,
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          ListTile(
                            leading: const Icon(
                              Icons.translate_rounded,
                              color: AppColors.accent,
                            ),
                            title: const Text('Primary Language'),
                            subtitle: Text(
                              _languageOptions[primaryLanguage] ?? 'English',
                            ),
                            trailing: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _languageOptions
                                        .containsKey(primaryLanguage)
                                    ? primaryLanguage
                                    : 'en',
                                items: _languageOptions.entries.map((entry) {
                                  return DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    _prefs.setPrimaryLanguage(val);
                                  }
                                },
                              ),
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          SwitchListTile(
                            value: wordTimestamps,
                            onChanged: (val) {
                              _prefs.setWordLevelTimestamps(val);
                            },
                            title: const Text('Word-level Timestamps'),
                            subtitle: const Text(
                              'Aligns individual spoken words with audio waveform',
                            ),
                            activeTrackColor: AppColors.accent,
                            secondary: const Icon(
                              Icons.timer_outlined,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Section: Theme Mode
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'Theme Mode',
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
                      child: RadioGroup<String>(
                        groupValue: themeModeCode,
                        onChanged: (val) {
                          if (val != null) {
                            _prefs.setThemeModeCode(val);
                          }
                        },
                        child: const Column(
                          children: [
                            RadioListTile<String>(
                              value: 'system',
                              activeColor: AppColors.accent,
                              title: Text(
                                'System Default',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Automatically follows Android/iOS appearance',
                              ),
                            ),
                            Divider(indent: 16, endIndent: 16),
                            RadioListTile<String>(
                              value: 'dark',
                              activeColor: AppColors.accent,
                              title: Text(
                                'Pure Dark',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'OLED studio obsidian palette (#0B0F19)',
                              ),
                            ),
                            Divider(indent: 16, endIndent: 16),
                            RadioListTile<String>(
                              value: 'light',
                              activeColor: AppColors.accent,
                              title: Text(
                                'Clean Light',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'High-contrast daylight surface (#F8FAFC)',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Section: Danger Zone
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      'Danger Zone',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.recording,
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: AppColors.recording.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppColors.recording,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Reset Local Vault',
                                    style:
                                        theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Deletes all saved audio files, transcripts, and vector embeddings from local device storage.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _confirmClearAllRecordings,
                                icon: const Icon(
                                  Icons.delete_forever_rounded,
                                  color: AppColors.recording,
                                ),
                                label: const Text(
                                  'Clear All Recordings & Cache',
                                  style: TextStyle(
                                    color: AppColors.recording,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.recording,
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
