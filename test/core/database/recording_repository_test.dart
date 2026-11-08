import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/srt_export_helper.dart';
import 'package:kinvoice/core/database/app_database.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/player/domain/models/transcript_segment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('RecordingRepository & SQLite FTS5 Tests', () {
    late AppDatabase appDatabase;
    late RecordingRepository repository;

    setUp(() async {
      // Use in-memory SQLite database for test isolation
      appDatabase = AppDatabase(customDatabasePath: inMemoryDatabasePath);
      repository = RecordingRepository(appDatabase: appDatabase);
    });

    tearDown(() async {
      await appDatabase.close();
    });

    final testRecording = RecordingSummary(
      id: 'rec_test_001',
      title: 'Architectural Review & Audio Pipeline',
      createdAt: DateTime(2026, 11, 8, 14, 30),
      durationSeconds: 125,
      transcriptSnippet:
          'Discussion regarding background Dart Isolates and Moonshine ONNX model.',
      speakers: const ['Ange', 'Alex'],
      tags: const ['#Architecture', '#Audio', '#Isolate'],
      isFavorite: true,
      audioFilePath: '/vault/audio/rec_test_001.wav',
    );

    final testSegments = [
      const TranscriptSegment(
        id: 'seg_001',
        recordingId: 'rec_test_001',
        startMs: 0,
        endMs: 3200,
        speakerId: 'Ange',
        text: 'Welcome team. Today we will review the audio isolate pipeline.',
      ),
      const TranscriptSegment(
        id: 'seg_002',
        recordingId: 'rec_test_001',
        startMs: 3500,
        endMs: 7800,
        speakerId: 'Alex',
        text: 'The ONNX Runtime model runs with zero main thread jank.',
      ),
      const TranscriptSegment(
        id: 'seg_003',
        recordingId: 'rec_test_001',
        startMs: 8100,
        endMs: 12400,
        speakerId: 'Ange',
        text: 'Let us also ensure full-text search snippet generation is verified.',
      ),
    ];

    test('saveRecordingWithSegments stores recording, segments, and indexes FTS5', () async {
      final saveResult = await repository.saveRecordingWithSegments(
        recording: testRecording,
        segments: testSegments,
      );

      expect(saveResult.isSuccess, isTrue);

      // Verify retrieval by ID
      final fetchResult = await repository.getRecordingById(testRecording.id);
      expect(fetchResult.isSuccess, isTrue);
      final fetched = fetchResult.getOrNull();
      expect(fetched, isNotNull);
      expect(fetched?.id, testRecording.id);
      expect(fetched?.title, testRecording.title);
      expect(fetched?.durationSeconds, 125);
      expect(fetched?.isFavorite, isTrue);
      expect(fetched?.speakers, containsAll(['Ange', 'Alex']));
      expect(fetched?.tags, containsAll(['#Architecture', '#Audio', '#Isolate']));

      // Verify segments retrieval
      final segmentsResult =
          await repository.getSegmentsForRecording(testRecording.id);
      expect(segmentsResult.isSuccess, isTrue);
      final segments = segmentsResult.getOrNull()!;
      expect(segments.length, 3);
      expect(segments[0].id, 'seg_001');
      expect(segments[0].startMs, 0);
      expect(segments[0].endMs, 3200);
      expect(segments[0].speakerId, 'Ange');
      expect(segments[1].speakerId, 'Alex');
      expect(segments[2].startMs, 8100);
    });

    test('getAllRecordings retrieves sorted recordings list', () async {
      await repository.saveRecordingWithSegments(
        recording: testRecording,
        segments: testSegments,
      );

      final secondRecording = RecordingSummary(
        id: 'rec_test_002',
        title: 'Standup Sync',
        createdAt: DateTime(2026, 11, 8, 15, 00),
        durationSeconds: 60,
        transcriptSnippet: 'Daily updates on flutter tasks.',
        speakers: const ['Ange'],
        tags: const ['#Daily'],
        isFavorite: false,
        audioFilePath: '/vault/audio/rec_test_002.wav',
      );

      await repository.saveRecordingWithSegments(
        recording: secondRecording,
        segments: [
          const TranscriptSegment(
            id: 'seg_101',
            recordingId: 'rec_test_002',
            startMs: 0,
            endMs: 2500,
            speakerId: 'Ange',
            text: 'Daily updates on flutter tasks.',
          ),
        ],
      );

      final allResult = await repository.getAllRecordings();
      expect(allResult.isSuccess, isTrue);
      final list = allResult.getOrNull()!;
      expect(list.length, 2);
      // Newest first
      expect(list.first.id, 'rec_test_002');
      expect(list.last.id, 'rec_test_001');
    });

    test('searchFts matches query term with bold snippets and speaker attribution', () async {
      await repository.saveRecordingWithSegments(
        recording: testRecording,
        segments: testSegments,
      );

      // Search for keyword "isolate"
      final searchResult = await repository.searchFts('isolate');
      expect(searchResult.isSuccess, isTrue);
      final results = searchResult.getOrNull()!;
      expect(results.isNotEmpty, isTrue);

      final match = results.first;
      expect(match.recordingId, testRecording.id);
      expect(match.title, testRecording.title);
      // FTS snippet should contain highlighted token <b>isolate</b> or <b>Isolates</b>
      expect(match.snippet.toLowerCase(), contains('<b>isolate'));

      // Search for query matching speech from Alex: "jank"
      final jankResult = await repository.searchFts('jank');
      expect(jankResult.isSuccess, isTrue);
      expect(jankResult.getOrNull()!.length, 1);
      expect(jankResult.getOrNull()!.first.snippet.toLowerCase(), contains('<b>jank</b>'));

      // Non-existent search returns empty list
      final emptyResult = await repository.searchFts('nonexistenttermxyz');
      expect(emptyResult.isSuccess, isTrue);
      expect(emptyResult.getOrNull()!, isEmpty);
    });

    test('renameSpeaker updates all matching segments and FTS index', () async {
      await repository.saveRecordingWithSegments(
        recording: testRecording,
        segments: testSegments,
      );

      // Rename "Ange" to "Architect Ange"
      final renameResult = await repository.renameSpeaker(
        recordingId: testRecording.id,
        oldSpeakerId: 'Ange',
        newSpeakerId: 'Architect Ange',
      );
      expect(renameResult.isSuccess, isTrue);

      // Verify updated segments
      final segmentsResult =
          await repository.getSegmentsForRecording(testRecording.id);
      final segments = segmentsResult.getOrNull()!;
      expect(segments[0].speakerId, 'Architect Ange');
      expect(segments[1].speakerId, 'Alex'); // Untouched
      expect(segments[2].speakerId, 'Architect Ange');

      // Verify recording summary speakers
      final recordingResult = await repository.getRecordingById(testRecording.id);
      expect(
        recordingResult.getOrNull()?.speakers,
        containsAll(['Architect Ange', 'Alex']),
      );
    });

    test('updateRecordingTitle updates title in recordings and FTS', () async {
      await repository.saveRecordingWithSegments(
        recording: testRecording,
        segments: testSegments,
      );

      final updateResult = await repository.updateRecordingTitle(
        recordingId: testRecording.id,
        newTitle: 'Deep Dive: Flutter Audio Engine',
      );
      expect(updateResult.isSuccess, isTrue);

      final fetched = (await repository.getRecordingById(testRecording.id)).getOrNull();
      expect(fetched?.title, 'Deep Dive: Flutter Audio Engine');

      // Search by new title keyword
      final searchResult = await repository.searchFts('Dive');
      expect(searchResult.isSuccess, isTrue);
      expect(searchResult.getOrNull()!.first.title, 'Deep Dive: Flutter Audio Engine');
    });

    test('deleteRecording cascade deletes recording, segments, and FTS index', () async {
      await repository.saveRecordingWithSegments(
        recording: testRecording,
        segments: testSegments,
      );

      final deleteResult = await repository.deleteRecording(testRecording.id);
      expect(deleteResult.isSuccess, isTrue);

      // Verify recording is gone
      final fetched = (await repository.getRecordingById(testRecording.id)).getOrNull();
      expect(fetched, isNull);

      // Verify segments are gone
      final segments =
          (await repository.getSegmentsForRecording(testRecording.id)).getOrNull()!;
      expect(segments, isEmpty);

      // Verify FTS returns nothing
      final searchResult = await repository.searchFts('isolate');
      expect(searchResult.getOrNull()!, isEmpty);
    });
  });

  group('SrtExportHelper & Transcript Formatter Tests', () {
    final segments = [
      const TranscriptSegment(
        id: 'seg_1',
        recordingId: 'rec_1',
        startMs: 1250, // 00:00:01,250
        endMs: 4800, // 00:00:04,800
        speakerId: 'Speaker 1',
        text: 'Hello world of ambient intelligence.',
      ),
      const TranscriptSegment(
        id: 'seg_2',
        recordingId: 'rec_1',
        startMs: 65120, // 00:01:05,120
        endMs: 72005, // 00:01:12,005
        speakerId: 'Speaker 2',
        text: 'Real-time on-device speech processing initialized.',
      ),
    ];

    test('formatSrtTimestamp correctly formats millisecond offsets to HH:MM:SS,mmm', () {
      expect(SrtExportHelper.formatSrtTimestamp(0), '00:00:00,000');
      expect(SrtExportHelper.formatSrtTimestamp(1250), '00:00:01,250');
      expect(SrtExportHelper.formatSrtTimestamp(65120), '00:01:05,120');
      expect(SrtExportHelper.formatSrtTimestamp(3661005), '01:01:01,005');
    });

    test('generateSrt produces valid standard SubRip specification', () {
      final srt = SrtExportHelper.generateSrt(segments);

      expect(srt, contains('1\n00:00:01,250 --> 00:00:04,800\n[Speaker 1] Hello world of ambient intelligence.'));
      expect(srt, contains('2\n00:01:05,120 --> 00:01:12,005\n[Speaker 2] Real-time on-device speech processing initialized.'));
    });

    test('generatePlainText produces clean timestamped text', () {
      final txt = SrtExportHelper.generatePlainText(segments);

      expect(txt, contains('[00:01] Speaker 1: Hello world of ambient intelligence.'));
      expect(txt, contains('[01:05] Speaker 2: Real-time on-device speech processing initialized.'));
    });
  });
}
