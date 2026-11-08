import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ai/vector_search/embedding_generator.dart';
import 'package:kinvoice/core/ai/vector_search/vector_store.dart';
import 'package:kinvoice/core/database/app_database.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/player/domain/models/transcript_segment.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('VectorStore SQLite Cosine Matching Tests', () {
    late AppDatabase testDb;
    late RecordingRepository repository;
    late VectorStore vectorStore;
    late MiniLmL6V2EmbeddingGenerator embeddingGenerator;

    setUp(() async {
      testDb = AppDatabase(customDatabasePath: inMemoryDatabasePath);
      repository = RecordingRepository(appDatabase: testDb);
      embeddingGenerator = MiniLmL6V2EmbeddingGenerator();
      vectorStore = VectorStore(
        appDatabase: testDb,
        embeddingGenerator: embeddingGenerator,
      );
    });

    tearDown(() async {
      embeddingGenerator.dispose();
      await testDb.close();
    });

    test('indexRecordingSegments stores dense 384-dim vectors and allows cosine k-NN search', () async {
      final rec = RecordingSummary(
        id: 'rec_vec_001',
        title: 'Executive Sync',
        createdAt: DateTime.now(),
        durationSeconds: 120,
        audioFilePath: 'sync.wav',
        isFavorite: false,
        transcriptSnippet: 'Discussion on marketing budget.',
        tags: ['#Marketing'],
        speakers: ['Speaker A'],
      );

      final segments = [
        const TranscriptSegment(
          id: 'seg_v1',
          recordingId: 'rec_vec_001',
          startMs: 1000,
          endMs: 5000,
          speakerId: 'Speaker A',
          text: 'We decided to increase our marketing budget by 20 percent.',
        ),
        const TranscriptSegment(
          id: 'seg_v2',
          recordingId: 'rec_vec_001',
          startMs: 6000,
          endMs: 10000,
          speakerId: 'Speaker A',
          text: 'The sprint backlog has three high priority bugs.',
        ),
      ];

      // Save recording to repository first to satisfy foreign key
      await repository.saveRecordingWithSegments(
        recording: rec,
        segments: segments,
      );

      // Index vectors
      await vectorStore.indexRecordingSegments(
        recording: rec,
        segments: segments,
      );

      // Query for marketing
      final queryEmbedding = await embeddingGenerator.generateEmbedding(
        'What was decided regarding marketing budget finance?',
      );

      final searchResults = await vectorStore.search(
        queryEmbedding: queryEmbedding,
        limit: 5,
        minSimilarity: 0.20,
      );

      expect(searchResults.isNotEmpty, isTrue);
      // Top result should be the marketing segment
      expect(searchResults.first.chunk.segmentId, 'seg_v1');
      expect(searchResults.first.chunk.chunkText, contains('marketing budget'));
      expect(searchResults.first.similarity, greaterThan(0.60));
    });

    test('deleteEmbeddingsForRecording deletes associated embeddings', () async {
      final rec = RecordingSummary(
        id: 'rec_vec_002',
        title: 'Standup',
        createdAt: DateTime.now(),
        durationSeconds: 60,
        audioFilePath: 'standup.wav',
        isFavorite: false,
        transcriptSnippet: 'Daily updates',
        tags: [],
        speakers: ['Speaker 1'],
      );

      final segments = [
        const TranscriptSegment(
          id: 'seg_v3',
          recordingId: 'rec_vec_002',
          startMs: 0,
          endMs: 4000,
          speakerId: 'Speaker 1',
          text: 'Daily standup notes.',
        ),
      ];

      await repository.saveRecordingWithSegments(
        recording: rec,
        segments: segments,
      );
      await vectorStore.indexRecordingSegments(
        recording: rec,
        segments: segments,
      );

      final queryEmb = await embeddingGenerator.generateEmbedding('Daily standup');
      final beforeDelete = await vectorStore.search(queryEmbedding: queryEmb);
      expect(beforeDelete.isNotEmpty, isTrue);

      await vectorStore.deleteEmbeddingsForRecording('rec_vec_002');
      final afterDelete = await vectorStore.search(
        queryEmbedding: queryEmb,
        recordingIdFilter: 'rec_vec_002',
      );
      expect(afterDelete.isEmpty, isTrue);
    });
  });
}
