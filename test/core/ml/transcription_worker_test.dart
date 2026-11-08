import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/database/app_database.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/core/ml/asr/asr_engine.dart';
import 'package:kinvoice/core/ml/diarization/diarization_engine.dart';
import 'package:kinvoice/core/ml/transcription_worker.dart';
import 'package:kinvoice/core/ml/vad/silero_vad_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('TranscriptionPipeline & Worker Coordinator Tests', () {
    late AppDatabase testDb;
    late RecordingRepository repository;
    late TranscriptionPipeline pipeline;
    late Uint8List multiSpeakerPcm;

    setUp(() async {
      testDb = AppDatabase(customDatabasePath: inMemoryDatabasePath);
      repository = RecordingRepository(appDatabase: testDb);

      pipeline = TranscriptionPipeline(
        vadEngine: SileroVadEngine(),
        diarizationEngine: EcapaTdnnDiarizationEngine(),
        initialAsrEngine: MoonshineAsrEngine(),
        repository: repository,
      );

      // Generate 4 seconds of synthetic 16kHz 16-bit Mono PCM (64,000 samples = 128,000 bytes)
      // First 2 seconds: Speaker 1 (250Hz tone)
      // Next 2 seconds: Speaker 2 (950Hz tone)
      multiSpeakerPcm = Uint8List(128000);
      final byteData = ByteData.sublistView(multiSpeakerPcm);

      for (int i = 0; i < 32000; i++) {
        final val = (math.sin(2 * math.pi * 250 * i / 16000) * 16000).round();
        byteData.setInt16(i * 2, val, Endian.little);
      }
      for (int i = 32000; i < 64000; i++) {
        final val = (math.sin(2 * math.pi * 950 * i / 16000) * 16000).round();
        byteData.setInt16(i * 2, val, Endian.little);
      }
    });

    tearDown(() async {
      pipeline.dispose();
      await testDb.close();
    });

    test('Pipeline executes full sequence: VAD -> Diarization -> ASR -> SQLite', () async {
      final progressEvents = <TranscriptionProgressEvent>[];

      final request = TranscriptionWorkerRequest(
        recordingId: 'rec_pipeline_001',
        audioFilePath: 'in_memory_rec_001.wav',
        modelType: AsrModelType.moonshineBase,
        title: 'Q3 Architectural Planning',
        tags: ['#Strategy', '#Meeting'],
        audioBytes: multiSpeakerPcm,
      );

      final result = await pipeline.execute(
        request: request,
        onProgress: (p) => progressEvents.add(p),
      );

      // 1. Verify progress stream continuity and monotonic increase
      expect(progressEvents.isNotEmpty, isTrue);
      expect(progressEvents.first.stage, TranscriptionStage.readingAudio);
      expect(progressEvents.last.stage, TranscriptionStage.completed);
      expect(progressEvents.last.progress, 1.0);

      double prevProgress = 0.0;
      for (final event in progressEvents) {
        expect(event.progress, greaterThanOrEqualTo(prevProgress));
        prevProgress = event.progress;
      }

      // 2. Verify Result
      expect(result.recordingId, 'rec_pipeline_001');
      expect(result.durationSeconds, 4);
      expect(result.segments.isNotEmpty, isTrue);
      expect(result.fullTranscript.isNotEmpty, isTrue);
      expect(result.speakers.isNotEmpty, isTrue);

      // 3. Verify SQLite Persistence
      final recordingsResult = await repository.getAllRecordings();
      expect(recordingsResult.isSuccess, isTrue);
      final recordings = recordingsResult.getOrNull()!;
      expect(recordings.any((r) => r.id == 'rec_pipeline_001'), isTrue);

      final savedRecording =
          recordings.firstWhere((r) => r.id == 'rec_pipeline_001');
      expect(savedRecording.title, 'Q3 Architectural Planning');
      expect(savedRecording.tags, contains('#Strategy'));

      // 4. Verify SQLite Segments
      final segmentsResult =
          await repository.getSegmentsForRecording('rec_pipeline_001');
      expect(segmentsResult.isSuccess, isTrue);
      final segments = segmentsResult.getOrNull()!;
      expect(segments.isNotEmpty, isTrue);
      expect(segments.first.speakerId, startsWith('Speaker'));

      // 5. Verify SQLite FTS5 Full-Text Search
      final searchResult = await repository.searchFts('Planning');
      expect(searchResult.isSuccess, isTrue);
      expect(searchResult.getOrNull()!.any((r) => r.recordingId == 'rec_pipeline_001'),
          isTrue);
    });

    test('TranscriptionWorkerCoordinator manages request and progress streams', () async {
      final coordinator = TranscriptionWorkerCoordinator(
        customPipeline: pipeline,
      );

      final progressList = <TranscriptionProgressEvent>[];
      final sub = coordinator.progressStream.listen(progressList.add);

      final request = TranscriptionWorkerRequest(
        recordingId: 'rec_coord_002',
        audioFilePath: 'virtual_meeting.wav',
        modelType: AsrModelType.whisperCppSmall,
        audioBytes: multiSpeakerPcm,
      );

      final result = await coordinator.transcribe(request: request);
      await pumpEventQueue();

      expect(result.recordingId, 'rec_coord_002');
      expect(progressList.any((p) => p.stage == TranscriptionStage.speechRecognition),
          isTrue);
      expect(progressList.last.stage, TranscriptionStage.completed);

      await sub.cancel();
      coordinator.dispose();
    });

    test('Pipeline handles Meta MMS Khmer model language configuration', () async {
      final khmerPipeline = TranscriptionPipeline(
        vadEngine: SileroVadEngine(),
        diarizationEngine: EcapaTdnnDiarizationEngine(),
        initialAsrEngine: MetaMmsKhmerAsrEngine(),
        repository: repository,
      );

      final request = TranscriptionWorkerRequest(
        recordingId: 'rec_khmer_003',
        audioFilePath: 'khmer_voice.wav',
        modelType: AsrModelType.metaMmsKhmer,
        language: 'km',
        audioBytes: multiSpeakerPcm,
      );

      final result = await khmerPipeline.execute(request: request);

      expect(result.recordingId, 'rec_khmer_003');
      expect(result.segments.isNotEmpty, isTrue);
      // Khmer script present
      expect(result.fullTranscript, contains('ជំរាបសួរ'));

      khmerPipeline.dispose();
    });
  });
}
