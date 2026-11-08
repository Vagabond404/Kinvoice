import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ai/model_manager/model_download_service.dart';
import 'package:kinvoice/core/services/backup_export_service.dart';
import 'package:kinvoice/core/services/secure_storage_service.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/settings/presentation/screens/model_hub_screen.dart';

class FakeBackupExportService extends Fake implements BackupExportService {
  @override
  Future<BackupExportResult> exportAllData() async {
    return BackupExportResult(
      jsonPath: '/dummy/kinvoice_backup.json',
      zipPath: '/dummy/kinvoice_backup.zip',
      recordingsCount: 12,
      segmentsCount: 48,
      fileSizeBytes: 2048576,
      exportedAt: DateTime.now(),
    );
  }
}

class FakeModelDownloadService extends ModelDownloadService {
  @override
  Future<void> refreshInstallationStatus() async {}

  @override
  Future<bool> downloadModel(
    String modelId, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final idx = models.indexWhere((m) => m.id == modelId);
    if (idx != -1) {
      models[idx].isDownloading = true;
      models[idx].downloadProgress = 0.5;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      models[idx].isDownloading = false;
      models[idx].isInstalled = true;
      models[idx].downloadProgress = 1.0;
      notifyListeners();
    }
    return true;
  }
}

void main() {
  group('ModelHubScreen & BYOK Settings Widget Tests', () {
    late SecureStorageService storageService;
    late FakeBackupExportService exportService;
    late FakeModelDownloadService modelService;
    final inMemoryStorage = <String, String>{};

    setUp(() {
      inMemoryStorage.clear();
      storageService = SecureStorageService(
        initialInMemoryFallback: inMemoryStorage,
      );
      exportService = FakeBackupExportService();
      modelService = FakeModelDownloadService();
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: ModelHubScreen(
          storageService: storageService,
          exportService: exportService,
          modelDownloadService: modelService,
        ),
      );
    }

    testWidgets('renders storage breakdown, model catalog, and BYOK section', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('AI Model Hub & BYOK'), findsOneWidget);
      expect(find.text('On-Device Neural Engine Hub'), findsOneWidget);
      expect(find.text('Model Library (GitHub & HuggingFace)'), findsOneWidget);
      expect(find.text('Silero VAD v5 (ONNX)'), findsOneWidget);
      expect(find.text('Whisper Tiny Multilingual (INT8 ONNX)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('1-Click Vault Backup'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('BYOK Custom API Configuration'), findsOneWidget);
      expect(find.text('1-Click Vault Backup'), findsOneWidget);
    });

    testWidgets('downloading a model triggers progress and marks as installed', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final downloadFinder = find.widgetWithText(FilledButton, 'Download');
      expect(downloadFinder, findsWidgets);

      await tester.tap(downloadFinder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('downloaded from'), findsOneWidget);
    });

    testWidgets('configuring and saving BYOK credentials persists encrypted keys', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('GEMINI'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Select Gemini chip
      await tester.tap(find.text('GEMINI'));
      await tester.pumpAndSettle();

      // Enter API key
      final apiKeyFinder = find.widgetWithText(TextField, 'API Key (Encrypted)');
      await tester.enterText(apiKeyFinder, 'AIzaSyTestApiKey_12345');
      await tester.pump();

      // Tap Test button
      final testBtn = find.widgetWithText(OutlinedButton, 'Test');
      await tester.ensureVisible(testBtn);
      await tester.tap(testBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Connected (GEMINI)'), findsOneWidget);

      // Tap Save Keys button
      final saveBtn = find.widgetWithText(FilledButton, 'Save Keys');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify stored in SecureStorageService
      expect(
        inMemoryStorage[SecureStorageService.keyApiKey],
        'AIzaSyTestApiKey_12345',
      );
      expect(inMemoryStorage[SecureStorageService.keyProvider], 'gemini');
      expect(find.textContaining('BYOK API Credentials saved'), findsOneWidget);
    });

    testWidgets('1-click backup exports JSON and ZIP and displays confirmation', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final exportButton = find.widgetWithText(
        FilledButton,
        'Export All Data (JSON + ZIP)',
      );
      await tester.scrollUntilVisible(
        exportButton,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(exportButton, findsOneWidget);

      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Backup Archive Generated (1.95 MB)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('12 recordings • 48 segments'),
        findsOneWidget,
      );
    });
  });
}
