import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/home/presentation/view_models/home_view_model.dart';

void main() {
  final sampleRecordings = [
    RecordingSummary(
      id: 'rec_001',
      title: 'Morning Standup Meeting',
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      durationSeconds: 184,
      transcriptSnippet: 'Reviewed sprint tasks and local ONNX pipeline.',
      speakers: const ['Speaker 1', 'Speaker 2'],
      tags: const ['#Meetings'],
      isFavorite: true,
      audioFilePath: '/storage/Kinvoice/Recordings/Kinvoice_Meetings_1.wav',
    ),
    RecordingSummary(
      id: 'rec_002',
      title: 'Product Feature Idea',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      durationSeconds: 95,
      transcriptSnippet: 'Voice note idea for spatial audio bookmarks.',
      speakers: const ['Speaker 1'],
      tags: const ['#Ideas'],
      isFavorite: false,
      audioFilePath: '/storage/Kinvoice/Recordings/Kinvoice_Ideas_2.wav',
    ),
  ];

  group('RecordingSummary Model Tests', () {
    test('formattedDuration handles minutes and seconds correctly', () {
      final summary = RecordingSummary(
        id: '1',
        title: 'Test',
        createdAt: DateTime.now(),
        durationSeconds: 65, // 01:05
        transcriptSnippet: 'Snippet',
        speakers: const ['Self'],
        tags: const ['#Tag'],
        isFavorite: false,
        audioFilePath: '/path/test.wav',
      );

      expect(summary.formattedDuration, '01:05');
    });

    test('copyWith properly updates selective attributes', () {
      final original = RecordingSummary(
        id: '1',
        title: 'Original',
        createdAt: DateTime.now(),
        durationSeconds: 120,
        transcriptSnippet: 'Snippet',
        speakers: const ['Mom'],
        tags: const ['#Family'],
        isFavorite: false,
        audioFilePath: '/path/test.wav',
      );

      final updated = original.copyWith(isFavorite: true, title: 'Updated');

      expect(updated.id, original.id);
      expect(updated.title, 'Updated');
      expect(updated.isFavorite, isTrue);
      expect(original.isFavorite, isFalse);
    });
  });

  group('HomeViewModel State Management Tests', () {
    test('Initializes with empty list when no recordings exist (zero mock data)', () {
      final viewModel = HomeViewModel(autoLoadFromDatabase: false);
      expect(viewModel.allRecordings, isEmpty);
      expect(viewModel.selectedFilter, 'All');
      expect(viewModel.filteredRecordings, isEmpty);
    });

    test('Filter by Favorites returns only starred recordings', () {
      final viewModel = HomeViewModel(
        initialRecordings: sampleRecordings,
        autoLoadFromDatabase: false,
      );
      viewModel.selectFilter('Favorites');

      expect(viewModel.selectedFilter, 'Favorites');
      expect(viewModel.filteredRecordings.length, 1);
      expect(
        viewModel.filteredRecordings.every((r) => r.isFavorite),
        isTrue,
      );
    });

    test('Toggling favorite updates recording state and notifies listeners', () async {
      final viewModel = HomeViewModel(
        initialRecordings: sampleRecordings,
        autoLoadFromDatabase: false,
      );
      final firstId = viewModel.allRecordings.first.id;
      final initialFav = viewModel.allRecordings.first.isFavorite;

      await viewModel.toggleFavorite(firstId);

      final updatedFav =
          viewModel.allRecordings.firstWhere((r) => r.id == firstId).isFavorite;
      expect(updatedFav, !initialFav);
    });

    test('Toggling play switches playback state', () async {
      final viewModel = HomeViewModel(
        initialRecordings: sampleRecordings,
        autoLoadFromDatabase: false,
      );
      final id = viewModel.allRecordings.first.id;

      expect(viewModel.isPlaying, isFalse);
      await viewModel.togglePlay(id);

      expect(viewModel.isPlaying, isTrue);
      expect(viewModel.activePlayingId, id);

      await viewModel.togglePlay(id);
      expect(viewModel.isPlaying, isFalse);
    });

    test('Renaming and deleting recording updates state', () async {
      final viewModel = HomeViewModel(
        initialRecordings: sampleRecordings,
        autoLoadFromDatabase: false,
      );

      await viewModel.renameRecording('rec_001', 'Updated Standup');
      expect(viewModel.allRecordings.first.title, 'Updated Standup');

      await viewModel.deleteRecording('rec_001');
      expect(viewModel.allRecordings.any((r) => r.id == 'rec_001'), isFalse);
    });

    test('Toggling recording switches recording state', () {
      final viewModel = HomeViewModel(autoLoadFromDatabase: false);
      expect(viewModel.isRecording, isFalse);

      viewModel.toggleRecording();
      expect(viewModel.isRecording, isTrue);

      viewModel.toggleRecording();
      expect(viewModel.isRecording, isFalse);
    });
  });
}
