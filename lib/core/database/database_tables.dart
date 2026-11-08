/// SQLite table names and SQL DDL schemas for Kinvoice.
abstract final class DatabaseTables {
  static const String recordings = 'recordings';
  static const String segments = 'segments';
  static const String recordingsFts = 'recordings_fts';
  static const String transcriptEmbeddings = 'transcript_embeddings';

  /// DDL: Recordings primary table
  static const String createRecordingsTable = '''
    CREATE TABLE IF NOT EXISTS $recordings (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      duration_seconds INTEGER NOT NULL,
      audio_file_path TEXT NOT NULL,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      transcript_snippet TEXT,
      tags TEXT
    );
  ''';

  /// DDL: Attributed transcript segments table with foreign key constraint
  static const String createSegmentsTable = '''
    CREATE TABLE IF NOT EXISTS $segments (
      id TEXT PRIMARY KEY NOT NULL,
      recording_id TEXT NOT NULL,
      start_ms INTEGER NOT NULL,
      end_ms INTEGER NOT NULL,
      speaker_id TEXT NOT NULL,
      text TEXT NOT NULL,
      FOREIGN KEY (recording_id) REFERENCES $recordings (id) ON DELETE CASCADE
    );
  ''';

  /// DDL: Index on segments for millisecond-precision chronological ordering
  static const String createSegmentsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_segments_recording_time 
    ON $segments (recording_id, start_ms ASC);
  ''';

  /// DDL: Full-Text Search (FTS5) virtual table
  static const String createRecordingsFtsTable = '''
    CREATE VIRTUAL TABLE IF NOT EXISTS $recordingsFts USING fts5(
      recording_id UNINDEXED,
      title,
      text,
      tags,
      speaker_id,
      tokenize='porter unicode61'
    );
  ''';

  /// DDL: 384-dimensional vector embeddings table for semantic memory search
  static const String createTranscriptEmbeddingsTable = '''
    CREATE TABLE IF NOT EXISTS $transcriptEmbeddings (
      id TEXT PRIMARY KEY NOT NULL,
      recording_id TEXT NOT NULL,
      segment_id TEXT NOT NULL,
      chunk_text TEXT NOT NULL,
      speaker_id TEXT NOT NULL,
      start_ms INTEGER NOT NULL,
      end_ms INTEGER NOT NULL,
      embedding BLOB NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (recording_id) REFERENCES $recordings (id) ON DELETE CASCADE
    );
  ''';

  /// DDL: Index on transcript embeddings by recording
  static const String createTranscriptEmbeddingsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_embeddings_recording 
    ON $transcriptEmbeddings (recording_id);
  ''';
}
