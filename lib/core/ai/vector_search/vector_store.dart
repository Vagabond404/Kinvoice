import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../../features/home/domain/models/recording_summary.dart';
import '../../../features/player/domain/models/transcript_segment.dart';
import '../../database/app_database.dart';
import '../../database/database_tables.dart';
import 'embedding_generator.dart';

/// Stored 384-dimensional vector embedding representing a spoken transcript chunk.
@immutable
class TranscriptChunkEmbedding {
  const TranscriptChunkEmbedding({
    required this.id,
    required this.recordingId,
    required this.segmentId,
    required this.chunkText,
    required this.speakerId,
    required this.startMs,
    required this.endMs,
    required this.embedding,
    required this.createdAt,
  }) : assert(embedding.length == 384, 'Embedding must be 384 dimensions');

  final String id;
  final String recordingId;
  final String segmentId;
  final String chunkText;
  final String speakerId;
  final int startMs;
  final int endMs;
  final Float32List embedding;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recording_id': recordingId,
      'segment_id': segmentId,
      'chunk_text': chunkText,
      'speaker_id': speakerId,
      'start_ms': startMs,
      'end_ms': endMs,
      'embedding': embedding.buffer.asUint8List(),
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory TranscriptChunkEmbedding.fromMap(Map<String, dynamic> map) {
    final blob = map['embedding'] as Uint8List;
    final floatList = Float32List.sublistView(blob);

    return TranscriptChunkEmbedding(
      id: map['id'] as String,
      recordingId: map['recording_id'] as String,
      segmentId: map['segment_id'] as String,
      chunkText: map['chunk_text'] as String,
      speakerId: map['speaker_id'] as String,
      startMs: map['start_ms'] as int,
      endMs: map['end_ms'] as int,
      embedding: Float32List.fromList(floatList),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

/// Match item returned from a vector cosine similarity search.
@immutable
class VectorSearchResult {
  const VectorSearchResult({
    required this.chunk,
    required this.similarity,
  });

  final TranscriptChunkEmbedding chunk;
  final double similarity;

  @override
  String toString() =>
      'VectorSearchResult(id: ${chunk.id}, sim: ${similarity.toStringAsFixed(3)}, text: "${chunk.chunkText}")';
}

/// SQLite-backed local vector store executing cosine distance matching
/// against 384-dimensional all-MiniLM-L6-v2 embeddings.
class VectorStore {
  VectorStore({
    AppDatabase? appDatabase,
    EmbeddingGenerator? embeddingGenerator,
  })  : _appDatabase = appDatabase ?? AppDatabase.instance,
        _embeddingGenerator =
            embeddingGenerator ?? MiniLmL6V2EmbeddingGenerator();

  final AppDatabase _appDatabase;
  final EmbeddingGenerator _embeddingGenerator;

  EmbeddingGenerator get embeddingGenerator => _embeddingGenerator;

  /// Indexes an entire recording's transcript segments into dense vector space.
  Future<void> indexRecordingSegments({
    required RecordingSummary recording,
    required List<TranscriptSegment> segments,
  }) async {
    if (segments.isEmpty) return;

    final db = await _appDatabase.database;

    // Delete existing chunk embeddings for this recording
    await db.delete(
      DatabaseTables.transcriptEmbeddings,
      where: 'recording_id = ?',
      whereArgs: [recording.id],
    );

    final batch = db.batch();
    final now = DateTime.now();

    for (final segment in segments) {
      if (segment.text.trim().isEmpty) continue;

      final embedding =
          await _embeddingGenerator.generateEmbedding(segment.text);

      final chunk = TranscriptChunkEmbedding(
        id: 'emb_${segment.id}',
        recordingId: recording.id,
        segmentId: segment.id,
        chunkText: segment.text,
        speakerId: segment.speakerId,
        startMs: segment.startMs,
        endMs: segment.endMs,
        embedding: embedding,
        createdAt: now,
      );

      batch.insert(
        DatabaseTables.transcriptEmbeddings,
        chunk.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Performs k-Nearest Neighbors (k-NN) cosine similarity search against stored embeddings.
  Future<List<VectorSearchResult>> search({
    required Float32List queryEmbedding,
    int limit = 10,
    double minSimilarity = 0.25,
    String? recordingIdFilter,
  }) async {
    final db = await _appDatabase.database;

    final List<Map<String, dynamic>> rows;
    if (recordingIdFilter != null) {
      rows = await db.query(
        DatabaseTables.transcriptEmbeddings,
        where: 'recording_id = ?',
        whereArgs: [recordingIdFilter],
      );
    } else {
      rows = await db.query(DatabaseTables.transcriptEmbeddings);
    }

    if (rows.isEmpty) return [];

    final results = <VectorSearchResult>[];

    for (final row in rows) {
      final chunk = TranscriptChunkEmbedding.fromMap(row);
      final sim = MiniLmL6V2EmbeddingGenerator.computeCosineSimilarity(
        queryEmbedding,
        chunk.embedding,
      );

      if (sim >= minSimilarity) {
        results.add(VectorSearchResult(chunk: chunk, similarity: sim));
      }
    }

    // Sort by descending similarity
    results.sort((a, b) => b.similarity.compareTo(a.similarity));

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// Removes embeddings for a deleted recording.
  Future<void> deleteEmbeddingsForRecording(String recordingId) async {
    final db = await _appDatabase.database;
    await db.delete(
      DatabaseTables.transcriptEmbeddings,
      where: 'recording_id = ?',
      whereArgs: [recordingId],
    );
  }
}
