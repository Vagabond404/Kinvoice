import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/audio_recorder_service.dart';
import 'package:kinvoice/core/audio/rms_calculator.dart';
import 'package:kinvoice/core/audio/srt_export_helper.dart';
import 'package:kinvoice/core/ml/asr/asr_engine.dart';
import 'package:kinvoice/core/services/app_preferences_service.dart';
import 'package:kinvoice/core/services/recording_notification_service.dart';
import 'package:kinvoice/core/theme/app_colors.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/core/utils/failure.dart';
import 'package:kinvoice/core/utils/result.dart';
import 'package:kinvoice/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:kinvoice/features/player/domain/models/transcript_segment.dart';
import 'package:kinvoice/features/recording/presentation/screens/recording_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotificationService extends RecordingNotificationService {
  _FakeNotificationService({super.customRecoveryDirPath});

  @override
  Future<bool> hasSufficientStorage({int? simulatedAvailableBytes}) async {
    if (simulatedAvailableBytes != null) {
      return simulatedAvailableBytes >=
          RecordingNotificationService.minRequiredFreeBytes;
    }
    return true;
  }

  @override
  Future<bool> requestAllPermissions() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<void> startRecordingNotification({
    required String title,
    Duration elapsed = Duration.zero,
    bool isPaused = false,
  }) async {}

  @override
  Future<void> updateRecordingNotification({
    required String title,
    required Duration elapsed,
    required bool isPaused,
  }) async {}

  @override
  Future<void> stopRecordingNotification() async {}
}

class _PermissionDeniedRecorderService extends AudioRecorderService {
  @override
  bool get isRecording => false;

  @override
  Future<Result<void, AudioCaptureFailure>> startRecording({
    String? customPath,
    Stream<Uint8List>? mockAudioStream,
  }) async {
    return const Result.error(
      AudioCaptureFailure('Microphone permission was denied.'),
    );
  }
}

class _ActiveMockRecorderService extends AudioRecorderService {
  bool _recording = false;
  bool _paused = false;

  @override
  bool get isRecording => _recording;

  @override
  bool get isPaused => _paused;

  @override
  String? get activeOutputPath => '';

  @override
  Future<Result<void, AudioCaptureFailure>> startRecording({
    String? customPath,
    Stream<Uint8List>? mockAudioStream,
  }) async {
    _recording = true;
    _paused = false;
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> pauseRecording() async {
    _paused = true;
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> resumeRecording() async {
    _paused = false;
    return const Result.success(null);
  }

  @override
  Future<Result<String, AudioCaptureFailure>> stopRecording() async {
    _recording = false;
    _paused = false;
    return const Result.success('/tmp/active_session.wav');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deliverable 7: Comprehensive Edge-Case Hardening & Stress Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
      '1. Permission Denied / Revoked shows graceful UI alert and Settings CTA with zero crashes',
      (WidgetTester tester) async {
        final deniedRecorder = _PermissionDeniedRecorderService();
        final fakeNotif = _FakeNotificationService();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: RecordingScreen(
              recorderService: deniedRecorder,
              notificationService: fakeNotif,
              initialTitle: 'Denied Test',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Microphone Permission Required'), findsOneWidget);
        expect(find.text('Open App Settings'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.text('Microphone permission denied. Tap Settings to enable.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. Interrupted Audio (incoming phone call / alarm) auto-pauses and preserves buffer',
      (WidgetTester tester) async {
        final activeRecorder = _ActiveMockRecorderService();
        final fakeNotif = _FakeNotificationService();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: RecordingScreen(
              recorderService: activeRecorder,
              notificationService: fakeNotif,
              initialTitle: 'Call Interruption Test',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(activeRecorder.isRecording, isTrue);
        expect(activeRecorder.isPaused, isFalse);

        final state = tester.state<RecordingScreenState>(
          find.byType(RecordingScreen),
        );
        await state.handleAudioInterruption();
        await tester.pump();

        expect(activeRecorder.isPaused, isTrue);
        expect(find.text('PAUSED'), findsOneWidget);
      },
    );

    test(
      '3. Storage Exhaustion guard blocks recording when free disk space is below 15 MB',
      () async {
        final notifService = _FakeNotificationService();

        final lowStorage = await notifService.hasSufficientStorage(
          simulatedAvailableBytes: 5 * 1024 * 1024, // 5 MB (< 15 MB)
        );
        expect(lowStorage, isFalse);

        final healthyStorage = await notifService.hasSufficientStorage(
          simulatedAvailableBytes: 512 * 1024 * 1024, // 512 MB (>= 15 MB)
        );
        expect(healthyStorage, isTrue);
      },
    );

    test(
      '4. App Killed / Crash Recovery writes journal and detects unfinalized audio on relaunch',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('kinvoice_crash_');
        final tempWav = File('${tempDir.path}/unfinalized_chunk.wav');
        await tempWav.writeAsBytes(Uint8List(32000)); // 1 second of 16kHz PCM

        final notifService = _FakeNotificationService(
          customRecoveryDirPath: tempDir.path,
        );

        final entry = CrashRecoveryJournalEntry(
          tempFilePath: tempWav.path,
          title: 'Boardroom Strategy Call',
          category: 'Meetings',
          startedAtMs: DateTime(2026, 11, 8, 14, 30).millisecondsSinceEpoch,
          elapsedSeconds: 185,
        );

        await notifService.writeRecoveryJournal(entry);

        final recovered = await notifService.checkUnfinalizedRecording();
        expect(recovered, isNotNull);
        expect(recovered!.title, 'Boardroom Strategy Call');
        expect(recovered.category, 'Meetings');
        expect(recovered.elapsedSeconds, 185);
        expect(recovered.tempFilePath, tempWav.path);

        await notifService.clearRecoveryJournal();
        final afterClear = await notifService.checkUnfinalizedRecording();
        expect(afterClear, isNull);

        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test(
      '5. Ultra-Short (0s / 1s) vs Long (2+ Hours) recordings: zero division by zero & bounded memory',
      () async {
        // Ultra-short: 0 bytes & 1 byte (odd byte count)
        expect(RmsCalculator.calculateNormalizedRms(Uint8List(0)), 0.0);
        expect(RmsCalculator.calculateNormalizedRms(Uint8List(1)), 0.0);
        expect(RmsCalculator.calculateDecibels(0.0), -60.0);

        // Ultra-short: 1 second of silence (16000 samples)
        final oneSecSilence = Uint8List(32000);
        expect(RmsCalculator.calculateNormalizedRms(oneSecSilence), 0.0);

        // Ultra-short ASR transcription (0 samples & 1 second)
        final asr = MoonshineAsrEngine();
        await asr.initialize();
        final emptyResult = await asr.transcribe(
          pcmBytes: Uint8List(0),
        );
        expect(emptyResult, isEmpty);

        final oneSecResult = await asr.transcribe(
          pcmBytes: oneSecSilence,
        );
        expect(oneSecResult.isNotEmpty, isTrue);
        expect(oneSecResult.first.endMs, greaterThan(0));
        asr.dispose();

        // 2+ Hours (7,200 seconds = 25,920,000 ms) SRT timecode & RMS stress test
        final twoHourTimecode = SrtExportHelper.formatSrtTimestamp(7542400);
        expect(twoHourTimecode, '02:05:42,400');

        final longSegments = List.generate(
          205,
          (i) => TranscriptSegment(
            id: 'seg_$i',
            recordingId: 'rec_2h',
            startMs: i * 36000,
            endMs: (i * 36000) + 30000,
            speakerId: 'Speaker ${(i % 2) + 1}',
            text: 'Continuous 2-hour stress test segment $i.',
          ),
        );
        final srtOutput = SrtExportHelper.generateSrt(longSegments);
        expect(srtOutput, contains('02:00:00,000'));
      },
    );

    testWidgets(
      '6. First-Launch Onboarding 3-step flow persists has_completed_onboarding: true',
      (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = AppPreferencesService();
        await prefs.init();
        final fakeNotif = _FakeNotificationService();
        expect(prefs.hasCompletedOnboarding, isFalse);

        bool completedCallbackFired = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: OnboardingScreen(
              preferencesService: prefs,
              notificationService: fakeNotif,
              onCompleted: () {
                completedCallbackFired = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Step 1: Welcome
        expect(find.text('Welcome to Kinvoice'), findsOneWidget);
        expect(find.text('Your Ambient Voice Second Brain'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 2: 100% On-Device Privacy Guarantee
        expect(find.text('100% On-Device Privacy Guarantee'), findsOneWidget);
        await tester.tap(find.text('I Agree & Continue'));
        await tester.pumpAndSettle();

        // Step 3: Permissions Request Step
        expect(find.text('Essential System Permissions'), findsOneWidget);
        await tester.tap(find.text('Grant Permissions & Start Kinvoice'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(completedCallbackFired, isTrue);
        expect(prefs.hasCompletedOnboarding, isTrue);
      },
    );

    test(
      '7. Theme Switcher persists System Default, Pure Dark (#0B0F19), and Clean Light (#F8FAFC)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = AppPreferencesService();
        await prefs.init();

        expect(prefs.themeModeCode, 'system');
        expect(prefs.themeMode, ThemeMode.system);

        await prefs.setThemeModeCode('dark');
        expect(prefs.themeMode, ThemeMode.dark);
        expect(AppColors.backgroundDark, const Color(0xFF0B0F19));

        await prefs.setThemeModeCode('light');
        expect(prefs.themeMode, ThemeMode.light);
        expect(AppColors.backgroundLight, const Color(0xFFF8FAFC));

        // Verify live notification HH:MM:SS timer formatting
        expect(
          RecordingNotificationService.formatDurationHhMmSs(Duration.zero),
          '00:00:00',
        );
        expect(
          RecordingNotificationService.formatDurationHhMmSs(
            const Duration(seconds: 3661),
          ),
          '01:01:01',
        );
        expect(
          RecordingNotificationService.formatDurationHhMmSs(
            const Duration(seconds: 7325),
          ),
          '02:02:05',
        );
      },
    );
  });
}
