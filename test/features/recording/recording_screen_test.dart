import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/audio_recorder_service.dart';
import 'package:kinvoice/core/database/app_database.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/core/services/app_preferences_service.dart';
import 'package:kinvoice/core/services/recording_storage_service.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/recording/presentation/screens/recording_screen.dart';
import 'package:kinvoice/features/recording/presentation/widgets/save_recording_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('RecordingScreen renders dark mode UI, timer, visualizer and controls', (
    WidgetTester tester,
  ) async {
    final service = AudioRecorderService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: RecordingScreen(
          recorderService: service,
          initialTitle: 'Test Studio Recording',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Verify format badge
    expect(find.text('16 kHz Mono PCM • WAV'), findsOneWidget);

    // Verify recording title
    expect(find.text('Test Studio Recording'), findsOneWidget);

    // Verify digital timer HH:MM:SS
    expect(find.text('00:00:00'), findsOneWidget);

    // Verify visualizer CustomPaint exists
    expect(find.byType(CustomPaint), findsWidgets);

    // Verify bottom control icons
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Tap Cancel button -> verify discard dialog opens
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Discard Recording?'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Keep Recording'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('Keep Recording'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Discard Recording?'), findsNothing);
  });

  testWidgets('SaveRecordingDialog renders categories, metadata, and saves to SQLite', (
    WidgetTester tester,
  ) async {
    late Directory tempDir;
    late RecordingStorageService storageService;
    late File tempAudioFile;
    late AppDatabase testDb;
    late RecordingRepository repository;
    late AppPreferencesService prefs;

    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('kinvoice_test_');
      storageService = RecordingStorageService(
        customBaseDirectoryPath: tempDir.path,
      );
      tempAudioFile = File('${tempDir.path}/temp_rec.wav');
      await tempAudioFile.writeAsBytes(List<int>.filled(64000, 0));

      testDb = AppDatabase(customDatabasePath: inMemoryDatabasePath);
      repository = RecordingRepository(appDatabase: testDb);
      prefs = AppPreferencesService();
      await prefs.setAutoTranscribeOnSave(false);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SaveRecordingDialog(
            tempFilePath: tempAudioFile.path,
            duration: const Duration(seconds: 42),
            fileSizeBytes: 64000,
            targetDirectoryPath: '${tempDir.path}/Kinvoice/Recordings',
            storageService: storageService,
            repository: repository,
            preferencesService: prefs,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Save & Tag Voice Note'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Meetings'), findsOneWidget);
    expect(find.text('Ideas'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Duration: 00:42'), findsOneWidget);

    // Select 'Meetings' category
    await tester.tap(find.text('Meetings'));
    await tester.pump();

    // Ensure 'Save & Transcribe' button is visible and tap it inside runAsync for real File/SQLite I/O
    await tester.ensureVisible(find.text('Save & Transcribe'));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Save & Transcribe'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();

    await tester.runAsync(() async {
      final allRecordingsResult = await repository.getAllRecordings();
      final savedRecordings = allRecordingsResult.getOrNull() ?? [];
      expect(savedRecordings.length, 1);
      expect(savedRecordings.first.tags, contains('#Meetings'));
      expect(
        savedRecordings.first.audioFilePath,
        contains('Kinvoice_Meetings_'),
      );

      await testDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
