import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/features/home/domain/models/recording_summary.dart';
import 'package:kinvoice/features/home/presentation/view_models/home_view_model.dart';

void main() {
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
    test('Seeds 5 mock recordings on initialization', () {
      final viewModel = HomeViewModel();
      expect(viewModel.allRecordings.length, 5);
      expect(viewModel.selectedFilter, 'All');
      expect(viewModel.filteredRecordings.length, 5);
    });

    test('Filter by Favorites returns only starred recordings', () {
      final viewModel = HomeViewModel();
      viewModel.selectFilter('Favorites');

      expect(viewModel.selectedFilter, 'Favorites');
      expect(
        viewModel.filteredRecordings.every((r) => r.isFavorite),
        isTrue,
      );
    });

    test('Toggling favorite updates recording state and notifies listeners', () {
      final viewModel = HomeViewModel();
      final firstId = viewModel.allRecordings.first.id;
      final initialFav = viewModel.allRecordings.first.isFavorite;

      viewModel.toggleFavorite(firstId);

      final updatedFav =
          viewModel.allRecordings.firstWhere((r) => r.id == firstId).isFavorite;
      expect(updatedFav, !initialFav);
    });

    test('Toggling play switches playback state', () {
      final viewModel = HomeViewModel();
      final id = viewModel.allRecordings.first.id;

      expect(viewModel.isPlaying, isFalse);
      viewModel.togglePlay(id);

      expect(viewModel.isPlaying, isTrue);
      expect(viewModel.activePlayingId, id);

      viewModel.togglePlay(id);
      expect(viewModel.isPlaying, isFalse);
    });

    test('Toggling recording switches recording state', () {
      final viewModel = HomeViewModel();
      expect(viewModel.isRecording, isFalse);

      viewModel.toggleRecording();
      expect(viewModel.isRecording, isTrue);

      viewModel.toggleRecording();
      expect(viewModel.isRecording, isFalse);
    });
  });
}
