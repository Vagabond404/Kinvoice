import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../features/home/domain/models/recording_summary.dart';
import '../../features/player/domain/models/transcript_segment.dart';
import '../audio/wav_header_helper.dart';
import '../database/recording_repository.dart';
import '../utils/result.dart';
import 'asr/asr_engine.dart';
import 'diarization/diarization_engine.dart';
import 'vad/silero_vad_engine.dart';
import 'vad/speech_state_machine.dart';

/// Sequential stages of the transcription worker pipeline.
enum TranscriptionStage {
  idle,
  readingAudio,
  vadSegmentation,
  speakerDiarization,
  speechRecognition,
  savingDatabase,
  completed,
  failed,
}

/// Request parameters submitted to the transcription worker.
@immutable
class TranscriptionWorkerRequest {
  const TranscriptionWorkerRequest({
    required this.recordingId,
    required this.audioFilePath,
    this.modelType = AsrModelType.moonshineBase,
    this.language = 'en',
    this.title,
    this.tags = const [],
    this.audioBytes,
  });

  final String recordingId;
  final String audioFilePath;
  final AsrModelType modelType;
  final String language;
  final String? title;
  final List<String> tags;

  /// Optional in-memory audio bytes for testing or streaming inputs.
  final Uint8List? audioBytes;
}

/// Progress event emitted during sequential worker execution.
@immutable
class TranscriptionProgressEvent {
  const TranscriptionProgressEvent({
    required this.recordingId,
    required this.progress,
    required this.stage,
    required this.message,
    this.error,
  });

  final String recordingId;

  /// Progress fraction normalized between 0.0 and 1.0.
  final double progress;
  final TranscriptionStage stage;
  final String message;
  final String? error;

  bool get isCompleted => stage == TranscriptionStage.completed;
  bool get isFailed => stage == TranscriptionStage.failed;

  @override
  String toString() =>
      'TranscriptionProgressEvent(id: $recordingId, stage: $stage, ${(progress * 100).toStringAsFixed(1)}%, msg: "$message")';
}

/// Final output returned upon successful completion of transcription & diarization.
@immutable
class TranscriptionResultEvent {
  const TranscriptionResultEvent({
    required this.recordingId,
    required this.segments,
    required this.speakers,
    required this.fullTranscript,
    required this.durationSeconds,
  });

  final String recordingId;
  final List<TranscriptSegment> segments;
  final List<String> speakers;
  final String fullTranscript;
  final int durationSeconds;

  @override
  String toString() =>
      'TranscriptionResultEvent(id: $recordingId, segments: ${segments.length}, speakers: $speakers)';
}

/// Core pipeline orchestrating sequential VAD -> Diarization -> ASR -> SQLite persistence.
class TranscriptionPipeline {
  TranscriptionPipeline({
    SileroVadEngine? vadEngine,
    DiarizationEngine? diarizationEngine,
    AsrEngine? initialAsrEngine,
    RecordingRepository? repository,
  })  : _vadEngine = vadEngine ?? SileroVadEngine(),
        _diarizationEngine = diarizationEngine ?? EcapaTdnnDiarizationEngine(),
        _asrEngine = initialAsrEngine,
        _repository = repository ?? RecordingRepository();

  final SileroVadEngine _vadEngine;
  final DiarizationEngine _diarizationEngine;
  final AsrEngine? _asrEngine;
  final RecordingRepository _repository;

  /// Executes the full multi-stage pipeline for a transcription request.
  Future<TranscriptionResultEvent> execute({
    required TranscriptionWorkerRequest request,
    void Function(TranscriptionProgressEvent progress)? onProgress,
  }) async {
    void emit(double progress, TranscriptionStage stage, String message,
        [String? error]) {
      onProgress?.call(
        TranscriptionProgressEvent(
          recordingId: request.recordingId,
          progress: progress.clamp(0.0, 1.0),
          stage: stage,
          message: message,
          error: error,
        ),
      );
    }

    try {
      // ---------------------------------------------------------------------
      // 1. Audio Ingestion (0% - 10%)
      // ---------------------------------------------------------------------
      emit(0.05, TranscriptionStage.readingAudio, 'Loading audio file...');

      Uint8List rawAudioBytes;
      if (request.audioBytes != null && request.audioBytes!.isNotEmpty) {
        rawAudioBytes = request.audioBytes!;
      } else {
        final file = File(request.audioFilePath);
        if (!await file.exists()) {
          throw StateError('Audio file does not exist at ${request.audioFilePath}');
        }
        rawAudioBytes = await file.readAsBytes();
      }

      final pcmBytes = _extractPcmData(rawAudioBytes);
      final durationSeconds = (pcmBytes.length ~/ 2) ~/ 16000;

      emit(0.15, TranscriptionStage.readingAudio,
          'Audio loaded (${durationSeconds}s, 16kHz PCM).');

      // ---------------------------------------------------------------------
      // 2. Silero VAD Voice Segmentation (15% - 35%)
      // ---------------------------------------------------------------------
      emit(0.20, TranscriptionStage.vadSegmentation,
          'Running Silero VAD v5 speech boundary detection...');

      final stateMachine = SpeechStateMachine();
      final speechSegments = <SpeechSegment>[];
      const frameBytes = SileroVadEngine.frameBytes; // 1024 bytes (512 samples)

      for (int i = 0; i + frameBytes <= pcmBytes.length; i += frameBytes) {
        final frame = pcmBytes.sublist(i, i + frameBytes);
        final prob = _vadEngine.processPcmBytes(frame);
        final segment = stateMachine.processFrame(
          pcmChunk: frame,
          voiceProbability: prob,
        );
        if (segment != null) {
          speechSegments.add(segment);
        }
      }

      final flushed = stateMachine.flush();
      if (flushed != null) {
        speechSegments.add(flushed);
      }

      emit(0.35, TranscriptionStage.vadSegmentation,
          'VAD complete: detected ${speechSegments.length} active speech sections.');

      // ---------------------------------------------------------------------
      // 3. ECAPA-TDNN Speaker Diarization (35% - 60%)
      // ---------------------------------------------------------------------
      emit(0.40, TranscriptionStage.speakerDiarization,
          'Extracting 192-dim ECAPA-TDNN speaker embeddings...');

      final embeddings = await _diarizationEngine.extractEmbeddings(
        pcmBytes,
        sampleRate: 16000,
      );

      emit(0.55, TranscriptionStage.speakerDiarization,
          'Extracted ${embeddings.length} speaker embeddings. Clustering via pure Dart cosine similarity...');

      // ---------------------------------------------------------------------
      // 4. Speech-to-Text Transcription & Alignment (60% - 85%)
      // ---------------------------------------------------------------------
      emit(0.60, TranscriptionStage.speechRecognition,
          'Initializing ${request.modelType.name} ASR engine...');

      final asr = _asrEngine ??
          AsrEngineFactory.createEngine(modelType: request.modelType);

      final rawAsrSegments = await asr.transcribe(
        pcmBytes: pcmBytes,
        sampleRate: 16000,
        language: request.language,
      );

      emit(0.75, TranscriptionStage.speechRecognition,
          'Aligning speaker diarization clusters with transcript segments...');

      final alignedAsrSegments = await _diarizationEngine.diarizeAndAlign(
        pcmBytes: pcmBytes,
        segments: rawAsrSegments,
        sampleRate: 16000,
      );

      emit(0.85, TranscriptionStage.speechRecognition,
          'ASR & Diarization complete (${alignedAsrSegments.length} segments).');

      // ---------------------------------------------------------------------
      // 5. Database Persistence (85% - 100%)
      // ---------------------------------------------------------------------
      emit(0.90, TranscriptionStage.savingDatabase,
          'Saving transcript and speaker attribution into SQLite FTS5...');

      final transcriptSegments = <TranscriptSegment>[];
      final detectedSpeakers = <String>{};

      for (int i = 0; i < alignedAsrSegments.length; i++) {
        final seg = alignedAsrSegments[i];
        final speaker = seg.speakerId ?? 'Speaker A';
        detectedSpeakers.add(speaker);

        transcriptSegments.add(
          seg.toTranscriptSegment(
            id: '${request.recordingId}_seg_$i',
            recordingId: request.recordingId,
            defaultSpeaker: speaker,
          ),
        );
      }

      final fullTranscript = transcriptSegments.map((s) => s.text).join(' ');
      final snippet = fullTranscript.length > 120
          ? '${fullTranscript.substring(0, 117)}...'
          : fullTranscript;

      final summary = RecordingSummary(
        id: request.recordingId,
        title: request.title ??
            (snippet.isNotEmpty ? _generateTitle(snippet) : 'Voice Memo'),
        createdAt: DateTime.now(),
        durationSeconds: durationSeconds,
        audioFilePath: request.audioFilePath,
        isFavorite: false,
        transcriptSnippet: snippet,
        tags: request.tags.isNotEmpty ? request.tags : ['#Voice', '#AI'],
        speakers: detectedSpeakers.toList(),
      );

      final saveResult = await _repository.saveRecordingWithSegments(
        recording: summary,
        segments: transcriptSegments,
      );

      if (saveResult.isError) {
        final err = (saveResult as Error).failure;
        throw StateError(
            'Failed to save transcript to SQLite: ${err.message}');
      }

      emit(1.0, TranscriptionStage.completed,
          'Transcription and diarization completed successfully.');

      return TranscriptionResultEvent(
        recordingId: request.recordingId,
        segments: transcriptSegments,
        speakers: detectedSpeakers.toList(),
        fullTranscript: fullTranscript,
        durationSeconds: durationSeconds,
      );
    } catch (e, stack) {
      debugPrint('TranscriptionPipeline error: $e\n$stack');
      emit(1.0, TranscriptionStage.failed, 'Pipeline failure: $e', e.toString());
      rethrow;
    }
  }

  void dispose() {
    _vadEngine.dispose();
    _diarizationEngine.dispose();
    _asrEngine?.dispose();
  }

  /// Extracts pure 16-bit linear PCM from raw WAV byte buffer or raw bytes.
  Uint8List _extractPcmData(Uint8List rawBytes) {
    if (rawBytes.length >= 44 &&
        rawBytes[0] == 0x52 &&
        rawBytes[1] == 0x49 &&
        rawBytes[2] == 0x46 &&
        rawBytes[3] == 0x46) {
      // Standard RIFF WAV header present, skip 44 header bytes
      return rawBytes.sublist(WavHeaderHelper.headerSize);
    }
    return rawBytes;
  }

  static String _generateTitle(String snippet) {
    final words = snippet.split(' ');
    if (words.length <= 4) return snippet;
    return '${words.take(4).join(' ')}...';
  }
}

// ---------------------------------------------------------------------------
// Worker Isolate Coordinator
// ---------------------------------------------------------------------------

/// Params passed to background isolate upon spawning.
class _WorkerIsolateParams {
  const _WorkerIsolateParams({
    required this.sendPort,
    required this.rootToken,
  });

  final SendPort sendPort;
  final RootIsolateToken rootToken;
}

/// Main-thread controller managing background worker isolate execution.
class TranscriptionWorkerCoordinator {
  TranscriptionWorkerCoordinator({
    TranscriptionPipeline? customPipeline,
  }) : _directPipeline = customPipeline;

  final TranscriptionPipeline? _directPipeline;
  final StreamController<TranscriptionProgressEvent> _progressController =
      StreamController<TranscriptionProgressEvent>.broadcast();

  Stream<TranscriptionProgressEvent> get progressStream =>
      _progressController.stream;

  bool _isDisposed = false;

  /// Executes transcription on a background worker Isolate with real-time progress events.
  Future<TranscriptionResultEvent> transcribe({
    required TranscriptionWorkerRequest request,
  }) async {
    if (_isDisposed) {
      throw StateError('TranscriptionWorkerCoordinator is disposed');
    }

    // If a custom pipeline was provided (e.g. for unit testing or deterministic testing)
    if (_directPipeline != null) {
      return _directPipeline.execute(
        request: request,
        onProgress: (p) => _progressController.add(p),
      );
    }

    // Spawn background worker Isolate
    final receivePort = ReceivePort();
    final rootToken = ServicesBinding.rootIsolateToken;
    final completer = Completer<TranscriptionResultEvent>();

    Isolate? isolate;

    if (rootToken != null) {
      try {
        isolate = await Isolate.spawn<_WorkerIsolateParams>(
          _workerIsolateEntryPoint,
          _WorkerIsolateParams(
            sendPort: receivePort.sendPort,
            rootToken: rootToken,
          ),
        );
      } catch (e) {
        debugPrint('Failed to spawn background isolate: $e. Falling back to in-thread execution.');
        final pipeline = TranscriptionPipeline();
        try {
          return await pipeline.execute(
            request: request,
            onProgress: (p) => _progressController.add(p),
          );
        } finally {
          pipeline.dispose();
        }
      }
    } else {
      // In tests without RootIsolateToken, execute in-thread
      final pipeline = TranscriptionPipeline();
      try {
        return await pipeline.execute(
          request: request,
          onProgress: (p) => _progressController.add(p),
        );
      } finally {
        pipeline.dispose();
      }
    }

    SendPort? workerSendPort;

    receivePort.listen((message) {
      if (message is SendPort) {
        workerSendPort = message;
        workerSendPort!.send(request);
      } else if (message is TranscriptionProgressEvent) {
        _progressController.add(message);
      } else if (message is TranscriptionResultEvent) {
        receivePort.close();
        isolate?.kill();
        if (!completer.isCompleted) completer.complete(message);
      } else if (message is Map<String, dynamic> && message['error'] != null) {
        receivePort.close();
        isolate?.kill();
        if (!completer.isCompleted) {
          completer.completeError(
            StateError(message['error'] as String),
          );
        }
      }
    });

    return completer.future;
  }

  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _progressController.close();
      _directPipeline?.dispose();
    }
  }
}

/// Static entry point running inside the spawned background Isolate.
void _workerIsolateEntryPoint(_WorkerIsolateParams params) {
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.rootToken);

  final commandPort = ReceivePort();
  params.sendPort.send(commandPort.sendPort);

  commandPort.listen((message) async {
    if (message is TranscriptionWorkerRequest) {
      final pipeline = TranscriptionPipeline();
      try {
        final result = await pipeline.execute(
          request: message,
          onProgress: (progress) {
            params.sendPort.send(progress);
          },
        );
        params.sendPort.send(result);
      } catch (e) {
        params.sendPort.send({'error': e.toString()});
      } finally {
        pipeline.dispose();
        commandPort.close();
      }
    }
  });
}
