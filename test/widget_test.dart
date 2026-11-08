import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/main.dart';

void main() {
  testWidgets('RootNavigationShell renders 3 tabs and switches screens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KinvoiceApp());
    await tester.pump(const Duration(milliseconds: 200));

    // Verify initial screen: HomeScreen (Timeline)
    expect(find.text('Kinvoice'), findsOneWidget);
    expect(find.text('Ambient Memory: Active'), findsOneWidget);

    // Verify bottom navigation bar destinations
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Ask Memory'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Switch to Tab 2: Ask Memory
    await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ask Your Memory'), findsOneWidget);
    expect(find.text('Suggested Questions'), findsOneWidget);

    // Switch to Tab 3: Settings
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Settings & Models'), findsOneWidget);
    expect(find.text('100% On-Device Privacy'), findsOneWidget);

    // Switch back to Tab 1: Timeline
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Kinvoice'), findsOneWidget);
  });
}
