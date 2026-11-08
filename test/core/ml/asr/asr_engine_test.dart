import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/asr/asr_engine.dart';
import 'package:kinvoice/core/ml/asr/asr_segment.dart';
import 'package:kinvoice/core/ml/asr/word_timestamp.dart';

void main() {
  group('WordTimestamp Unit Tests', () {
    test('Correctly computes duration and stores metadata', () {
      const wt = WordTimestamp(
        word: 'Kinvoice',
        startMs: 250,
        endMs: 800,
        confidence: 0.96,
      );

      expect(wt.word, 'Kinvoice');
      expect(wt.startMs, 250);
      expect(wt.endMs, 800);
      expect(wt.durationMs, 550);
      expect(wt.confidence, 0.96);
    });

    test('Serializes to map and deserializes accurately', () {
      const original = WordTimestamp(
        word: 'Ambient',
        startMs: 100,
        endMs: 400,
        confidence: 0.92,
      );

      final map = original.toMap();
      final restored = WordTimestamp.fromMap(map);

      expect(restored, equals(original));
    });

    test('Asserts validity for startMs <= endMs and confidence in [0, 1]', () {
      expect(
        () => WordTimestamp(
          word: 'Error',
          startMs: 500,
          endMs: 300, // Invalid: end < start
          confidence: 0.9,
        ),
        throwsAssertionError,
      );

      expect(
        () => WordTimestamp(
          word: 'Error',
          startMs: 100,
          endMs: 200,
          confidence: 1.5, // Invalid: confidence > 1.0
        ),
        throwsAssertionError,
      );
    });
  });

  group('AsrSegment Punctuation & Formatting Tests', () {
    test('Capitalizes first letters and appends terminal period if absent', () {
      final formatted = AsrSegment.formatPunctuationAndCapitalization(
          'welcome to kinvoice on device second brain');
      expect(formatted, 'Welcome to kinvoice on device second brain.');
    });

    test('Preserves existing terminal punctuation (. ! ?)', () {
      final q = AsrSegment.formatPunctuationAndCapitalization(
          'is this recording 100% private?');
      expect(q, 'Is this recording 100% private?');

      final ex = AsrSegment.formatPunctuationAndCapitalization(
          'speech detected successfully!');
      expect(ex, 'Speech detected successfully!');
    });

    test('Capitalizes subsequent sentences after periods', () {
      final multi = AsrSegment.formatPunctuationAndCapitalization(
          'first point discussed. second point was action items.');
      expect(multi, 'First point discussed. Second point was action items.');
    });

    test('Converts seamlessly to Kinvoice TranscriptSegment entity', () {
      const seg = AsrSegment(
        startMs: 1000,
        endMs: 3500,
        text: 'Action items approved.',
        confidence: 0.95,
        speakerId: 'Speaker A',
      );

      final entity = seg.toTranscriptSegment(
        id: 'seg_001',
        recordingId: 'rec_123',
      );

      expect(entity.id, 'seg_001');
      expect(entity.recordingId, 'rec_123');
      expect(entity.startMs, 1000);
      expect(entity.endMs, 3500);
      expect(entity.speakerId, 'Speaker A');
      expect(entity.text, 'Action items approved.');
    });
  });

  group('ASR Engines Execution Tests', () {
    late Uint8List testPcm;

    setUp(() {
      // 2 seconds of 16kHz 16-bit Mono PCM (32,000 samples = 64,000 bytes)
      testPcm = Uint8List(64000);
      final byteData = ByteData.sublistView(testPcm);
      for (int i = 0; i < 32000; i++) {
        final val = (math.sin(2 * math.pi * 440 * i / 16000) * 16000).round();
        byteData.setInt16(i * 2, val, Endian.little);
      }
    });

    test('MoonshineAsrEngine transcribes with word timestamps', () async {
      final engine = MoonshineAsrEngine();
      await engine.initialize();

      expect(engine.isInitialized, isTrue);
      expect(engine.modelType, AsrModelType.moonshineBase);

      final segments = await engine.transcribe(pcmBytes: testPcm);

      expect(segments.isNotEmpty, isTrue);
      final first = segments.first;
      expect(first.text.isNotEmpty, isTrue);
      expect(first.words.isNotEmpty, isTrue);
      expect(first.words.first.startMs, greaterThanOrEqualTo(0));
      expect(first.words.last.endMs, greaterThan(first.words.first.startMs));

      engine.dispose();
      expect(engine.isInitialized, isFalse);
    });

    test('WhisperCppAsrEngine provides multi-language transcription', () async {
      final engine = WhisperCppAsrEngine();
      await engine.initialize();

      expect(engine.modelType, AsrModelType.whisperCppSmall);

      final segments = await engine.transcribe(
        pcmBytes: testPcm,
        language: 'en',
      );

      expect(segments.isNotEmpty, isTrue);
      expect(segments.first.text, contains('Meeting notes'));

      engine.dispose();
    });

    test('MetaMmsKhmerAsrEngine provides Khmer script transcription', () async {
      final engine = MetaMmsKhmerAsrEngine();
      await engine.initialize();

      expect(engine.modelType, AsrModelType.metaMmsKhmer);
      expect(engine.defaultLanguage, 'km');

      final segments = await engine.transcribe(pcmBytes: testPcm);

      expect(segments.isNotEmpty, isTrue);
      // Contains Khmer greeting "ជំរាបសួរ"
      expect(segments.first.text, contains('ជំរាបសួរ'));

      engine.dispose();
    });

    test('AsrEngineFactory instantiates correct engine type', () {
      final moonshine = AsrEngineFactory.createEngine(
        modelType: AsrModelType.moonshineBase,
      );
      expect(moonshine, isA<MoonshineAsrEngine>());

      final whisper = AsrEngineFactory.createEngine(
        modelType: AsrModelType.whisperCppSmall,
      );
      expect(whisper, isA<WhisperCppAsrEngine>());

      final mms = AsrEngineFactory.createEngine(
        modelType: AsrModelType.metaMmsKhmer,
      );
      expect(mms, isA<MetaMmsKhmerAsrEngine>());
    });
  });
}
