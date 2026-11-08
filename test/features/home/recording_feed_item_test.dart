import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/home/presentation/widgets/recording_feed_item.dart';

void main() {
  final sampleRecording = RecordingSummary(
    id: 'rec_test_1',
    title: 'Sprint Architecture Sync',
    createdAt: DateTime(2026, 11, 8, 10, 30),
    durationSeconds: 184, // 03:04
    transcriptSnippet: 'Discussed isolate latency and ONNX Runtime performance.',
    speakers: const ['Ange', 'Karusak'],
    tags: const ['#Work', '#Audio'],
    isFavorite: false,
    audioFilePath: '/storage/recordings/test.wav',
  );

  Widget createWidgetUnderTest({
    required RecordingSummary recording,
    bool isPlaying = false,
    VoidCallback? onFavoriteToggle,
    VoidCallback? onPlayToggle,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: RecordingFeedItem(
          recording: recording,
          isPlaying: isPlaying,
          onFavoriteToggle: onFavoriteToggle ?? () {},
          onPlayToggle: onPlayToggle ?? () {},
        ),
      ),
    );
  }

  testWidgets('RecordingFeedItem displays metadata, duration, tags, and waveform', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest(recording: sampleRecording));
    await tester.pumpAndSettle();

    // Verify Title and Transcript
    expect(find.text('Sprint Architecture Sync'), findsOneWidget);
    expect(
      find.text('Discussed isolate latency and ONNX Runtime performance.'),
      findsOneWidget,
    );

    // Verify Duration formatted as mm:ss
    expect(find.text('03:04'), findsOneWidget);

    // Verify Speaker count
    expect(find.text('2 Speakers'), findsOneWidget);

    // Verify Tags
    expect(find.text('#Work'), findsOneWidget);
    expect(find.text('#Audio'), findsOneWidget);

    // Verify Mini Waveform CustomPaint exists
    expect(find.byType(CustomPaint), findsWidgets);

    // Verify idle play icon
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Verify star outline (not favorite)
    expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
  });

  testWidgets('RecordingFeedItem invokes onFavoriteToggle on star tap', (
    WidgetTester tester,
  ) async {
    bool favoriteTapped = false;

    await tester.pumpWidget(
      createWidgetUnderTest(
        recording: sampleRecording,
        onFavoriteToggle: () {
          favoriteTapped = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_outline_rounded));
    await tester.pump();

    expect(favoriteTapped, isTrue);
  });

  testWidgets('RecordingFeedItem displays active pause icon and triggers onPlayToggle', (
    WidgetTester tester,
  ) async {
    bool playTapped = false;

    await tester.pumpWidget(
      createWidgetUnderTest(
        recording: sampleRecording,
        isPlaying: true,
        onPlayToggle: () {
          playTapped = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Verify active pause icon
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();

    expect(playTapped, isTrue);
  });
}
