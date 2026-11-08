import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_tables.dart';

/// Database provider handling initialization, FTS5 virtual tables, and migrations.
class AppDatabase {
  AppDatabase({this.customDatabasePath});

  /// Shared singleton database provider for production runtime.
  static final AppDatabase instance = AppDatabase();

  final String? customDatabasePath;
  Database? _db;

  static const int schemaVersion = 1;
  static const String databaseName = 'kinvoice_vault.db';

  /// Returns the singleton opened database instance.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initializeDatabase();
    return _db!;
  }

  Future<Database> _initializeDatabase() async {
    // Configure FFI SQLite engine on Desktop (Windows/Linux/macOS) and unit tests
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbPath;
    if (customDatabasePath != null) {
      dbPath = customDatabasePath!;
    } else {
      final defaultDatabasesPath = await getDatabasesPath();
      dbPath = p.join(defaultDatabasesPath, databaseName);
    }

    return await openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        batch.execute(DatabaseTables.createRecordingsTable);
        batch.execute(DatabaseTables.createSegmentsTable);
        batch.execute(DatabaseTables.createSegmentsIndex);
        batch.execute(DatabaseTables.createRecordingsFtsTable);
        batch.execute(DatabaseTables.createTranscriptEmbeddingsTable);
        batch.execute(DatabaseTables.createTranscriptEmbeddingsIndex);
        await batch.commit(noResult: true);
      },
      onOpen: (db) async {
        await db.execute(DatabaseTables.createTranscriptEmbeddingsTable);
        await db.execute(DatabaseTables.createTranscriptEmbeddingsIndex);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migration hooks for future schema increments
      },
    );
  }

  /// Closes the active database.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
