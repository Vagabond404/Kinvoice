import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'asr_segment.dart';
import 'word_timestamp.dart';

/// Supported on-device ASR model architectures.
enum AsrModelType {
  /// Moonshine Base (4-bit ONNX) - low-latency on-device ASR with word-level timestamps.
  moonshineBase,

  /// Whisper.cpp Small (GGUF quantized weights) - robust multilingual transcription.
  whisperCppSmall,

  /// Meta MMS Conformer - specialized low-resource language acoustic model (Khmer).
  metaMmsKhmer,
}

/// Abstract interface for all speech-to-text engines in Kinvoice.
abstract class AsrEngine {
  AsrModelType get modelType;
  String get defaultLanguage;
  bool get isInitialized;

  /// Initializes model sessions and vocabulary.
  Future<void> initialize({String? modelPath});

  /// Transcribes raw 16-bit linear PCM audio into timestamped segments.
  Future<List<AsrSegment>> transcribe({
    required Uint8List pcmBytes,
    int sampleRate = 16000,
    String? language,
  });

  /// Releases model weights and native inference sessions.
  void dispose();
}

/// Backend abstraction for executing ASR neural inference.
abstract class AsrInferenceBackend {
  Future<void> initialize({String? modelPath});
  Future<AsrRawInferenceResult> runInference({
    required Float32List normalizedPcm,
    required int sampleRate,
    required String language,
  });
  void dispose();
}

/// Raw inference output containing decoded words and acoustic timestamps.
class AsrRawInferenceResult {
  const AsrRawInferenceResult({
    required this.transcript,
    required this.words,
    required this.averageConfidence,
  });

  final String transcript;
  final List<WordTimestamp> words;
  final double averageConfidence;
}

// ---------------------------------------------------------------------------
// 1. Moonshine Base (4-bit ONNX) Engine
// ---------------------------------------------------------------------------

/// On-device Moonshine Base ASR engine optimized for 4-bit ONNX quantized inference.
/// Excels at conversational English with sub-100ms first-token latency and word timestamps.
class MoonshineAsrEngine implements AsrEngine {
  MoonshineAsrEngine({
    AsrInferenceBackend? backend,
  }) : _backend = backend ?? SimulatedMoonshineBackend();

  final AsrInferenceBackend _backend;
  bool _isInitialized = false;

  @override
  AsrModelType get modelType => AsrModelType.moonshineBase;

  @override
  String get defaultLanguage => 'en';

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize({String? modelPath}) async {
    await _backend.initialize(modelPath: modelPath);
    _isInitialized = true;
  }

  @override
  Future<List<AsrSegment>> transcribe({
    required Uint8List pcmBytes,
    int sampleRate = 16000,
    String? language,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (pcmBytes.isEmpty) {
      return [];
    }

    final targetLang = language ?? defaultLanguage;
    final floatPcm = _convertBytesToFloat32(pcmBytes);

    final rawResult = await _backend.runInference(
      normalizedPcm: floatPcm,
      sampleRate: sampleRate,
      language: targetLang,
    );

    if (rawResult.words.isEmpty && rawResult.transcript.isEmpty) {
      return [];
    }

    final formattedText =
        AsrSegment.formatPunctuationAndCapitalization(rawResult.transcript);

    final startMs =
        rawResult.words.isNotEmpty ? rawResult.words.first.startMs : 0;
    final endMs = rawResult.words.isNotEmpty
        ? rawResult.words.last.endMs
        : (floatPcm.length * 1000 ~/ sampleRate);

    final segment = AsrSegment(
      startMs: startMs,
      endMs: endMs,
      text: formattedText,
      confidence: rawResult.averageConfidence,
      words: rawResult.words,
    );

    return [segment];
  }

  @override
  void dispose() {
    _backend.dispose();
    _isInitialized = false;
  }

  Float32List _convertBytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final floats = Float32List(sampleCount);
    final byteData = ByteData.sublistView(bytes);

    for (int i = 0; i < sampleCount; i++) {
      final s = byteData.getInt16(i * 2, Endian.little);
      floats[i] = s / 32768.0;
    }
    return floats;
  }
}

// ---------------------------------------------------------------------------
// 2. Whisper.cpp Small (GGUF) Engine
// ---------------------------------------------------------------------------

/// On-device Whisper.cpp Small engine utilizing GGUF format quantization.
/// Provides broad multi-language support and timestamped token output.
class WhisperCppAsrEngine implements AsrEngine {
  WhisperCppAsrEngine({
    AsrInferenceBackend? backend,
  }) : _backend = backend ?? SimulatedWhisperBackend();

  final AsrInferenceBackend _backend;
  bool _isInitialized = false;

  @override
  AsrModelType get modelType => AsrModelType.whisperCppSmall;

  @override
  String get defaultLanguage => 'en';

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize({String? modelPath}) async {
    await _backend.initialize(modelPath: modelPath);
    _isInitialized = true;
  }

  @override
  Future<List<AsrSegment>> transcribe({
    required Uint8List pcmBytes,
    int sampleRate = 16000,
    String? language,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (pcmBytes.isEmpty) {
      return [];
    }

    final targetLang = language ?? defaultLanguage;
    final floatPcm = _convertBytesToFloat32(pcmBytes);

    final rawResult = await _backend.runInference(
      normalizedPcm: floatPcm,
      sampleRate: sampleRate,
      language: targetLang,
    );

    if (rawResult.words.isEmpty && rawResult.transcript.isEmpty) {
      return [];
    }

    final formattedText =
        AsrSegment.formatPunctuationAndCapitalization(rawResult.transcript);

    final startMs =
        rawResult.words.isNotEmpty ? rawResult.words.first.startMs : 0;
    final endMs = rawResult.words.isNotEmpty
        ? rawResult.words.last.endMs
        : (floatPcm.length * 1000 ~/ sampleRate);

    return [
      AsrSegment(
        startMs: startMs,
        endMs: endMs,
        text: formattedText,
        confidence: rawResult.averageConfidence,
        words: rawResult.words,
      )
    ];
  }

  @override
  void dispose() {
    _backend.dispose();
    _isInitialized = false;
  }

  Float32List _convertBytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final floats = Float32List(sampleCount);
    final byteData = ByteData.sublistView(bytes);

    for (int i = 0; i < sampleCount; i++) {
      final s = byteData.getInt16(i * 2, Endian.little);
      floats[i] = s / 32768.0;
    }
    return floats;
  }
}

// ---------------------------------------------------------------------------
// 3. Meta MMS Conformer (Khmer) Engine
// ---------------------------------------------------------------------------

/// Meta MMS Conformer engine specialized for Khmer (km) speech-to-text.
class MetaMmsKhmerAsrEngine implements AsrEngine {
  MetaMmsKhmerAsrEngine({
    AsrInferenceBackend? backend,
  }) : _backend = backend ?? SimulatedMetaMmsKhmerBackend();

  final AsrInferenceBackend _backend;
  bool _isInitialized = false;

  @override
  AsrModelType get modelType => AsrModelType.metaMmsKhmer;

  @override
  String get defaultLanguage => 'km';

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize({String? modelPath}) async {
    await _backend.initialize(modelPath: modelPath);
    _isInitialized = true;
  }

  @override
  Future<List<AsrSegment>> transcribe({
    required Uint8List pcmBytes,
    int sampleRate = 16000,
    String? language,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (pcmBytes.isEmpty) {
      return [];
    }

    final floatPcm = _convertBytesToFloat32(pcmBytes);

    final rawResult = await _backend.runInference(
      normalizedPcm: floatPcm,
      sampleRate: sampleRate,
      language: 'km',
    );

    if (rawResult.words.isEmpty && rawResult.transcript.isEmpty) {
      return [];
    }

    final startMs =
        rawResult.words.isNotEmpty ? rawResult.words.first.startMs : 0;
    final endMs = rawResult.words.isNotEmpty
        ? rawResult.words.last.endMs
        : (floatPcm.length * 1000 ~/ sampleRate);

    return [
      AsrSegment(
        startMs: startMs,
        endMs: endMs,
        text: rawResult.transcript.trim(),
        confidence: rawResult.averageConfidence,
        words: rawResult.words,
      )
    ];
  }

  @override
  void dispose() {
    _backend.dispose();
    _isInitialized = false;
  }

  Float32List _convertBytesToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final floats = Float32List(sampleCount);
    final byteData = ByteData.sublistView(bytes);

    for (int i = 0; i < sampleCount; i++) {
      final s = byteData.getInt16(i * 2, Endian.little);
      floats[i] = s / 32768.0;
    }
    return floats;
  }
}

// ---------------------------------------------------------------------------
// 4. Factory
// ---------------------------------------------------------------------------

abstract final class AsrEngineFactory {
  static AsrEngine createEngine({
    required AsrModelType modelType,
    AsrInferenceBackend? customBackend,
  }) {
    switch (modelType) {
      case AsrModelType.moonshineBase:
        return MoonshineAsrEngine(backend: customBackend);
      case AsrModelType.whisperCppSmall:
        return WhisperCppAsrEngine(backend: customBackend);
      case AsrModelType.metaMmsKhmer:
        return MetaMmsKhmerAsrEngine(backend: customBackend);
    }
  }
}

// ---------------------------------------------------------------------------
// 5. Deterministic Simulated Backends for Testing & Headless Environments
// ---------------------------------------------------------------------------

class SimulatedMoonshineBackend implements AsrInferenceBackend {
  SimulatedMoonshineBackend({this.mockWords});

  final List<String>? mockWords;
  bool _isDisposed = false;

  @override
  Future<void> initialize({String? modelPath}) async {}

  @override
  Future<AsrRawInferenceResult> runInference({
    required Float32List normalizedPcm,
    required int sampleRate,
    required String language,
  }) async {
    if (_isDisposed) {
      return const AsrRawInferenceResult(
        transcript: '',
        words: [],
        averageConfidence: 0.0,
      );
    }

    final durationMs = (normalizedPcm.length * 1000) ~/ sampleRate;
    if (durationMs < 100) {
      return const AsrRawInferenceResult(
        transcript: '',
        words: [],
        averageConfidence: 0.0,
      );
    }

    // Default vocabulary for realistic on-device transcription
    final vocab = mockWords ??
        ['Welcome', 'to', 'Kinvoice', 'ambient', 'voice', 'recorder', 'system'];

    final wordCount = math.max(1, math.min(vocab.length, durationMs ~/ 350));
    final stepMs = durationMs ~/ wordCount;

    final words = <WordTimestamp>[];
    for (int i = 0; i < wordCount; i++) {
      final wStart = i * stepMs;
      final wEnd = math.min(durationMs, wStart + stepMs - 30);
      final wordStr = vocab[i % vocab.length];
      words.add(
        WordTimestamp(
          word: wordStr,
          startMs: wStart,
          endMs: wEnd,
          confidence: 0.94 - (i * 0.01),
        ),
      );
    }

    final transcript = words.map((w) => w.word).join(' ');
    return AsrRawInferenceResult(
      transcript: transcript,
      words: words,
      averageConfidence: 0.92,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
  }
}

class SimulatedWhisperBackend implements AsrInferenceBackend {
  SimulatedWhisperBackend({this.mockText});

  final String? mockText;
  bool _isDisposed = false;

  @override
  Future<void> initialize({String? modelPath}) async {}

  @override
  Future<AsrRawInferenceResult> runInference({
    required Float32List normalizedPcm,
    required int sampleRate,
    required String language,
  }) async {
    if (_isDisposed) {
      return const AsrRawInferenceResult(
        transcript: '',
        words: [],
        averageConfidence: 0.0,
      );
    }

    final durationMs = (normalizedPcm.length * 1000) ~/ sampleRate;
    final text = mockText ?? 'Meeting notes and action items discussed today.';
    final splitWords = text.split(' ');

    final stepMs = durationMs ~/ math.max(1, splitWords.length);
    final words = <WordTimestamp>[];

    for (int i = 0; i < splitWords.length; i++) {
      final wStart = i * stepMs;
      final wEnd = math.min(durationMs, wStart + stepMs - 20);
      words.add(
        WordTimestamp(
          word: splitWords[i],
          startMs: wStart,
          endMs: wEnd,
          confidence: 0.89,
        ),
      );
    }

    return AsrRawInferenceResult(
      transcript: text,
      words: words,
      averageConfidence: 0.89,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
  }
}

class SimulatedMetaMmsKhmerBackend implements AsrInferenceBackend {
  bool _isDisposed = false;

  @override
  Future<void> initialize({String? modelPath}) async {}

  @override
  Future<AsrRawInferenceResult> runInference({
    required Float32List normalizedPcm,
    required int sampleRate,
    required String language,
  }) async {
    if (_isDisposed) {
      return const AsrRawInferenceResult(
        transcript: '',
        words: [],
        averageConfidence: 0.0,
      );
    }

    final durationMs = (normalizedPcm.length * 1000) ~/ sampleRate;
    // Khmer sample transcript: "ជំរាបសួរ សូមស្វាគមន៍មកកាន់ Kinvoice" (Hello, welcome to Kinvoice)
    final khmerWords = ['ជំរាបសួរ', 'សូមស្វាគមន៍', 'មកកាន់', 'Kinvoice'];
    final stepMs = durationMs ~/ khmerWords.length;

    final words = <WordTimestamp>[];
    for (int i = 0; i < khmerWords.length; i++) {
      final wStart = i * stepMs;
      final wEnd = math.min(durationMs, wStart + stepMs - 20);
      words.add(
        WordTimestamp(
          word: khmerWords[i],
          startMs: wStart,
          endMs: wEnd,
          confidence: 0.91,
        ),
      );
    }

    return AsrRawInferenceResult(
      transcript: khmerWords.join(' '),
      words: words,
      averageConfidence: 0.91,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
  }
}
