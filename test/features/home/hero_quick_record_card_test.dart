import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/home/presentation/widgets/hero_quick_record_card.dart';

void main() {
  Widget createWidgetUnderTest({
    bool isRecording = false,
    VoidCallback? onRecordTap,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: HeroQuickRecordCard(
            isRecording: isRecording,
            onRecordTap: onRecordTap ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('HeroQuickRecordCard renders greeting, audio specs, and mic icon when idle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest(isRecording: false));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Greeting
    expect(find.text('Capture your mind'), findsOneWidget);

    // Verify Badge & Specs
    expect(find.text('PRO AUDIO STUDIO'), findsOneWidget);
    expect(find.text('48 kHz • 24-bit PCM'), findsOneWidget);

    // Verify Mic button icon
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('HeroQuickRecordCard triggers onRecordTap callback when tapped', (
    WidgetTester tester,
  ) async {
    bool recordTapped = false;

    await tester.pumpWidget(
      createWidgetUnderTest(
        isRecording: false,
        onRecordTap: () {
          recordTapped = true;
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(recordTapped, isTrue);
  });

  testWidgets('HeroQuickRecordCard renders stop icon and active recording badge when active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest(isRecording: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('RECORDING LIVE'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });
}
