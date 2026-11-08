import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/audio_recorder_service.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/recording/presentation/screens/recording_screen.dart';

void main() {
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
}
