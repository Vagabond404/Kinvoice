import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../audio/wav_header_helper.dart';

/// Distinct conversational states recognized by the VAD state machine.
enum SpeechState {
  silence,
  speaking,
}

/// Completed speech segment automatically partitioned by the VAD state machine.
@immutable
class SpeechSegment {
  const SpeechSegment({
    required this.wavBytes,
    required this.duration,
    required this.sampleCount,
    required this.startTimestamp,
    required this.endTimestamp,
  });

  final Uint8List wavBytes;
  final Duration duration;
  final int sampleCount;
  final DateTime startTimestamp;
  final DateTime endTimestamp;

  @override
  String toString() =>
      'SpeechSegment(duration: ${duration.inMilliseconds}ms, bytes: ${wavBytes.length})';
}

/// State machine tracking voice activity probabilities over time.
/// Triggers speech onset on >0.5 prob for 3 consecutive frames (96ms).
/// Triggers speech offset on <0.35 prob for 800ms (25 consecutive frames).
class SpeechStateMachine {
  SpeechStateMachine({
    this.onsetProbabilityThreshold = 0.5,
    this.onsetConsecutiveFrames = 3,
    this.offsetProbabilityThreshold = 0.35,
    this.offsetSilenceDurationMs = 800,
    this.frameDurationMs = 32, // 512 samples at 16kHz = 32ms
    this.preBufferMaxFrames = 8, // Keep 256ms of leading context
  }) : offsetConsecutiveFrames = (offsetSilenceDurationMs / frameDurationMs).ceil();

  final double onsetProbabilityThreshold;
  final int onsetConsecutiveFrames;
  final double offsetProbabilityThreshold;
  final int offsetSilenceDurationMs;
  final int offsetConsecutiveFrames;
  final int frameDurationMs;
  final int preBufferMaxFrames;

  SpeechState _state = SpeechState.silence;
  int _consecutiveOnsetFrames = 0;
  int _consecutiveOffsetFrames = 0;

  DateTime? _speechStartTime;
  final List<Uint8List> _activeSegmentChunks = [];
  final List<Uint8List> _preBuffer = [];

  SpeechState get state => _state;
  bool get isSpeaking => _state == SpeechState.speaking;

  /// Feeds a 512-sample PCM chunk and its calculated voice probability.
  /// Returns a completed [SpeechSegment] if speech offset was just triggered, or null.
  SpeechSegment? processFrame({
    required Uint8List pcmChunk,
    required double voiceProbability,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();

    if (_state == SpeechState.silence) {
      // Maintain circular pre-buffer to capture leading speech attack/consonants
      _preBuffer.add(pcmChunk);
      if (_preBuffer.length > preBufferMaxFrames) {
        _preBuffer.removeAt(0);
      }

      if (voiceProbability > onsetProbabilityThreshold) {
        _consecutiveOnsetFrames++;
        if (_consecutiveOnsetFrames >= onsetConsecutiveFrames) {
          // Transition to Speaking
          _state = SpeechState.speaking;
          _speechStartTime = now.subtract(
            Duration(milliseconds: _consecutiveOnsetFrames * frameDurationMs),
          );
          _consecutiveOnsetFrames = 0;
          _consecutiveOffsetFrames = 0;

          // Prepend pre-buffer chunks to segment
          _activeSegmentChunks.clear();
          _activeSegmentChunks.addAll(_preBuffer);
          _preBuffer.clear();
          _activeSegmentChunks.add(pcmChunk);
        }
      } else {
        _consecutiveOnsetFrames = 0;
      }
      return null;
    } else {
      // Currently Speaking
      _activeSegmentChunks.add(pcmChunk);

      if (voiceProbability < offsetProbabilityThreshold) {
        _consecutiveOffsetFrames++;
        if (_consecutiveOffsetFrames >= offsetConsecutiveFrames) {
          // Transition to Silence -> Produce SpeechSegment
          _state = SpeechState.silence;
          final start = _speechStartTime ?? now;
          final end = now;
          final segment = _finalizeSegment(start, end);

          _activeSegmentChunks.clear();
          _speechStartTime = null;
          _consecutiveOffsetFrames = 0;
          _consecutiveOnsetFrames = 0;

          return segment;
        }
      } else {
        _consecutiveOffsetFrames = 0;
      }
      return null;
    }
  }

  SpeechSegment _finalizeSegment(DateTime start, DateTime end) {
    int totalPcmLength = 0;
    for (final chunk in _activeSegmentChunks) {
      totalPcmLength += chunk.length;
    }

    // Assemble complete RIFF WAV with standard 44-byte header
    final header = WavHeaderHelper.createWavHeader(
      pcmDataLength: totalPcmLength,
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
    );

    final wavBuilder = BytesBuilder(copy: false);
    wavBuilder.add(header);
    for (final chunk in _activeSegmentChunks) {
      wavBuilder.add(chunk);
    }

    final totalSamples = totalPcmLength ~/ 2;
    final durationMs = (totalSamples / 16.0).round();

    return SpeechSegment(
      wavBytes: wavBuilder.toBytes(),
      duration: Duration(milliseconds: durationMs),
      sampleCount: totalSamples,
      startTimestamp: start,
      endTimestamp: end,
    );
  }

  /// Forces finalization of active speech if any (e.g. on stream stop).
  SpeechSegment? flush() {
    if (_state == SpeechState.speaking && _activeSegmentChunks.isNotEmpty) {
      final now = DateTime.now();
      final segment = _finalizeSegment(_speechStartTime ?? now, now);
      reset();
      return segment;
    }
    reset();
    return null;
  }

  /// Resets state machine counters.
  void reset() {
    _state = SpeechState.silence;
    _consecutiveOnsetFrames = 0;
    _consecutiveOffsetFrames = 0;
    _speechStartTime = null;
    _activeSegmentChunks.clear();
    _preBuffer.clear();
  }
}
