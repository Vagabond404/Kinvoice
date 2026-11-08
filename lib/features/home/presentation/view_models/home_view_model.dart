import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/database/recording_repository.dart';
import '../../../../core/services/recording_storage_service.dart';
import '../../domain/models/recording_summary.dart';

/// State management ViewModel for the Kinvoice Home / Timeline screen.
/// Streams and manages real recordings persisted in SQLite and local storage.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    List<RecordingSummary>? initialRecordings,
    RecordingRepository? repository,
    AudioPlayerService? playerService,
    RecordingStorageService? storageService,
    bool autoLoadFromDatabase = true,
  })  : _recordings = List<RecordingSummary>.from(initialRecordings ?? const []),
        _repository = repository,
        _playerService = playerService,
        _storageService = storageService ?? RecordingStorageService.instance,
        _enableNativeAudioPlayback =
            autoLoadFromDatabase || playerService != null {
    _dbChangesSub = RecordingRepository.changes.listen((_) {
      loadRecordings();
    });

    if (autoLoadFromDatabase && initialRecordings == null) {
      loadRecordings();
    }
  }

  List<RecordingSummary> _recordings;
  final RecordingRepository? _repository;
  AudioPlayerService? _playerService;
  final RecordingStorageService _storageService;
  final bool _enableNativeAudioPlayback;

  StreamSubscription<void>? _dbChangesSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  String _selectedFilter = 'All';
  String? _activePlayingId;
  bool _isPlaying = false;
  bool _isRecording = false;
  bool _isLoading = false;

  final List<String> availableFilters = const [
    'All',
    'Today',
    'This Week',
    'Favorites',
    'Meetings',
    'Ideas',
    'Personal',
    'Projects',
  ];

  // Getters
  List<RecordingSummary> get allRecordings => List.unmodifiable(_recordings);
  String get selectedFilter => _selectedFilter;
  String? get activePlayingId => _activePlayingId;
  bool get isPlaying => _isPlaying;
  bool get isRecording => _isRecording;
  bool get isLoading => _isLoading;

  RecordingRepository get _resolvedRepository =>
      _repository ?? RecordingRepository();

  AudioPlayerService get _resolvedPlayerService {
    if (_playerService == null) {
      _playerService = AudioPlayerService();
      _playerStateSub = _playerService!.playerStateStream.listen((state) {
        if (state == PlayerState.completed || state == PlayerState.stopped) {
          _isPlaying = false;
          _activePlayingId = null;
          notifyListeners();
        } else if (state == PlayerState.paused) {
          _isPlaying = false;
          notifyListeners();
        } else if (state == PlayerState.playing) {
          _isPlaying = true;
          notifyListeners();
        }
      });
    }
    return _playerService!;
  }

  /// Loads all saved recordings from SQLite ordered chronologically (newest first).
  Future<void> loadRecordings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _resolvedRepository.getAllRecordings();
      result.fold(
        onSuccess: (items) {
          _recordings = items;
        },
        onError: (_) {},
      );
    } catch (_) {
      // Ignore database initialization errors in pure widget test environments without FFI
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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
        'Personal' => recording.tags.any(
          (tag) => tag.toLowerCase().contains('personal'),
        ),
        'Projects' => recording.tags.any(
          (tag) => tag.toLowerCase().contains('project'),
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

  /// Toggles favorite status for a given recording ID and persists to SQLite.
  Future<void> toggleFavorite(String id) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final current = _recordings[index];
      final newFav = !current.isFavorite;
      _recordings[index] = current.copyWith(isFavorite: newFav);
      notifyListeners();

      try {
        await _resolvedRepository.updateFavoriteStatus(
          recordingId: id,
          isFavorite: newFav,
        );
      } catch (_) {}
    }
  }

  /// Plays or pauses the actual local audio file for a given recording item.
  Future<void> togglePlay(String id) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final recording = _recordings[index];

    if (_activePlayingId == id && _isPlaying) {
      _isPlaying = false;
      notifyListeners();
      if (_enableNativeAudioPlayback) {
        try {
          await _resolvedPlayerService.pause();
        } catch (_) {}
      }
    } else {
      final previousId = _activePlayingId;
      _activePlayingId = id;
      _isPlaying = true;
      notifyListeners();

      if (_enableNativeAudioPlayback) {
        try {
          if (previousId == id) {
            await _resolvedPlayerService.resume();
          } else {
            await _resolvedPlayerService.stop();
            await _resolvedPlayerService.play(recording.audioFilePath);
          }
        } catch (_) {}
      }
    }
  }

  /// Stops active audio playback if any.
  Future<void> stopPlayback() async {
    if (_isPlaying || _activePlayingId != null) {
      _isPlaying = false;
      _activePlayingId = null;
      notifyListeners();
      try {
        await _playerService?.stop();
      } catch (_) {}
    }
  }

  /// Renames a recording in state and SQLite.
  Future<void> renameRecording(String id, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;

    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      _recordings[index] = _recordings[index].copyWith(title: trimmed);
      notifyListeners();
    }

    try {
      await _resolvedRepository.updateRecordingTitle(
        recordingId: id,
        newTitle: trimmed,
      );
    } catch (_) {}
  }

  /// Deletes a recording from SQLite and removes its physical audio file from storage.
  Future<void> deleteRecording(String id) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    String? filePath;
    if (index != -1) {
      filePath = _recordings[index].audioFilePath;
      _recordings.removeAt(index);
      if (_activePlayingId == id) {
        _isPlaying = false;
        _activePlayingId = null;
        try {
          await _playerService?.stop();
        } catch (_) {}
      }
      notifyListeners();
    }

    if (filePath != null && filePath.isNotEmpty) {
      await _storageService.deleteAudioFile(filePath);
    }

    try {
      await _resolvedRepository.deleteRecording(id);
    } catch (_) {}
  }

  /// Toggles the live recording studio action.
  void toggleRecording() {
    _isRecording = !_isRecording;
    notifyListeners();
  }

  @override
  void dispose() {
    _dbChangesSub?.cancel();
    _playerStateSub?.cancel();
    _playerService?.dispose();
    super.dispose();
  }
}
