import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/vad/silero_vad_engine.dart';
import 'package:kinvoice/core/ml/vad/speech_state_machine.dart';

void main() {
  group('SpeechStateMachine Unit Tests', () {
    late SpeechStateMachine machine;
    final dummyFrame = Uint8List(SileroVadEngine.frameBytes);

    setUp(() {
      machine = SpeechStateMachine(
        onsetProbabilityThreshold: 0.5,
        onsetConsecutiveFrames: 3,
        offsetProbabilityThreshold: 0.35,
        offsetSilenceDurationMs: 800, // 25 frames
        frameDurationMs: 32,
      );
    });

    test('Initial state is silence with zero active segments', () {
      expect(machine.state, SpeechState.silence);
      expect(machine.isSpeaking, isFalse);
    });

    test('Probability > 0.5 for 1 or 2 frames does not trigger speech onset', () {
      final seg1 = machine.processFrame(
        pcmChunk: dummyFrame,
        voiceProbability: 0.85,
      );
      expect(machine.state, SpeechState.silence);
      expect(seg1, isNull);

      final seg2 = machine.processFrame(
        pcmChunk: dummyFrame,
        voiceProbability: 0.72,
      );
      expect(machine.state, SpeechState.silence);
      expect(seg2, isNull);

      // Noise drops below threshold -> counter resets
      machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.1);
      expect(machine.state, SpeechState.silence);
    });

    test('Probability > 0.5 for 3 consecutive frames triggers speech onset', () {
      machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.7);
      machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.8);
      final seg = machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.9);

      expect(machine.state, SpeechState.speaking);
      expect(machine.isSpeaking, isTrue);
      expect(seg, isNull); // Still speaking, not finished
    });

    test('Brief silence pause (< 800ms / 25 frames) does not split speaking session', () {
      // 1. Trigger speech onset
      for (int i = 0; i < 3; i++) {
        machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.8);
      }
      expect(machine.isSpeaking, isTrue);

      // 2. Simulate 10 frames (~320ms) of natural silence pause
      for (int i = 0; i < 10; i++) {
        final seg = machine.processFrame(
          pcmChunk: dummyFrame,
          voiceProbability: 0.1,
        );
        expect(machine.isSpeaking, isTrue);
        expect(seg, isNull);
      }

      // 3. User resumes talking
      machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.85);
      expect(machine.isSpeaking, isTrue);
    });

    test('Sustained silence (800ms / 25 frames) triggers offset and produces valid SpeechSegment', () {
      // 1. Trigger speech onset (3 frames)
      for (int i = 0; i < 3; i++) {
        machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.85);
      }

      // 2. Speak for another 10 frames
      for (int i = 0; i < 10; i++) {
        machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.9);
      }
      expect(machine.isSpeaking, isTrue);

      // 3. Silence begins for 24 frames -> still speaking
      for (int i = 0; i < 24; i++) {
        final seg = machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.05);
        expect(machine.isSpeaking, isTrue);
        expect(seg, isNull);
      }

      // 4. 25th frame of silence (800ms achieved) -> speech offset triggered!
      final completedSegment = machine.processFrame(
        pcmChunk: dummyFrame,
        voiceProbability: 0.05,
      );

      expect(machine.state, SpeechState.silence);
      expect(machine.isSpeaking, isFalse);
      expect(completedSegment, isNotNull);

      // Verify WAV structure
      final wav = completedSegment!.wavBytes;
      expect(wav.length, greaterThan(44));
      // Standard RIFF header check: 'R','I','F','F'
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // Standard WAVE check: 'W','A','V','E'
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');

      // Verify duration calculation
      expect(completedSegment.duration.inMilliseconds, greaterThan(800));
    });

    test('flush() finalizes in-progress speech when interrupted', () {
      for (int i = 0; i < 3; i++) {
        machine.processFrame(pcmChunk: dummyFrame, voiceProbability: 0.8);
      }
      expect(machine.isSpeaking, isTrue);

      final flushed = machine.flush();
      expect(flushed, isNotNull);
      expect(machine.isSpeaking, isFalse);
    });
  });
}
