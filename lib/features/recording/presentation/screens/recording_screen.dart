import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/audio/audio_recorder_service.dart';
import '../../../../core/database/recording_repository.dart';
import '../../../../core/services/app_preferences_service.dart';
import '../../../../core/services/recording_notification_service.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/live_waveform_painter.dart';
import '../widgets/save_recording_dialog.dart';

/// Full-screen dark mode studio recording modal with live waveform visualizer,
/// digital timer, active speaker/VAD indicator, interactive Android ongoing
/// notification synchronization, crash recovery journal, and edge-case hardening.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    this.recorderService,
    this.storageService,
    this.repository,
    this.preferencesService,
    this.notificationService,
    this.initialTitle = 'New Recording',
  });

  final AudioRecorderService? recorderService;
  final RecordingStorageService? storageService;
  final RecordingRepository? repository;
  final AppPreferencesService? preferencesService;
  final RecordingNotificationService? notificationService;
  final String initialTitle;

  @override
  State<RecordingScreen> createState() => RecordingScreenState();
}

class RecordingScreenState extends State<RecordingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AudioRecorderService _recorderService;
  late final RecordingNotificationService _notificationService;
  late final AnimationController _waveAnimationController;
  late final TextEditingController _titleController;

  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<bool>? _voiceSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<NotificationRecordingAction>? _notifActionSub;

  double _currentAmplitude = 0.05;
  double _smoothedAmplitude = 0.05;
  bool _isVoiceDetected = false;
  Duration _elapsed = Duration.zero;
  int _lastNotifiedSecond = -1;
  bool _isSaving = false;
  bool _permissionDenied = false;
  bool _storageExhausted = false;
  DateTime _sessionStartedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorderService = widget.recorderService ?? AudioRecorderService();
    _notificationService =
        widget.notificationService ?? RecordingNotificationService.instance;
    _titleController = TextEditingController(text: widget.initialTitle);

    // Continuous wave motion controller
    _waveAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _waveAnimationController.addListener(() {
      if (!mounted) return;
      setState(() {
        _smoothedAmplitude =
            _smoothedAmplitude + (_currentAmplitude - _smoothedAmplitude) * 0.15;
      });
    });

    _notifActionSub = _notificationService.actionStream.listen((action) {
      if (!mounted) return;
      if (action == NotificationRecordingAction.pauseResume) {
        _togglePauseResume();
      } else if (action == NotificationRecordingAction.stopAndSave) {
        _finishAndSave();
      }
    });

    _startRecordingSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Keep ongoing notification synced; if OS signals audio interruption or call,
    // synchronize state and flush recovery journal.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _flushRecoveryJournal();
    } else if (state == AppLifecycleState.resumed) {
      _checkPendingNotificationActions();
    }
  }

  /// Auto-pauses recording and preserves the current audio buffer when an incoming
  /// phone call, alarm, or Bluetooth disconnection interrupts audio focus.
  Future<void> handleAudioInterruption() async {
    if (_recorderService.isRecording && !_recorderService.isPaused) {
      await _recorderService.pauseRecording();
      await _notificationService.updateRecordingNotification(
        title: _titleController.text.trim().isEmpty
            ? 'Voice Note'
            : _titleController.text.trim(),
        elapsed: _elapsed,
        isPaused: true,
      );
      await _flushRecoveryJournal();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _checkPendingNotificationActions() async {
    final pendingAction =
        await _notificationService.consumePendingNotificationAction();
    if (!mounted || pendingAction == null) return;
    if (pendingAction == NotificationRecordingAction.pauseResume) {
      await _togglePauseResume();
    } else if (pendingAction == NotificationRecordingAction.stopAndSave) {
      await _finishAndSave();
    }
  }

  Future<void> _startRecordingSession() async {
    _sessionStartedAt = DateTime.now();

    // 1. Storage Exhaustion Guard
    final hasSpace = await _notificationService.hasSufficientStorage();
    if (!hasSpace) {
      if (mounted) {
        setState(() {
          _storageExhausted = true;
        });
        _showStorageExhaustedDialog();
      }
      return;
    }

    // Listen to live metrics
    _amplitudeSub = _recorderService.amplitudeStream.listen((rms) {
      if (mounted) {
        _currentAmplitude = rms.isNaN || rms.isInfinite ? 0.05 : rms;
      }
    });

    _voiceSub = _recorderService.voiceDetectedStream.listen((voice) {
      if (mounted) {
        setState(() {
          _isVoiceDetected = voice;
        });
      }
    });

    _durationSub = _recorderService.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _elapsed = duration;
        });
        final sec = duration.inSeconds;
        if (sec != _lastNotifiedSecond) {
          _lastNotifiedSecond = sec;
          _notificationService.updateRecordingNotification(
            title: _titleController.text.trim().isEmpty
                ? 'Voice Note'
                : _titleController.text.trim(),
            elapsed: duration,
            isPaused: _recorderService.isPaused,
          );
          if (sec > 0 && sec % 5 == 0) {
            _flushRecoveryJournal();
          }
        }
      }
    });

    if (!_recorderService.isRecording) {
      final startResult = await _recorderService.startRecording();
      if (!mounted) return;

      startResult.fold(
        onSuccess: (_) {
          _notificationService.startRecordingNotification(
            title: _titleController.text.trim().isEmpty
                ? 'Voice Note'
                : _titleController.text.trim(),
          );
          _flushRecoveryJournal();
        },
        onError: (failure) {
          if (failure.message.toLowerCase().contains('permission')) {
            setState(() {
              _permissionDenied = true;
            });
            _showPermissionDeniedDialog();
          }
        },
      );
    } else {
      await _notificationService.startRecordingNotification(
        title: _titleController.text.trim(),
      );
    }
  }

  Future<void> _flushRecoveryJournal() async {
    final tempPath = _recorderService.activeOutputPath;
    if (tempPath == null || tempPath.isEmpty) return;
    await _notificationService.writeRecoveryJournal(
      CrashRecoveryJournalEntry(
        tempFilePath: tempPath,
        title: _titleController.text.trim().isEmpty
            ? 'Recovered Voice Note'
            : _titleController.text.trim(),
        category: 'General',
        startedAtMs: _sessionStartedAt.millisecondsSinceEpoch,
        elapsedSeconds: _elapsed.inSeconds,
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.mic_off_rounded, color: AppColors.recording),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Microphone Permission Required',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Kinvoice requires microphone access to capture and transcribe your voice notes locally on your device. Please enable Microphone permission in App Settings.',
          style: TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _notificationService.openAppSettings();
            },
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Open App Settings'),
          ),
        ],
      ),
    );
  }

  void _showStorageExhaustedDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.disc_full_rounded, color: AppColors.warning),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Low Device Storage',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your device has less than 50 MB of free storage remaining. Please free up disk space before starting a new long recording.',
          style: TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waveAnimationController.dispose();
    _titleController.dispose();
    _amplitudeSub?.cancel();
    _voiceSub?.cancel();
    _durationSub?.cancel();
    _notifActionSub?.cancel();
    if (widget.recorderService == null) {
      _recorderService.dispose();
    }
    super.dispose();
  }

  String _formatTimer(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _togglePauseResume() async {
    if (_recorderService.isPaused) {
      await _recorderService.resumeRecording();
    } else {
      await _recorderService.pauseRecording();
    }
    await _notificationService.updateRecordingNotification(
      title: _titleController.text.trim().isEmpty
          ? 'Voice Note'
          : _titleController.text.trim(),
      elapsed: _elapsed,
      isPaused: _recorderService.isPaused,
    );
    await _flushRecoveryJournal();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmCancel() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Discard Recording?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This action cannot be undone. All captured audio will be deleted.',
          style: TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Recording'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.recording,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (shouldCancel == true && mounted) {
      await _recorderService.cancelRecording();
      await _notificationService.stopRecordingNotification();
      await _notificationService.clearRecoveryJournal();
      if (mounted) {
        Navigator.pop(context, null);
      }
    }
  }

  Future<void> _finishAndSave() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    final capturedDuration = _elapsed > Duration.zero
        ? _elapsed
        : _recorderService.currentDuration;
    final result = await _recorderService.stopRecording();
    await _notificationService.stopRecordingNotification();
    await _notificationService.clearRecoveryJournal();

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    await result.fold(
      onSuccess: (tempFilePath) async {
        final dialogResult = await SaveRecordingDialog.show(
          context,
          tempFilePath: tempFilePath,
          duration: capturedDuration,
          initialTitle: _titleController.text.trim(),
          storageService: widget.storageService,
          repository: widget.repository,
          preferencesService: widget.preferencesService,
        );

        if (!mounted) return;
        if (dialogResult != null && dialogResult.isSaved) {
          Navigator.pop(context, dialogResult.savedFilePath);
        } else {
          Navigator.pop(context, null);
        }
      },
      onError: (failure) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: AppColors.recording,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPaused = _recorderService.isPaused;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _confirmCancel,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 26,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '16 kHz Mono PCM • WAV',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48), // Balance close button spacing
                ],
              ),
            ),

            // Permission Denied / Storage Exhausted Warning Banner (if applicable)
            if (_permissionDenied || _storageExhausted)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.recording.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.recording),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _permissionDenied
                            ? Icons.mic_off_rounded
                            : Icons.disc_full_rounded,
                        color: AppColors.recording,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _permissionDenied
                              ? 'Microphone permission denied. Tap Settings to enable.'
                              : 'Low storage space (<50 MB available).',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_permissionDenied)
                        TextButton(
                          onPressed: _notificationService.openAppSettings,
                          child: const Text('Settings'),
                        ),
                    ],
                  ),
                ),
              ),

            // Recording Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: TextField(
                controller: _titleController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Recording Title...',
                  hintStyle: TextStyle(color: AppColors.textSecondaryDark),
                ),
              ),
            ),

            // Speaker / VAD Diarization Indicator Badge
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _isVoiceDetected
                      ? AppColors.success.withValues(alpha: 0.16)
                      : AppColors.surfaceContainerDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isVoiceDetected
                        ? AppColors.success
                        : AppColors.borderDark,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isVoiceDetected
                            ? AppColors.success
                            : AppColors.textSecondaryDark,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isVoiceDetected
                          ? 'Active Voice Detected'
                          : 'Ambient Silence',
                      style: TextStyle(
                        color: _isVoiceDetected
                            ? AppColors.success
                            : AppColors.textSecondaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Center Waveform Visualizer Stage
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Center(
                  child: SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: LiveWaveformPainter(
                        phase: _waveAnimationController.value * 2 * math.pi,
                        amplitude: isPaused ? 0.02 : _smoothedAmplitude,
                        isVoiceDetected: !isPaused && _isVoiceDetected,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Large Digital Timer HH:MM:SS
            Text(
              _formatTimer(_elapsed),
              style: const TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPaused
                  ? 'PAUSED'
                  : (_isVoiceDetected
                      ? 'TRANSCRIBING STREAM'
                      : 'LISTENING...'),
              style: TextStyle(
                color: isPaused
                    ? AppColors.warning
                    : (_isVoiceDetected
                        ? AppColors.success
                        : AppColors.textSecondaryDark),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: 20),

            // Bottom Controls Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Cancel / Trash Button
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _confirmCancel,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceContainerDark,
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.recording,
                          size: 26,
                        ),
                      ),
                    ),
                  ),

                  // Pause / Resume Button
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _togglePauseResume,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF374151),
                              Color(0xFF1F2937),
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.borderDark,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          isPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                  ),

                  // Finish / Save Button
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: _isSaving ? null : _finishAndSave,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _isSaving
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
