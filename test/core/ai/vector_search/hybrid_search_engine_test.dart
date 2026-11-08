import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ai/vector_search/embedding_generator.dart';
import 'package:kinvoice/core/ai/vector_search/hybrid_search_engine.dart';
import 'package:kinvoice/core/ai/vector_search/vector_store.dart';
import 'package:kinvoice/core/database/app_database.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/player/domain/models/transcript_segment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('HybridSearchEngine Hybrid Retrieval Tests', () {
    late AppDatabase testDb;
    late RecordingRepository repository;
    late VectorStore vectorStore;
    late MiniLmL6V2EmbeddingGenerator embeddingGenerator;
    late HybridSearchEngine hybridEngine;

    setUp(() async {
      testDb = AppDatabase(customDatabasePath: inMemoryDatabasePath);
      repository = RecordingRepository(appDatabase: testDb);
      embeddingGenerator = MiniLmL6V2EmbeddingGenerator();
      vectorStore = VectorStore(
        appDatabase: testDb,
        embeddingGenerator: embeddingGenerator,
      );

      hybridEngine = HybridSearchEngine(
        repository: repository,
        vectorStore: vectorStore,
        embeddingGenerator: embeddingGenerator,
      );

      // Seed database with two realistic conversational meetings
      final rec1 = RecordingSummary(
        id: 'rec_m1',
        title: 'Q3 Marketing Strategy Sync',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        durationSeconds: 180,
        audioFilePath: 'marketing_sync.wav',
        isFavorite: true,
        transcriptSnippet: 'Discussion on marketing budget allocation.',
        tags: ['#Marketing', '#Strategy'],
        speakers: ['Speaker A', 'Speaker B'],
      );

      final segments1 = [
        const TranscriptSegment(
          id: 'seg_m1_1',
          recordingId: 'rec_m1',
          startMs: 14000,
          endMs: 32000,
          speakerId: 'Speaker A',
          text: 'We finalized the marketing campaign budget to twenty thousand dollars.',
        ),
        const TranscriptSegment(
          id: 'seg_m1_2',
          recordingId: 'rec_m1',
          startMs: 35000,
          endMs: 50000,
          speakerId: 'Speaker B',
          text: 'Approved. The brand advertising push launches on Monday.',
        ),
      ];

      final rec2 = RecordingSummary(
        id: 'rec_m2',
        title: 'Engineering Sprint Backlog',
        createdAt: DateTime.now(),
        durationSeconds: 120,
        audioFilePath: 'sprint.wav',
        isFavorite: false,
        transcriptSnippet: 'Sprint backlog bugs resolved.',
        tags: ['#Dev'],
        speakers: ['Speaker C'],
      );

      final segments2 = [
        const TranscriptSegment(
          id: 'seg_m2_1',
          recordingId: 'rec_m2',
          startMs: 2000,
          endMs: 12000,
          speakerId: 'Speaker C',
          text: 'The architecture pipeline refactoring is complete.',
        ),
      ];

      await repository.saveRecordingWithSegments(
        recording: rec1,
        segments: segments1,
      );
      await vectorStore.indexRecordingSegments(
        recording: rec1,
        segments: segments1,
      );

      await repository.saveRecordingWithSegments(
        recording: rec2,
        segments: segments2,
      );
      await vectorStore.indexRecordingSegments(
        recording: rec2,
        segments: segments2,
      );
    });

    tearDown(() async {
      embeddingGenerator.dispose();
      await testDb.close();
    });

    test('Hybrid search blends keyword and semantic scoring for conversational queries', () async {
      final response = await hybridEngine.search(
        query: 'What did I decide in yesterday\'s meeting about marketing?',
      );

      expect(response.results.isNotEmpty, isTrue);
      final topMatch = response.results.first;

      expect(topMatch.recordingId, 'rec_m1');
      expect(topMatch.recordingTitle, 'Q3 Marketing Strategy Sync');
      expect(
        response.results.any((r) => r.text.contains('marketing campaign budget')),
        isTrue,
      );
      expect(['Speaker A', 'Speaker B'], contains(topMatch.speakerId));
      expect(topMatch.startMs, greaterThanOrEqualTo(0));
      expect(topMatch.formattedStartTime.isNotEmpty, isTrue);

      // Verify Generative Answer Summary
      expect(response.generativeSummary.isNotEmpty, isTrue);
      expect(response.generativeSummary, contains('Q3 Marketing Strategy Sync'));

      // Verify Citations
      expect(response.citations.isNotEmpty, isTrue);
      final citation = response.citations.first;
      expect(citation.recordingId, 'rec_m1');
      expect(citation.formattedStartTime.isNotEmpty, isTrue);
    });

    test('Returns empty response for blank query', () async {
      final response = await hybridEngine.search(query: '   ');
      expect(response.results.isEmpty, isTrue);
      expect(response.citations.isEmpty, isTrue);
      expect(response.generativeSummary.isEmpty, isTrue);
    });
  });
}
