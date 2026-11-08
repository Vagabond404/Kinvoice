import 'package:flutter/foundation.dart';
import '../../domain/models/recording_summary.dart';

/// State management ViewModel for the Kinvoice Home / Timeline screen.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({List<RecordingSummary>? initialRecordings}) {
    _recordings = initialRecordings ?? _createInitialMockRecordings();
  }

  late List<RecordingSummary> _recordings;
  String _selectedFilter = 'All';
  String? _activePlayingId;
  bool _isPlaying = false;
  bool _isRecording = false;

  final List<String> availableFilters = const [
    'All',
    'Today',
    'This Week',
    'Favorites',
    'Meetings',
    'Ideas',
  ];

  // Getters
  List<RecordingSummary> get allRecordings => List.unmodifiable(_recordings);
  String get selectedFilter => _selectedFilter;
  String? get activePlayingId => _activePlayingId;
  bool get isPlaying => _isPlaying;
  bool get isRecording => _isRecording;

  /// Returns the recordings filtered according to [_selectedFilter].
  List<RecordingSummary> get filteredRecordings {
    final now = DateTime.now();

    return _recordings.where((recording) {
      return switch (_selectedFilter) {
        'All' => true,
        'Favorites' => recording.isFavorite,
        'Today' =>
          recording.createdAt.year == now.year &&
              recording.createdAt.month == now.month &&
              recording.createdAt.day == now.day,
        'This Week' => now.difference(recording.createdAt).inDays <= 7,
        'Meetings' => recording.tags.any(
          (tag) =>
              tag.toLowerCase().contains('meeting') ||
              tag.toLowerCase().contains('work'),
        ),
        'Ideas' => recording.tags.any(
          (tag) =>
              tag.toLowerCase().contains('idea') ||
              tag.toLowerCase().contains('creative'),
        ),
        _ => true,
      };
    }).toList();
  }

  /// Updates the active category/time filter.
  void selectFilter(String filter) {
    if (_selectedFilter != filter) {
      _selectedFilter = filter;
      notifyListeners();
    }
  }

  /// Toggles favorite status for a given recording ID.
  void toggleFavorite(String id) {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final current = _recordings[index];
      _recordings[index] = current.copyWith(isFavorite: !current.isFavorite);
      notifyListeners();
    }
  }

  /// Toggles simulated playback for a given recording item.
  void togglePlay(String id) {
    if (_activePlayingId == id && _isPlaying) {
      _isPlaying = false;
    } else {
      _activePlayingId = id;
      _isPlaying = true;
    }
    notifyListeners();
  }

  /// Toggles the live recording studio action.
  void toggleRecording() {
    _isRecording = !_isRecording;
    notifyListeners();
  }

  /// Seeds 5 realistic recordings matching Kinvoice master specifications.
  static List<RecordingSummary> _createInitialMockRecordings() {
    final now = DateTime.now();

    return [
      RecordingSummary(
        id: 'rec_001',
        title: 'Weekend market reimbursement & Tuk-tuk',
        createdAt: now.subtract(const Duration(minutes: 42)),
        durationSeconds: 184, // 03:04
        transcriptSnippet:
            'Your mother agreed to reimburse you 5,800 KHR for the tuk-tuk ride back from The River Gallery.',
        speakers: const ['Mom', 'Ange'],
        tags: const ['#Personal', '#Expenses'],
        isFavorite: true,
        audioFilePath: '/storage/recordings/rec_001.wav',
      ),
      RecordingSummary(
        id: 'rec_002',
        title: 'Acoustic ONNX VAD & Audio Isolate Latency',
        createdAt: now.subtract(const Duration(hours: 3, minutes: 15)),
        durationSeconds: 412, // 06:52
        transcriptSnippet:
            'Verified Silero VAD frame slicing running under 4ms latency inside background Dart isolate with zero UI frame drops.',
        speakers: const ['Karusak', 'Ange'],
        tags: const ['#Work', '#Engineering'],
        isFavorite: false,
        audioFilePath: '/storage/recordings/rec_002.wav',
      ),
      RecordingSummary(
        id: 'rec_003',
        title: 'Cambodian Silk Farm Strategy & Export',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        durationSeconds: 895, // 14:55
        transcriptSnippet:
            'Discussed local artisan weaving timelines, export logistics for natural dyes, and packaging prototypes for the European market.',
        speakers: const ['Karusak', 'Client', 'Ange'],
        tags: const ['#Meeting', '#Work'],
        isFavorite: false,
        audioFilePath: '/storage/recordings/rec_003.wav',
      ),
      RecordingSummary(
        id: 'rec_004',
        title: 'Spatial Audio Bookmarks Concept',
        createdAt: now.subtract(const Duration(days: 2, hours: 5)),
        durationSeconds: 92, // 01:32
        transcriptSnippet:
            'Concept for tapping audio waveform nodes to create instantaneous 3D spatial sound markers and word-level timestamps.',
        speakers: const ['Ange'],
        tags: const ['#Idea', '#Creative'],
        isFavorite: true,
        audioFilePath: '/storage/recordings/rec_004.wav',
      ),
      RecordingSummary(
        id: 'rec_005',
        title: 'Family recipe: Amok Fish & Lemongrass',
        createdAt: now.subtract(const Duration(days: 4, hours: 1)),
        durationSeconds: 340, // 05:40
        transcriptSnippet:
            'Fresh kroeung paste preparation: lemongrass, galangal, kaffir lime leaves, and rich coconut cream steamed in banana leaves.',
        speakers: const ['Mom'],
        tags: const ['#Family', '#Recipe'],
        isFavorite: true,
        audioFilePath: '/storage/recordings/rec_005.wav',
      ),
    ];
  }
}
