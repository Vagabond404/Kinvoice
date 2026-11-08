import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import '../services/recording_storage_service.dart';
import '../utils/failure.dart';
import '../utils/result.dart';
import 'audio_capture_isolate.dart';

/// Audio recording service orchestrating the hardware microphone stream
/// and the dedicated background processing Isolate.
class AudioRecorderService {
  AudioRecorderService({
    AudioRecorder? recorder,
    AudioCaptureIsolateController? isolateController,
  })  : _isolateController = isolateController ?? AudioCaptureIsolateController() {
    _recorder = recorder;
  }

  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();

  final AudioCaptureIsolateController _isolateController;

  StreamSubscription<Uint8List>? _microphoneStreamSub;
  StreamSubscription<AudioIsolateEvent>? _isolateEventSub;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<bool> _voiceDetectedController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  bool _isRecording = false;
  bool _isPaused = false;
  Duration _currentDuration = Duration.zero;
  String? _activeOutputPath;

  // Public Getters
  Stream<double> get amplitudeStream => _amplitudeController.stream;
  Stream<bool> get voiceDetectedStream => _voiceDetectedController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Duration get currentDuration => _currentDuration;
  String? get activeOutputPath => _activeOutputPath;

  /// Starts a new recording session at 16kHz Mono PCM.
  Future<Result<void, AudioCaptureFailure>> startRecording({
    String? customPath,
    Stream<Uint8List>? mockAudioStream,
  }) async {
    try {
      if (_isRecording) {
        return const Result.error(
          AudioCaptureFailure('Recording session is already active.'),
        );
      }

      // Check microphone permission if not using mock audio
      if (mockAudioStream == null) {
        final hasPermission = await recorder.hasPermission();
        if (!hasPermission) {
          return const Result.error(
            AudioCaptureFailure('Microphone permission was denied.'),
          );
        }
      }

      // Determine output WAV file location
      if (customPath != null) {
        _activeOutputPath = customPath;
      } else {
        final tempDir =
            await RecordingStorageService.instance.getTempRecordingDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _activeOutputPath = p.join(tempDir.path, 'temp_recording_$timestamp.wav');
      }

      // Start the background worker isolate
      await _isolateController.start();

      _isolateEventSub = _isolateController.events.listen((event) {
        if (event is IsolateMetricsEvent) {
          _amplitudeController.add(event.rms);
          _voiceDetectedController.add(event.isVoiceDetected);
          _currentDuration = event.elapsed;
          _durationController.add(event.elapsed);
        }
      });

      _isolateController.sendCommand(
        StartCaptureCommand(
          outputPath: _activeOutputPath!,
          sampleRate: 16000,
        ),
      );

      // Listen to raw PCM chunks
      final stream = mockAudioStream ??
          await recorder.startStream(
            const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
            ),
          );

      _microphoneStreamSub = stream.listen((chunk) {
        _isolateController.sendCommand(ProcessChunkCommand(chunk));
      });

      _isRecording = true;
      _isPaused = false;
      _currentDuration = Duration.zero;

      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to start audio recording: $e', e, stack),
      );
    }
  }

  /// Pauses the active recording session.
  Future<Result<void, AudioCaptureFailure>> pauseRecording() async {
    if (!_isRecording || _isPaused) {
      return const Result.error(
        AudioCaptureFailure('Cannot pause when not actively recording.'),
      );
    }

    try {
      if (_recorder != null) {
        await _recorder!.pause();
      }
      _isolateController.sendCommand(const PauseCaptureCommand());
      _isPaused = true;
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to pause audio recording: $e', e, stack),
      );
    }
  }

  /// Resumes a paused recording session.
  Future<Result<void, AudioCaptureFailure>> resumeRecording() async {
    if (!_isRecording || !_isPaused) {
      return const Result.error(
        AudioCaptureFailure('Cannot resume when not in paused state.'),
      );
    }

    try {
      if (_recorder != null) {
        await _recorder!.resume();
      }
      _isolateController.sendCommand(const ResumeCaptureCommand());
      _isPaused = false;
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to resume audio recording: $e', e, stack),
      );
    }
  }

  /// Completes recording, finalizes the WAV file, and returns the saved file path.
  Future<Result<String, AudioCaptureFailure>> stopRecording() async {
    if (!_isRecording) {
      return const Result.error(
        AudioCaptureFailure('No active recording to stop.'),
      );
    }

    try {
      await _microphoneStreamSub?.cancel();
      _microphoneStreamSub = null;
      if (_recorder != null) {
        await _recorder!.stop();
      }

      final finishCompleter = Completer<String>();

      late StreamSubscription<AudioIsolateEvent> sub;
      sub = _isolateController.events.listen((event) {
        if (event is IsolateFinishedEvent) {
          sub.cancel();
          if (!finishCompleter.isCompleted) {
            finishCompleter.complete(event.wavFilePath);
          }
        } else if (event is IsolateErrorEvent) {
          sub.cancel();
          if (!finishCompleter.isCompleted) {
            finishCompleter.completeError(
              AudioCaptureFailure(event.message),
            );
          }
        }
      });

      _isolateController.sendCommand(const StopCaptureCommand());

      final filePath = await finishCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => _activeOutputPath ?? '',
      );

      _isRecording = false;
      _isPaused = false;
      await _isolateEventSub?.cancel();
      await _isolateController.dispose();

      return Result.success(filePath);
    } catch (e, stack) {
      _isRecording = false;
      _isPaused = false;
      return Result.error(
        AudioCaptureFailure('Failed to stop and finalize audio recording: $e', e, stack),
      );
    }
  }

  /// Cancels recording and discards temporary files.
  Future<Result<void, AudioCaptureFailure>> cancelRecording() async {
    try {
      await _microphoneStreamSub?.cancel();
      _microphoneStreamSub = null;
      if (_recorder != null) {
        await _recorder!.cancel();
      }

      _isolateController.sendCommand(const CancelCaptureCommand());
      _isRecording = false;
      _isPaused = false;
      _currentDuration = Duration.zero;

      await _isolateEventSub?.cancel();
      await _isolateController.dispose();

      if (_activeOutputPath != null) {
        final file = File(_activeOutputPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to cancel recording session: $e', e, stack),
      );
    }
  }

  /// Cleans up controllers.
  Future<void> dispose() async {
    await cancelRecording();
    await _amplitudeController.close();
    await _voiceDetectedController.close();
    await _durationController.close();
  }
}
