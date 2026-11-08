import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../database/recording_repository.dart';
import '../../../features/home/domain/models/recording_summary.dart';
import '../../../features/player/domain/models/transcript_segment.dart';
import 'ambient_vad_isolate.dart';
import 'battery_optimization_policy.dart';
import 'speech_state_machine.dart';

/// Top-level coordinator managing continuous hands-free voice detection,
/// native background services (Android ForegroundService / iOS AVAudioSession),
/// and automatic SQLite persistence.
class AmbientMonitoringService {
  AmbientMonitoringService({
    AmbientVadIsolateController? isolateController,
    AudioRecorder? initialRecorder,
    RecordingRepository? repository,
    MethodChannel? platformChannel,
  })  : _isolateController = isolateController ?? AmbientVadIsolateController(),
        _recorder = initialRecorder,
        _repository = repository ?? RecordingRepository(),
        _platformChannel = platformChannel ??
            const MethodChannel('com.kinvoice.kinvoice/ambient_service');

  final AmbientVadIsolateController _isolateController;
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  final RecordingRepository _repository;
  final MethodChannel _platformChannel;

  StreamSubscription<AmbientIsolateEvent>? _isolateSub;
  StreamSubscription<Uint8List>? _micSub;

  bool _isAmbientModeEnabled = false;
  bool _isSpeaking = false;
  double _currentProbability = 0.0;
  double _currentRms = 0.0;
  AmbientPowerMode _currentPowerMode = AmbientPowerMode.active;

  final StreamController<bool> _ambientStateController =
      StreamController<bool>.broadcast();
  final StreamController<AmbientMetricsEvent> _metricsController =
      StreamController<AmbientMetricsEvent>.broadcast();
  final StreamController<SpeechSegment> _segmentController =
      StreamController<SpeechSegment>.broadcast();

  bool get isAmbientModeEnabled => _isAmbientModeEnabled;
  bool get isSpeaking => _isSpeaking;
  double get currentProbability => _currentProbability;
  double get currentRms => _currentRms;
  AmbientPowerMode get currentPowerMode => _currentPowerMode;

  Stream<bool> get ambientStateStream => _ambientStateController.stream;
  Stream<AmbientMetricsEvent> get metricsStream => _metricsController.stream;
  Stream<SpeechSegment> get segmentStream => _segmentController.stream;

  /// Starts ambient listening pipeline.
  /// Launches native foreground service and spawns worker isolate.
  Future<void> startAmbientMonitoring({
    String? modelPath,
    Stream<Uint8List>? mockAudioStream,
  }) async {
    if (_isAmbientModeEnabled) return;

    // 1. Notify native platform to activate foreground service / audio session
    try {
      await _platformChannel.invokeMethod('startAmbientService', {
        'channelName': 'Ambient Voice Ear',
        'notificationTitle': 'Ambient Voice Ear',
        'notificationText': 'Kinvoice is listening in low-power ambient mode',
      });
    } on MissingPluginException {
      // In headless testing or desktop platform without custom native runner
    } catch (e) {
      // Log platform channel warning
    }

    // 2. Launch background worker isolate
    await _isolateController.start(modelPath: modelPath);

    _isolateSub = _isolateController.events.listen((event) async {
      if (event is AmbientMetricsEvent) {
        _currentProbability = event.voiceProbability;
        _currentRms = event.rmsEnergy;
        _isSpeaking = event.isSpeaking;
        _currentPowerMode = event.powerMode;
        _metricsController.add(event);
      } else if (event is AmbientSegmentCompletedEvent) {
        _segmentController.add(event.segment);
        await _persistSpeechSegment(event.segment);
      }
    });

    // 3. Connect microphone capture stream into isolate
    if (mockAudioStream != null) {
      _micSub = mockAudioStream.listen((chunk) {
        _isolateController.pushChunk(chunk);
      });
    } else {
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission denied for ambient listening');
      }

      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _micSub = stream.listen((chunk) {
        _isolateController.pushChunk(chunk);
      });
    }

    _isAmbientModeEnabled = true;
    _ambientStateController.add(true);
  }

  /// Stops ambient listening, terminates native foreground service and isolate.
  Future<void> stopAmbientMonitoring() async {
    if (!_isAmbientModeEnabled) return;

    await _micSub?.cancel();
    _micSub = null;

    if (_recorder != null && await _recorder!.isRecording()) {
      await _recorder!.stop();
    }

    await _isolateSub?.cancel();
    _isolateSub = null;

    await _isolateController.dispose();

    // Notify native platform to stop foreground service
    try {
      await _platformChannel.invokeMethod('stopAmbientService');
    } catch (_) {}

    _isAmbientModeEnabled = false;
    _isSpeaking = false;
    _currentProbability = 0.0;
    _currentRms = 0.0;
    _ambientStateController.add(false);
  }

  /// Automatically persists completed speech segment to local vault and database.
  Future<void> _persistSpeechSegment(SpeechSegment segment) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory('${docsDir.path}/vault');
      if (!await vaultDir.exists()) {
        await vaultDir.create(recursive: true);
      }

      final id = 'amb_${DateTime.now().millisecondsSinceEpoch}';
      final filePath = '${vaultDir.path}/$id.wav';
      final file = File(filePath);
      await file.writeAsBytes(segment.wavBytes, flush: true);

      final summary = RecordingSummary(
        id: id,
        title: 'Ambient Note ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        createdAt: segment.startTimestamp,
        durationSeconds: segment.duration.inSeconds > 0 ? segment.duration.inSeconds : 1,
        transcriptSnippet: 'Ambient voice capture ready for on-device transcription.',
        speakers: const ['Speaker 1'],
        tags: const ['#Ambient', '#VoiceEar'],
        isFavorite: false,
        audioFilePath: filePath,
      );

      final transcriptSegment = TranscriptSegment(
        id: '${id}_seg_0',
        recordingId: id,
        startMs: 0,
        endMs: segment.duration.inMilliseconds,
        speakerId: 'Speaker 1',
        text: 'Ambient speech segment automatically isolated by Silero VAD.',
      );

      await _repository.saveRecordingWithSegments(
        recording: summary,
        segments: [transcriptSegment],
      );
    } catch (e) {
      // Avoid failing ambient ear on background file IO warning
    }
  }

  /// Toggles ambient mode on or off.
  Future<void> toggleAmbientMode() async {
    if (_isAmbientModeEnabled) {
      await stopAmbientMonitoring();
    } else {
      await startAmbientMonitoring();
    }
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await stopAmbientMonitoring();
    await _ambientStateController.close();
    await _metricsController.close();
    await _segmentController.close();
    _recorder?.dispose();
  }
}
