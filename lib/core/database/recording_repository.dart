import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/home/domain/models/recording_summary.dart';
import '../../features/player/domain/models/transcript_segment.dart';
import '../utils/failure.dart';
import '../utils/result.dart';
import 'app_database.dart';
import 'database_tables.dart';

/// Result item produced by an FTS5 full-text search match.
@immutable
class FtsSearchResult {
  const FtsSearchResult({
    required this.recordingId,
    required this.title,
    required this.snippet,
    required this.speakerId,
  });

  final String recordingId;
  final String title;
  final String snippet;
  final String speakerId;

  @override
  String toString() =>
      'FtsSearchResult(id: $recordingId, title: $title, snippet: "$snippet")';
}

/// Central repository managing recording entities, segment chronologies,
/// and FTS5 indexing.
class RecordingRepository {
  RecordingRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  static final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  /// Stream emitting an event whenever recordings or segments change in SQLite.
  static Stream<void> get changes => _changeController.stream;

  /// Notifies listeners that the recordings table has been updated.
  static void notifyChanges() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  /// Transactionally inserts or updates a recording and its child audio segments,
  /// updating the FTS5 virtual table index in the same atomic block.
  Future<Result<void, DatabaseFailure>> saveRecordingWithSegments({
    required RecordingSummary recording,
    required List<TranscriptSegment> segments,
  }) async {
    try {
      final db = await _appDatabase.database;

      await db.transaction((txn) async {
        // 1. Insert/Replace into recordings table
        await txn.insert(
          DatabaseTables.recordings,
          {
            'id': recording.id,
            'title': recording.title,
            'created_at': recording.createdAt.millisecondsSinceEpoch,
            'duration_seconds': recording.durationSeconds,
            'audio_file_path': recording.audioFilePath,
            'is_favorite': recording.isFavorite ? 1 : 0,
            'transcript_snippet': recording.transcriptSnippet,
            'tags': recording.tags.join(','),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // 2. Clear old segments if any and batch insert new ones
        await txn.delete(
          DatabaseTables.segments,
          where: 'recording_id = ?',
          whereArgs: [recording.id],
        );

        final batch = txn.batch();
        for (final segment in segments) {
          batch.insert(
            DatabaseTables.segments,
            segment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);

        // 3. Sync FTS5 virtual table
        await txn.delete(
          DatabaseTables.recordingsFts,
          where: 'recording_id = ?',
          whereArgs: [recording.id],
        );

        final combinedText = segments.map((s) => s.text).join(' ');
        final allSpeakers = segments.map((s) => s.speakerId).toSet().join(', ');

        await txn.insert(
          DatabaseTables.recordingsFts,
          {
            'recording_id': recording.id,
            'title': recording.title,
            'text': combinedText.isNotEmpty
                ? combinedText
                : recording.transcriptSnippet,
            'tags': recording.tags.join(' '),
            'speaker_id': allSpeakers.isNotEmpty
                ? allSpeakers
                : recording.speakers.join(', '),
          },
        );
      });

      notifyChanges();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to save recording and segments: $e', e, stack),
      );
    }
  }

  /// Retrieves a recording summary by its unique [id].
  Future<Result<RecordingSummary?, DatabaseFailure>> getRecordingById(
    String id,
  ) async {
    try {
      final db = await _appDatabase.database;
      final results = await db.query(
        DatabaseTables.recordings,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (results.isEmpty) {
        return const Result.success(null);
      }

      final row = results.first;
      final tagsRaw = row['tags'] as String? ?? '';
      final tags = tagsRaw.isEmpty ? <String>[] : tagsRaw.split(',');

      // Retrieve speakers from segments
      final speakerRows = await db.rawQuery(
        'SELECT DISTINCT speaker_id FROM ${DatabaseTables.segments} WHERE recording_id = ?',
        [id],
      );
      final speakers = speakerRows
          .map((r) => r['speaker_id'] as String)
          .where((s) => s.isNotEmpty)
          .toList();

      final recording = RecordingSummary(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        durationSeconds: row['duration_seconds'] as int,
        transcriptSnippet: row['transcript_snippet'] as String? ?? '',
        speakers: speakers,
        tags: tags,
        isFavorite: (row['is_favorite'] as int) == 1,
        audioFilePath: row['audio_file_path'] as String,
      );

      return Result.success(recording);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to fetch recording by id: $e', e, stack),
      );
    }
  }

  /// Retrieves all recordings ordered chronologically (newest first).
  Future<Result<List<RecordingSummary>, DatabaseFailure>> getAllRecordings() async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseTables.recordings,
        orderBy: 'created_at DESC',
      );

      final List<RecordingSummary> recordings = [];
      for (final row in rows) {
        final id = row['id'] as String;
        final tagsRaw = row['tags'] as String? ?? '';
        final tags = tagsRaw.isEmpty ? <String>[] : tagsRaw.split(',');

        final speakerRows = await db.rawQuery(
          'SELECT DISTINCT speaker_id FROM ${DatabaseTables.segments} WHERE recording_id = ?',
          [id],
        );
        final speakers = speakerRows
            .map((r) => r['speaker_id'] as String)
            .where((s) => s.isNotEmpty)
            .toList();

        recordings.add(
          RecordingSummary(
            id: id,
            title: row['title'] as String,
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
            durationSeconds: row['duration_seconds'] as int,
            transcriptSnippet: row['transcript_snippet'] as String? ?? '',
            speakers: speakers,
            tags: tags,
            isFavorite: (row['is_favorite'] as int) == 1,
            audioFilePath: row['audio_file_path'] as String,
          ),
        );
      }

      return Result.success(recordings);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to fetch all recordings: $e', e, stack),
      );
    }
  }

  /// Retrieves all segments for a specific recording, ordered by [start_ms] ascending.
  Future<Result<List<TranscriptSegment>, DatabaseFailure>> getSegmentsForRecording(
    String recordingId,
  ) async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseTables.segments,
        where: 'recording_id = ?',
        whereArgs: [recordingId],
        orderBy: 'start_ms ASC',
      );

      final segments = rows.map((r) => TranscriptSegment.fromMap(r)).toList();
      return Result.success(segments);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to fetch transcript segments: $e', e, stack),
      );
    }
  }

  /// Executes an FTS5 full-text query across titles, spoken transcripts, and tags.
  Future<Result<List<FtsSearchResult>, DatabaseFailure>> searchFts(
    String query,
  ) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) {
        return const Result.success([]);
      }

      final db = await _appDatabase.database;

      // Escape special characters and suffix with wildcard for prefix matching
      final sanitized = trimmed.replaceAll(RegExp(r'["*]'), '');
      final ftsQuery = '$sanitized*';

      final rows = await db.rawQuery(
        '''
        SELECT 
          recording_id,
          title,
          snippet(${DatabaseTables.recordingsFts}, 2, '<b>', '</b>', '...', 16) AS matched_snippet,
          speaker_id
        FROM ${DatabaseTables.recordingsFts}
        WHERE ${DatabaseTables.recordingsFts} MATCH ?
        ORDER BY rank;
        ''',
        [ftsQuery],
      );

      final results = rows.map((r) {
        return FtsSearchResult(
          recordingId: r['recording_id'] as String,
          title: r['title'] as String,
          snippet: r['matched_snippet'] as String? ?? '',
          speakerId: r['speaker_id'] as String? ?? '',
        );
      }).toList();

      return Result.success(results);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('FTS5 search query failed: $e', e, stack),
      );
    }
  }

  /// Renames a speaker across all segments in a given recording.
  Future<Result<void, DatabaseFailure>> renameSpeaker({
    required String recordingId,
    required String oldSpeakerId,
    required String newSpeakerId,
  }) async {
    try {
      final db = await _appDatabase.database;

      await db.transaction((txn) async {
        // 1. Update segments table
        await txn.update(
          DatabaseTables.segments,
          {'speaker_id': newSpeakerId},
          where: 'recording_id = ? AND speaker_id = ?',
          whereArgs: [recordingId, oldSpeakerId],
        );

        // 2. Sync FTS5 virtual table with updated speaker list and text
        final recRows = await txn.query(
          DatabaseTables.recordings,
          where: 'id = ?',
          whereArgs: [recordingId],
          limit: 1,
        );

        if (recRows.isNotEmpty) {
          final speakerRows = await txn.rawQuery(
            'SELECT DISTINCT speaker_id FROM ${DatabaseTables.segments} WHERE recording_id = ?',
            [recordingId],
          );
          final allSpeakers =
              speakerRows.map((r) => r['speaker_id'] as String).join(', ');

          final textRows = await txn.rawQuery(
            'SELECT text FROM ${DatabaseTables.segments} WHERE recording_id = ? ORDER BY start_ms ASC',
            [recordingId],
          );
          final combinedText = textRows.map((r) => r['text'] as String).join(' ');

          await txn.delete(
            DatabaseTables.recordingsFts,
            where: 'recording_id = ?',
            whereArgs: [recordingId],
          );

          await txn.insert(
            DatabaseTables.recordingsFts,
            {
              'recording_id': recordingId,
              'title': recRows.first['title'] as String,
              'text': combinedText,
              'tags': (recRows.first['tags'] as String? ?? '').replaceAll(',', ' '),
              'speaker_id': allSpeakers,
            },
          );
        }
      });

      notifyChanges();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to rename speaker: $e', e, stack),
      );
    }
  }

  /// Updates recording favorite status.
  Future<Result<void, DatabaseFailure>> updateFavoriteStatus({
    required String recordingId,
    required bool isFavorite,
  }) async {
    try {
      final db = await _appDatabase.database;
      await db.update(
        DatabaseTables.recordings,
        {'is_favorite': isFavorite ? 1 : 0},
        where: 'id = ?',
        whereArgs: [recordingId],
      );
      notifyChanges();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to update favorite status: $e', e, stack),
      );
    }
  }

  /// Updates recording title.
  Future<Result<void, DatabaseFailure>> updateRecordingTitle({
    required String recordingId,
    required String newTitle,
  }) async {
    try {
      final db = await _appDatabase.database;
      await db.transaction((txn) async {
        await txn.update(
          DatabaseTables.recordings,
          {'title': newTitle},
          where: 'id = ?',
          whereArgs: [recordingId],
        );

        final recRows = await txn.query(
          DatabaseTables.recordings,
          where: 'id = ?',
          whereArgs: [recordingId],
          limit: 1,
        );

        if (recRows.isNotEmpty) {
          final speakerRows = await txn.rawQuery(
            'SELECT DISTINCT speaker_id FROM ${DatabaseTables.segments} WHERE recording_id = ?',
            [recordingId],
          );
          final allSpeakers =
              speakerRows.map((r) => r['speaker_id'] as String).join(', ');

          final textRows = await txn.rawQuery(
            'SELECT text FROM ${DatabaseTables.segments} WHERE recording_id = ? ORDER BY start_ms ASC',
            [recordingId],
          );
          final combinedText = textRows.map((r) => r['text'] as String).join(' ');

          await txn.delete(
            DatabaseTables.recordingsFts,
            where: 'recording_id = ?',
            whereArgs: [recordingId],
          );

          await txn.insert(
            DatabaseTables.recordingsFts,
            {
              'recording_id': recordingId,
              'title': newTitle,
              'text': combinedText,
              'tags': (recRows.first['tags'] as String? ?? '').replaceAll(',', ' '),
              'speaker_id': allSpeakers,
            },
          );
        }
      });

      notifyChanges();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to update title: $e', e, stack),
      );
    }
  }

  /// Deletes a recording and its associated segments and embeddings.
  Future<Result<void, DatabaseFailure>> deleteRecording(
    String recordingId,
  ) async {
    try {
      final db = await _appDatabase.database;
      await db.transaction((txn) async {
        await txn.delete(
          DatabaseTables.recordings,
          where: 'id = ?',
          whereArgs: [recordingId],
        );
        await txn.delete(
          DatabaseTables.segments,
          where: 'recording_id = ?',
          whereArgs: [recordingId],
        );
        await txn.delete(
          DatabaseTables.recordingsFts,
          where: 'recording_id = ?',
          whereArgs: [recordingId],
        );
        await txn.delete(
          DatabaseTables.transcriptEmbeddings,
          where: 'recording_id = ?',
          whereArgs: [recordingId],
        );
      });

      notifyChanges();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to delete recording: $e', e, stack),
      );
    }
  }

  /// Clears all recordings, segments, FTS5 entries, and vector embeddings.
  Future<Result<void, DatabaseFailure>> clearAllRecordings() async {
    try {
      final db = await _appDatabase.database;
      await db.transaction((txn) async {
        await txn.delete(DatabaseTables.recordings);
        await txn.delete(DatabaseTables.segments);
        await txn.delete(DatabaseTables.recordingsFts);
        await txn.delete(DatabaseTables.transcriptEmbeddings);
      });

      notifyChanges();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        DatabaseFailure('Failed to clear all recordings: $e', e, stack),
      );
    }
  }
}
