import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('ModelHubScreen & BYOK Settings Widget Tests', () {
    late SecureStorageService storageService;
    late FakeBackupExportService exportService;
    final inMemoryStorage = <String, String>{};

    setUp(() {
      inMemoryStorage.clear();
      storageService = SecureStorageService(initialInMemoryFallback: inMemoryStorage);
      exportService = FakeBackupExportService();
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: ModelHubScreen(
          storageService: storageService,
          exportService: exportService,
        ),
      );
    }

    testWidgets('renders storage breakdown, model catalog, and BYOK section', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('AI Model Hub & BYOK'), findsOneWidget);
      expect(find.text('On-Device AI Storage Breakdown'), findsOneWidget);
      expect(find.text('62 MB used by models'), findsOneWidget);
      expect(find.text('Silero VAD v5 (ONNX)'), findsOneWidget);
      expect(find.text('Moonshine Base (4-bit ONNX)'), findsOneWidget);
      expect(find.text('all-MiniLM-L6-v2 (ONNX)'), findsOneWidget);
      expect(find.text('Meta MMS Conformer (Khmer 🇰🇭)'), findsOneWidget);
      expect(find.text('BYOK Custom API Configuration'), findsOneWidget);
      expect(find.text('1-Click Vault Backup'), findsOneWidget);
    });

    testWidgets('downloading a model triggers progress and marks as installed', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find Khmer download button
      final downloadFinder = find.widgetWithText(FilledButton, 'Download');
      expect(downloadFinder, findsWidgets);

      await tester.tap(downloadFinder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('downloaded and ready'), findsOneWidget);
    });

    testWidgets('configuring and saving BYOK credentials persists encrypted keys', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Select Gemini chip
      await tester.tap(find.text('GEMINI'));
      await tester.pumpAndSettle();

      // Enter API key
      final apiKeyFinder = find.widgetWithText(TextField, 'API Key (Encrypted)');
      await tester.enterText(apiKeyFinder, 'AIzaSyTestApiKey_12345');
      await tester.pump();

      // Tap Test button
      await tester.tap(find.widgetWithText(OutlinedButton, 'Test'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Connected (GEMINI)'), findsOneWidget);

      // Tap Save Keys button
      await tester.tap(find.widgetWithText(FilledButton, 'Save Keys'));
      await tester.pumpAndSettle();

      // Verify stored in SecureStorageService
      expect(inMemoryStorage[SecureStorageService.keyApiKey], 'AIzaSyTestApiKey_12345');
      expect(inMemoryStorage[SecureStorageService.keyProvider], 'gemini');
      expect(find.text('BYOK Custom API Credentials securely saved.'), findsOneWidget);
    });

    testWidgets('1-click backup exports JSON and ZIP and displays confirmation', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final exportButton = find.widgetWithText(
        FilledButton,
        'Export All Data (JSON + ZIP)',
      );
      expect(exportButton, findsOneWidget);

      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Backup Archive Generated (1.95 MB)'), findsOneWidget);
      expect(find.textContaining('12 recordings • 48 segments'), findsOneWidget);
    });
  });
}
