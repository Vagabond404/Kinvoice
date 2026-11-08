import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/audio/audio_recorder_service.dart';
import '../../../../core/database/recording_repository.dart';
import '../../../../core/services/app_preferences_service.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/live_waveform_painter.dart';
import '../widgets/save_recording_dialog.dart';

/// Full-screen dark mode studio recording modal with live waveform visualizer,
/// digital timer, active speaker/VAD indicator, and recording controls.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    this.recorderService,
    this.storageService,
    this.repository,
    this.preferencesService,
    this.initialTitle = 'New Recording',
  });

  final AudioRecorderService? recorderService;
  final RecordingStorageService? storageService;
  final RecordingRepository? repository;
  final AppPreferencesService? preferencesService;
  final String initialTitle;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with SingleTickerProviderStateMixin {
  late final AudioRecorderService _recorderService;
  late final AnimationController _waveAnimationController;
  late final TextEditingController _titleController;

  StreamSubscription<double>? _amplitudeSub;
  StreamSubscription<bool>? _voiceSub;
  StreamSubscription<Duration>? _durationSub;

  double _currentAmplitude = 0.05;
  double _smoothedAmplitude = 0.05;
  bool _isVoiceDetected = false;
  Duration _elapsed = Duration.zero;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _recorderService = widget.recorderService ?? AudioRecorderService();
    _titleController = TextEditingController(text: widget.initialTitle);

    // Continuous wave motion controller
    _waveAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _waveAnimationController.addListener(() {
      // Smooth amplitude dampening for fluid animations
      setState(() {
        _smoothedAmplitude =
            _smoothedAmplitude + (_currentAmplitude - _smoothedAmplitude) * 0.15;
      });
    });

    _startRecordingSession();
  }

  Future<void> _startRecordingSession() async {
    // Listen to live metrics
    _amplitudeSub = _recorderService.amplitudeStream.listen((rms) {
      if (mounted) {
        _currentAmplitude = rms;
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
      }
    });

    if (!_recorderService.isRecording) {
      await _recorderService.startRecording();
    }
  }

  @override
  void dispose() {
    _waveAnimationController.dispose();
    _titleController.dispose();
    _amplitudeSub?.cancel();
    _voiceSub?.cancel();
    _durationSub?.cancel();
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
    setState(() {});
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
