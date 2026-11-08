import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/vad/ambient_monitoring_service.dart';
import 'package:kinvoice/core/ml/vad/ambient_vad_isolate.dart';
import 'package:kinvoice/core/ml/vad/battery_optimization_policy.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/settings/presentation/screens/settings_screen.dart';

class FakeAmbientMonitoringService extends AmbientMonitoringService {
  FakeAmbientMonitoringService() : super();

  bool _mockEnabled = false;
  final StreamController<bool> _mockStateController =
      StreamController<bool>.broadcast();
  final StreamController<AmbientMetricsEvent> _mockMetricsController =
      StreamController<AmbientMetricsEvent>.broadcast();

  @override
  bool get isAmbientModeEnabled => _mockEnabled;

  @override
  AmbientPowerMode get currentPowerMode => AmbientPowerMode.active;

  @override
  Stream<bool> get ambientStateStream => _mockStateController.stream;

  @override
  Stream<AmbientMetricsEvent> get metricsStream => _mockMetricsController.stream;

  @override
  Future<void> startAmbientMonitoring({
    String? modelPath,
    dynamic mockAudioStream,
  }) async {
    _mockEnabled = true;
    _mockStateController.add(true);
  }

  @override
  Future<void> stopAmbientMonitoring() async {
    _mockEnabled = false;
    _mockStateController.add(false);
  }

  @override
  Future<void> toggleAmbientMode() async {
    if (_mockEnabled) {
      await stopAmbientMonitoring();
    } else {
      await startAmbientMonitoring();
    }
  }

  @override
  Future<void> dispose() async {
    await _mockStateController.close();
    await _mockMetricsController.close();
  }
}

void main() {
  group('SettingsScreen & Ambient Toggle Widget Tests', () {
    late FakeAmbientMonitoringService fakeService;

    setUp(() {
      fakeService = FakeAmbientMonitoringService();
    });

    tearDown(() async {
      await fakeService.dispose();
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: SettingsScreen(ambientService: fakeService),
      );
    }

    testWidgets('renders acoustic engine, Silero VAD v5 badge, and ambient toggle', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Settings & Models'), findsOneWidget);
      expect(find.text('Acoustic Engine & VAD'), findsOneWidget);
      expect(find.text('Passive Ambient Listener'), findsOneWidget);
      expect(find.text('Silero VAD v5 (ONNX)'), findsOneWidget);
      expect(find.text('Moonshine Base (4-bit ONNX)'), findsOneWidget);
    });

    testWidgets('toggling Master Ambient Switch enables and disables ambient listener', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      // Initial state is disabled
      expect(fakeService.isAmbientModeEnabled, isFalse);

      // Tap master switch to enable
      await tester.tap(find.text('Passive Ambient Listener'));
      await tester.pumpAndSettle();

      expect(fakeService.isAmbientModeEnabled, isTrue);
      expect(
        find.text('Ambient Voice Ear Activated (Foreground Service Running)'),
        findsOneWidget,
      );

      // Tap again to disable
      await tester.tap(find.text('Passive Ambient Listener'));
      await tester.pumpAndSettle();

      expect(fakeService.isAmbientModeEnabled, isFalse);
      expect(find.text('Ambient Voice Ear Deactivated'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(SettingsScreen))).clearSnackBars();
      await tester.pump();
    });
  });
}
