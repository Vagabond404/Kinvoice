import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import '../utils/failure.dart';
import '../utils/result.dart';

/// Audio playback service handling local audio playback, position tracking,
/// millisecond seeking, and speed modulation.
class AudioPlayerService {
  AudioPlayerService({AudioPlayer? initialPlayer}) : _player = initialPlayer {
    if (_player != null) {
      _initListeners();
    }
  }

  AudioPlayer? _player;
  AudioPlayer get player {
    if (_player == null) {
      _player = AudioPlayer();
      _initListeners();
    }
    return _player!;
  }

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  double _playbackRate = 1.0;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  PlayerState get playerState => _playerState;
  bool get isPlaying => _playerState == PlayerState.playing;
  double get playbackRate => _playbackRate;

  void _initListeners() {
    final p = _player;
    if (p == null) return;

    _posSub = p.onPositionChanged.listen((pos) {
      _currentPosition = pos;
      _positionController.add(pos);
    });

    _durSub = p.onDurationChanged.listen((dur) {
      _totalDuration = dur;
      _durationController.add(dur);
    });

    _stateSub = p.onPlayerStateChanged.listen((state) {
      _playerState = state;
      _stateController.add(state);
    });
  }

  /// Starts playback of a local audio file with optional initial seek offset.
  Future<Result<void, AudioCaptureFailure>> play(
    String filePath, {
    Duration? initialPosition,
  }) async {
    try {
      await player.setPlaybackRate(_playbackRate);
      await player.play(DeviceFileSource(filePath));
      if (initialPosition != null) {
        await player.seek(initialPosition);
      }
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to start audio playback: $e', e, stack),
      );
    }
  }

  /// Pauses active playback.
  Future<Result<void, AudioCaptureFailure>> pause() async {
    try {
      await player.pause();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to pause playback: $e', e, stack),
      );
    }
  }

  /// Resumes paused playback.
  Future<Result<void, AudioCaptureFailure>> resume() async {
    try {
      await player.resume();
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to resume playback: $e', e, stack),
      );
    }
  }

  /// Stops playback.
  Future<Result<void, AudioCaptureFailure>> stop() async {
    try {
      await player.stop();
      _currentPosition = Duration.zero;
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to stop playback: $e', e, stack),
      );
    }
  }

  /// Seeks to an exact position with millisecond precision.
  Future<Result<void, AudioCaptureFailure>> seek(Duration position) async {
    try {
      await player.seek(position);
      _currentPosition = position;
      _positionController.add(position);
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to seek audio: $e', e, stack),
      );
    }
  }

  /// Sets the playback rate (e.g., 1.0, 1.25, 1.5, 2.0).
  Future<Result<void, AudioCaptureFailure>> setPlaybackRate(double rate) async {
    try {
      _playbackRate = rate;
      await player.setPlaybackRate(rate);
      return const Result.success(null);
    } catch (e, stack) {
      return Result.error(
        AudioCaptureFailure('Failed to set playback rate: $e', e, stack),
      );
    }
  }

  /// Cleans up subscriptions and audio player resources.
  Future<void> dispose() async {
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _stateSub?.cancel();
    await _player?.dispose();
    await _positionController.close();
    await _durationController.close();
    await _stateController.close();
  }
}
