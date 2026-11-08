import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/audio_player_service.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/core/utils/failure.dart';
import 'package:kinvoice/core/utils/result.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/player/domain/models/transcript_segment.dart';
import 'package:kinvoice/features/player/presentation/screens/player_screen.dart';
import 'package:kinvoice/features/player/presentation/widgets/scrubbable_waveform_track.dart';
import 'package:kinvoice/features/player/presentation/widgets/transcript_segment_tile.dart';

/// Test audio player double to avoid platform channels during headless widget tests.
class FakeAudioPlayerService extends AudioPlayerService {
  FakeAudioPlayerService() : super();

  final StreamController<Duration> _mockPositionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _mockDurationController =
      StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _mockStateController =
      StreamController<PlayerState>.broadcast();

  Duration _mockPosition = Duration.zero;
  final Duration _mockDuration = const Duration(seconds: 120);
  PlayerState _mockState = PlayerState.stopped;
  double _mockRate = 1.0;

  @override
  Stream<Duration> get positionStream => _mockPositionController.stream;

  @override
  Stream<Duration> get durationStream => _mockDurationController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _mockStateController.stream;

  @override
  Duration get currentPosition => _mockPosition;

  @override
  Duration get totalDuration => _mockDuration;

  @override
  PlayerState get playerState => _mockState;

  @override
  bool get isPlaying => _mockState == PlayerState.playing;

  @override
  double get playbackRate => _mockRate;

  @override
  Future<Result<void, AudioCaptureFailure>> play(
    String filePath, {
    Duration? initialPosition,
  }) async {
    _mockState = PlayerState.playing;
    _mockStateController.add(_mockState);
    if (initialPosition != null) {
      _mockPosition = initialPosition;
      _mockPositionController.add(_mockPosition);
    }
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> pause() async {
    _mockState = PlayerState.paused;
    _mockStateController.add(_mockState);
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> resume() async {
    _mockState = PlayerState.playing;
    _mockStateController.add(_mockState);
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> stop() async {
    _mockState = PlayerState.stopped;
    _mockPosition = Duration.zero;
    _mockStateController.add(_mockState);
    _mockPositionController.add(_mockPosition);
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> seek(Duration position) async {
    _mockPosition = position;
    _mockPositionController.add(position);
    return const Result.success(null);
  }

  @override
  Future<Result<void, AudioCaptureFailure>> setPlaybackRate(double rate) async {
    _mockRate = rate;
    return const Result.success(null);
  }

  @override
  Future<void> dispose() async {
    await _mockPositionController.close();
    await _mockDurationController.close();
    await _mockStateController.close();
  }
}

/// Mock repository double to decouple UI widget tests from SQLite native locks.
class MockRecordingRepository extends RecordingRepository {
  String? lastUpdatedRecordingId;
  String? lastUpdatedTitle;
  String? lastRenamedOldSpeaker;
  String? lastRenamedNewSpeaker;

  @override
  Future<Result<void, DatabaseFailure>> renameSpeaker({
    required String recordingId,
    required String oldSpeakerId,
    required String newSpeakerId,
  }) async {
    lastRenamedOldSpeaker = oldSpeakerId;
    lastRenamedNewSpeaker = newSpeakerId;
    return const Result.success(null);
  }

  @override
  Future<Result<void, DatabaseFailure>> updateRecordingTitle({
    required String recordingId,
    required String newTitle,
  }) async {
    lastUpdatedRecordingId = recordingId;
    lastUpdatedTitle = newTitle;
    return const Result.success(null);
  }
}

void main() {
  final testRecording = RecordingSummary(
    id: 'rec_player_001',
    title: 'Product Brainstorm: On-Device Voice AI',
    createdAt: DateTime(2026, 11, 8, 10, 0),
    durationSeconds: 120,
    transcriptSnippet:
        'Discussing the privacy benefits of 100% offline edge transcription.',
    speakers: const ['Ange', 'Elena'],
    tags: const ['#AI', '#Privacy'],
    isFavorite: true,
    audioFilePath: '/vault/rec_player_001.wav',
  );

  final testSegments = [
    const TranscriptSegment(
      id: 'seg_1',
      recordingId: 'rec_player_001',
      startMs: 0,
      endMs: 5000,
      speakerId: 'Ange',
      text: 'Good morning Elena. Let us review the edge AI privacy specs.',
    ),
    const TranscriptSegment(
      id: 'seg_2',
      recordingId: 'rec_player_001',
      startMs: 5200,
      endMs: 12000,
      speakerId: 'Elena',
      text: 'All raw audio samples stay in RAM and are discarded after transcription.',
    ),
  ];

  group('PlayerScreen Widget Tests', () {
    late MockRecordingRepository repository;
    late FakeAudioPlayerService fakePlayer;

    setUp(() {
      repository = MockRecordingRepository();
      fakePlayer = FakeAudioPlayerService();
    });

    tearDown(() async {
      await fakePlayer.dispose();
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: PlayerScreen(
          recording: testRecording,
          initialSegments: testSegments,
          playerService: fakePlayer,
          repository: repository,
        ),
      );
    }

    testWidgets('renders recording title, duration, waveform, and segments', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Product Brainstorm: On-Device Voice AI'), findsOneWidget);
      expect(find.text('02:00'), findsNWidgets(2));
      expect(find.byType(ScrubbableWaveformTrack), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.text('Attributed Transcript'), findsOneWidget);
      expect(find.text('2 segments'), findsOneWidget);
      expect(find.byType(TranscriptSegmentTile), findsNWidgets(2));
      expect(find.text('Ange'), findsOneWidget);
      expect(find.text('Elena'), findsOneWidget);
      expect(
        find.text('Good morning Elena. Let us review the edge AI privacy specs.'),
        findsOneWidget,
      );
    });

    testWidgets('cycles playback speed on button press', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('1.0x'));
      await tester.pump();
      expect(find.text('1.25x'), findsOneWidget);
      expect(fakePlayer.playbackRate, 1.25);

      await tester.tap(find.text('1.25x'));
      await tester.pump();
      expect(find.text('1.5x'), findsOneWidget);
      expect(fakePlayer.playbackRate, 1.5);

      await tester.tap(find.text('1.5x'));
      await tester.pump();
      expect(find.text('2.0x'), findsOneWidget);
      expect(fakePlayer.playbackRate, 2.0);

      await tester.tap(find.text('2.0x'));
      await tester.pump();
      expect(find.text('1.0x'), findsOneWidget);
      expect(fakePlayer.playbackRate, 1.0);
    });

    testWidgets('toggles play and pause state', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(fakePlayer.isPlaying, isTrue);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();

      expect(fakePlayer.isPlaying, isFalse);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('tapping transcript segment seeks player to segment start time', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.text('All raw audio samples stay in RAM and are discarded after transcription.'),
      );
      await tester.pump();

      expect(fakePlayer.currentPosition, const Duration(milliseconds: 5200));
      expect(fakePlayer.isPlaying, isTrue);
    });

    testWidgets('speaker rename dialog updates speaker across transcript segments', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.edit_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Rename Speaker'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Architect Ange');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Architect Ange'), findsOneWidget);
      expect(find.text('Renamed "Ange" to "Architect Ange"'), findsOneWidget);
      expect(repository.lastRenamedOldSpeaker, 'Ange');
      expect(repository.lastRenamedNewSpeaker, 'Architect Ange');

      ScaffoldMessenger.of(
        tester.element(find.byType(PlayerScreen)),
      ).clearSnackBars();
      await tester.pump();
    });

    testWidgets('export menu displays formats and triggers preview modal for SRT', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.ios_share_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Export Subtitles (.SRT)'), findsOneWidget);
      expect(find.text('Export Plain Text (.TXT)'), findsOneWidget);
      expect(find.text('Export Audio (.WAV)'), findsOneWidget);

      await tester.tap(find.text('Export Subtitles (.SRT)'));
      await tester.pumpAndSettle();

      expect(find.text('Exported .SRT (2 segments)'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Exported .SRT'), findsOneWidget);
      expect(find.textContaining('00:00:00,000 --> 00:00:05,000'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Exported .SRT'), findsNothing);

      ScaffoldMessenger.of(
        tester.element(find.byType(PlayerScreen)),
      ).clearSnackBars();
      await tester.pump();
    });
  });
}
