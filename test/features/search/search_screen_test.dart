import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ai/vector_search/hybrid_search_engine.dart';
import 'package:kinvoice/core/theme/app_theme.dart';
import 'package:kinvoice/features/search/presentation/screens/search_screen.dart';

class FakeHybridSearchEngine extends Fake implements HybridSearchEngine {
  @override
  Future<HybridSearchResponse> search({
    required String query,
    int limit = 6,
    double semanticWeight = 0.65,
  }) async {
    if (query.trim().isEmpty) {
      return const HybridSearchResponse(
        query: '',
        generativeSummary: '',
        citations: [],
        results: [],
      );
    }

    return HybridSearchResponse(
      query: query,
      generativeSummary:
          'Based on your spoken notes from "Marketing Sync" with Speaker A: At 00:14, Speaker A noted: "Approved the marketing budget."',
      citations: const [
        CitationChip(
          recordingId: 'rec_fake_01',
          recordingTitle: 'Marketing Sync',
          speakerId: 'Speaker A',
          startMs: 14000,
          endMs: 32000,
          snippet: 'Approved the marketing budget.',
        ),
      ],
      results: const [
        HybridSearchResult(
          recordingId: 'rec_fake_01',
          recordingTitle: 'Marketing Sync',
          segmentId: 'seg_fake_01',
          startMs: 14000,
          endMs: 32000,
          speakerId: 'Speaker A',
          text: 'Approved the marketing budget.',
          audioFilePath: 'fake_audio.wav',
          semanticScore: 0.92,
          keywordScore: 0.88,
          combinedScore: 0.91,
        ),
      ],
    );
  }
}

void main() {
  group('SearchScreen & Ask Memory Widget Tests', () {
    late FakeHybridSearchEngine fakeEngine;

    setUp(() {
      fakeEngine = FakeHybridSearchEngine();
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: SearchScreen(searchEngine: fakeEngine),
      );
    }

    testWidgets('renders conversational search bar, filter chips, and suggested inquiries', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Ask Your Memory'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All Notes'), findsOneWidget);
      expect(find.text('Decisions'), findsOneWidget);
      expect(find.text('Suggested Questions'), findsOneWidget);
    });

    testWidgets('tapping suggested inquiry triggers hybrid search and shows AI Answer card', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap suggested query
      final queryFinder = find.text(
        'What did I decide in yesterday\'s meeting about marketing?',
      );
      expect(queryFinder, findsOneWidget);
      await tester.tap(queryFinder);
      await tester.pumpAndSettle();

      // Generative Answer Card should appear
      expect(find.text('AI Answer Summary'), findsOneWidget);
      expect(find.text('all-MiniLM-L6-v2'), findsOneWidget);
      expect(
        find.textContaining('Approved the marketing budget'),
        findsWidgets,
      );

      // Citation Chip
      expect(find.text('Speaker A [00:14 - 00:32]'), findsOneWidget);

      // Embedded Audio Preview Player
      expect(find.text('Relevant Spoken Moments (1)'), findsOneWidget);
      expect(find.text('Play Audio Clip'), findsOneWidget);
      expect(find.text('91% Match'), findsOneWidget);

      // Tap citation chip
      await tester.tap(find.text('Speaker A [00:14 - 00:32]'));
      await tester.pump();
    });
  });
}
