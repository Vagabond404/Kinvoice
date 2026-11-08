import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../../../features/player/domain/models/transcript_segment.dart';
import '../../audio/wav_header_helper.dart';

/// Represents a speaker turn span produced by native Pyannote + ERes2Net/TitaNet diarization.
class NativeDiarizationTurn {
  const NativeDiarizationTurn({
    required this.startSec,
    required this.endSec,
    required this.speakerLabel,
  });

  final double startSec;
  final double endSec;
  final String speakerLabel;
}

/// Real native C++/ONNX speech recognition, VAD, and speaker diarization engine
/// powered by `sherpa_onnx`, plus optional Cloud Whisper (Groq / OpenAI) support.
class SherpaOnnxEngine {
  SherpaOnnxEngine._();

  static bool _bindingsInitialized = false;

  /// Initializes native `libsherpa-onnx-c-api` FFI bindings once per isolate.
  static bool ensureBindingsInitialized() {
    if (_bindingsInitialized) return true;
    try {
      sherpa.initBindings();
      _bindingsInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Converts 16-bit little-endian PCM bytes to normalized Float32List [-1.0, 1.0].
  static Float32List pcm16BytesToFloat32(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    final floats = Float32List(sampleCount);
    final byteData = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < sampleCount; i++) {
      floats[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return floats;
  }

  /// Checks whether a valid local ONNX ASR model is installed inside [modelsRootPath].
  static String? resolveInstalledAsrModelDir({
    required String modelsRootPath,
    required String preferredModelId,
    required String language,
  }) {
    final candidates = <String>[
      if (language == 'km') 'meta_mms_khmer',
      preferredModelId,
      'whisper_tiny',
      'whisper_base',
      'whisper_small',
      'moonshine_tiny',
      'moonshine_base',
      'sense_voice',
    ];

    for (final id in candidates) {
      if (id.isEmpty) continue;
      final dir = Directory('$modelsRootPath${Platform.pathSeparator}$id');
      if (!dir.existsSync()) continue;

      final tokens = File('${dir.path}${Platform.pathSeparator}tokens.txt');
      if (!tokens.existsSync() || tokens.lengthSync() < 100) continue;

      if (id.startsWith('whisper') || id == 'meta_mms_khmer') {
        final enc = File('${dir.path}${Platform.pathSeparator}encoder.onnx');
        final dec = File('${dir.path}${Platform.pathSeparator}decoder.onnx');
        if (enc.existsSync() && dec.existsSync()) {
          return id;
        }
      } else if (id.startsWith('moonshine')) {
        final pre = File('${dir.path}${Platform.pathSeparator}preprocess.onnx');
        final enc = File('${dir.path}${Platform.pathSeparator}encode.int8.onnx');
        final uncached =
            File('${dir.path}${Platform.pathSeparator}uncached_decode.int8.onnx');
        final cached =
            File('${dir.path}${Platform.pathSeparator}cached_decode.int8.onnx');
        if (pre.existsSync() &&
            enc.existsSync() &&
            uncached.existsSync() &&
            cached.existsSync()) {
          return id;
        }
      } else if (id == 'sense_voice') {
        final model =
            File('${dir.path}${Platform.pathSeparator}model.int8.onnx');
        if (model.existsSync()) {
          return id;
        }
      }
    }
    return null;
  }

  /// Executes full native ONNX pipeline (Silero VAD -> Pyannote/ERes2Net Diarization -> OfflineRecognizer ASR).
  /// Returns null if native bindings or local ONNX model files are not yet installed.
  static List<TranscriptSegment>? runNativePipeline({
    required String recordingId,
    required Uint8List pcmBytes,
    required String modelsRootPath,
    required String preferredModelId,
    required String language,
    double vadThreshold = 0.5,
    int sampleRate = 16000,
    void Function(double progress, String message)? onProgress,
  }) {
    final resolvedModelId = resolveInstalledAsrModelDir(
      modelsRootPath: modelsRootPath,
      preferredModelId: preferredModelId,
      language: language,
    );
    if (resolvedModelId == null) {
      return null;
    }

    if (!ensureBindingsInitialized()) {
      return null;
    }

    final samples = pcm16BytesToFloat32(pcmBytes);
    if (samples.isEmpty) return const [];

    // 1. Optional Native Speaker Diarization (Pyannote 3.0 + ERes2Net / TitaNet)
    onProgress?.call(0.25, 'Running neural speaker diarization...');
    final diarizationTurns = _tryRunNativeDiarization(
      samples: samples,
      modelsRootPath: modelsRootPath,
    );

    // 2. Native Silero VAD v5 speech segmentation
    onProgress?.call(0.45, 'Running Silero VAD v5 speech segmentation...');
    final vadSlices = _runVadOrChunking(
      samples: samples,
      sampleRate: sampleRate,
      modelsRootPath: modelsRootPath,
      vadThreshold: vadThreshold,
    );

    // 3. Create OfflineRecognizer for the selected ONNX model
    onProgress?.call(0.60, 'Loading $resolvedModelId ONNX recognizer...');
    final recognizerConfig = _buildRecognizerConfig(
      modelsRootPath: modelsRootPath,
      modelId: resolvedModelId,
      language: language,
      sampleRate: sampleRate,
    );
    if (recognizerConfig == null) return null;

    sherpa.OfflineRecognizer? recognizer;
    try {
      recognizer = sherpa.OfflineRecognizer(recognizerConfig);
      final results = <TranscriptSegment>[];

      for (int i = 0; i < vadSlices.length; i++) {
        final slice = vadSlices[i];
        final ratio = 0.65 + (0.25 * ((i + 1) / math.max(1, vadSlices.length)));
        onProgress?.call(
          ratio,
          'Transcribing segment ${i + 1} of ${vadSlices.length}...',
        );

        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(
            samples: slice.samples,
            sampleRate: sampleRate,
          );
          recognizer.decode(stream);
          final result = recognizer.getResult(stream);
          final cleanedText = _cleanRecognizedText(result.text);

          if (cleanedText.isEmpty) continue;

          final startMs = (slice.startSample * 1000) ~/ sampleRate;
          final durationMs = (slice.samples.length * 1000) ~/ sampleRate;
          final endMs = math.max(startMs + 250, startMs + durationMs);

          final speakerLabel = _assignSpeakerForSpan(
            startSec: startMs / 1000.0,
            endSec: endMs / 1000.0,
            turns: diarizationTurns,
            fallbackIndex: i,
          );

          results.add(
            TranscriptSegment(
              id: '${recordingId}_seg_${results.length}',
              recordingId: recordingId,
              startMs: startMs,
              endMs: endMs,
              speakerId: speakerLabel,
              text: cleanedText,
            ),
          );
        } finally {
          stream.free();
        }
      }

      // If VAD produced no segments (very quiet or short clip), decode full waveform directly
      if (results.isEmpty && samples.isNotEmpty) {
        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
          recognizer.decode(stream);
          final result = recognizer.getResult(stream);
          final cleanedText = _cleanRecognizedText(result.text);
          if (cleanedText.isNotEmpty) {
            final totalMs =
                math.max(1000, (samples.length * 1000) ~/ sampleRate);
            results.add(
              TranscriptSegment(
                id: '${recordingId}_seg_0',
                recordingId: recordingId,
                startMs: 0,
                endMs: totalMs,
                speakerId: 'Speaker 1',
                text: cleanedText,
              ),
            );
          }
        } finally {
          stream.free();
        }
      }

      return results;
    } catch (_) {
      return null;
    } finally {
      recognizer?.free();
    }
  }

  /// Cloud Whisper API transcription (Groq `whisper-large-v3-turbo` or OpenAI `whisper-1`)
  /// when the user configures a BYOK key in Model Hub.
  static Future<List<TranscriptSegment>?> tryCloudWhisperTranscription({
    required String recordingId,
    required Uint8List pcmBytes,
    required String apiKey,
    required String provider,
    required String language,
    int sampleRate = 16000,
  }) async {
    if (apiKey.trim().isEmpty) return null;
    if (provider != 'groq' && provider != 'openai') return null;

    final endpoint = provider == 'groq'
        ? 'https://api.groq.com/openai/v1/audio/transcriptions'
        : 'https://api.openai.com/v1/audio/transcriptions';
    final modelName =
        provider == 'groq' ? 'whisper-large-v3-turbo' : 'whisper-1';

    final wavHeader = WavHeaderHelper.createWavHeader(
      pcmDataLength: pcmBytes.length,
      sampleRate: sampleRate,
      channels: 1,
      bitsPerSample: 16,
    );
    final wavBuilder = BytesBuilder(copy: false)
      ..add(wavHeader)
      ..add(pcmBytes);
    final wavBytes = wavBuilder.takeBytes();

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 25);

    try {
      final uri = Uri.parse(endpoint);
      final request = await client.postUrl(uri);
      final boundary =
          '----KinvoiceWhisperBoundary${DateTime.now().millisecondsSinceEpoch}';

      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${apiKey.trim()}',
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      final bodyBytes = BytesBuilder(copy: false);
      void writeField(String name, String value) {
        bodyBytes.add(utf8.encode('--$boundary\r\n'));
        bodyBytes.add(
          utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
        );
        bodyBytes.add(utf8.encode('$value\r\n'));
      }

      writeField('model', modelName);
      writeField('response_format', 'verbose_json');
      if (language.isNotEmpty && language != 'auto') {
        writeField('language', language);
      }

      bodyBytes.add(utf8.encode('--$boundary\r\n'));
      bodyBytes.add(
        utf8.encode(
          'Content-Disposition: form-data; name="file"; filename="recording.wav"\r\n',
        ),
      );
      bodyBytes.add(utf8.encode('Content-Type: audio/wav\r\n\r\n'));
      bodyBytes.add(wavBytes);
      bodyBytes.add(utf8.encode('\r\n--$boundary--\r\n'));

      request.add(bodyBytes.takeBytes());
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final rawSegments = decoded['segments'] as List<dynamic>?;
      final fullText = (decoded['text'] as String? ?? '').trim();

      if (rawSegments != null && rawSegments.isNotEmpty) {
        final segments = <TranscriptSegment>[];
        for (int i = 0; i < rawSegments.length; i++) {
          final item = rawSegments[i] as Map<String, dynamic>;
          final text = (item['text'] as String? ?? '').trim();
          if (text.isEmpty) continue;
          final startSec = (item['start'] as num?)?.toDouble() ?? 0.0;
          final endSec =
              (item['end'] as num?)?.toDouble() ?? (startSec + 2.0);
          final startMs = (startSec * 1000).round();
          final endMs = math.max(startMs + 250, (endSec * 1000).round());

          segments.add(
            TranscriptSegment(
              id: '${recordingId}_seg_${segments.length}',
              recordingId: recordingId,
              startMs: startMs,
              endMs: endMs,
              speakerId: 'Speaker 1',
              text: text,
            ),
          );
        }
        if (segments.isNotEmpty) return segments;
      }

      if (fullText.isNotEmpty) {
        final totalMs =
            math.max(1000, ((pcmBytes.length ~/ 2) * 1000) ~/ sampleRate);
        return [
          TranscriptSegment(
            id: '${recordingId}_seg_0',
            recordingId: recordingId,
            startMs: 0,
            endMs: totalMs,
            speakerId: 'Speaker 1',
            text: fullText,
          ),
        ];
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: false);
    }
  }

  static List<NativeDiarizationTurn> _tryRunNativeDiarization({
    required Float32List samples,
    required String modelsRootPath,
  }) {
    try {
      final segFile = File(
        '$modelsRootPath${Platform.pathSeparator}pyannote_segmentation${Platform.pathSeparator}model.onnx',
      );
      if (!segFile.existsSync()) return const [];

      File embFile = File(
        '$modelsRootPath${Platform.pathSeparator}speaker_eres2net${Platform.pathSeparator}embedding.onnx',
      );
      if (!embFile.existsSync()) {
        embFile = File(
          '$modelsRootPath${Platform.pathSeparator}nemo_titanet${Platform.pathSeparator}embedding.onnx',
        );
      }
      if (!embFile.existsSync()) return const [];

      final config = sherpa.OfflineSpeakerDiarizationConfig(
        segmentation: sherpa.OfflineSpeakerSegmentationModelConfig(
          pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
            model: segFile.path,
          ),
          numThreads: 2,
          debug: false,
        ),
        embedding: sherpa.SpeakerEmbeddingExtractorConfig(
          model: embFile.path,
          numThreads: 2,
          debug: false,
        ),
        clustering: const sherpa.FastClusteringConfig(
          numClusters: -1,
          threshold: 0.5,
        ),
      );

      final diarizer = sherpa.OfflineSpeakerDiarization(config);
      try {
        final rawSegments = diarizer.process(samples: samples);
        return rawSegments
            .map(
              (s) => NativeDiarizationTurn(
                startSec: s.start,
                endSec: s.end,
                speakerLabel: 'Speaker ${s.speaker + 1}',
              ),
            )
            .toList();
      } finally {
        diarizer.free();
      }
    } catch (_) {
      return const [];
    }
  }

  static List<_VadAudioSlice> _runVadOrChunking({
    required Float32List samples,
    required int sampleRate,
    required String modelsRootPath,
    required double vadThreshold,
  }) {
    final vadFile = File(
      '$modelsRootPath${Platform.pathSeparator}silero_vad${Platform.pathSeparator}silero_vad.onnx',
    );

    if (vadFile.existsSync() && vadFile.lengthSync() > 1024) {
      sherpa.VoiceActivityDetector? vad;
      try {
        final vadConfig = sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: vadFile.path,
            threshold: vadThreshold.clamp(0.15, 0.85),
            minSilenceDuration: 0.45,
            minSpeechDuration: 0.25,
            windowSize: 512,
            maxSpeechDuration: 22.0,
          ),
          sampleRate: sampleRate,
          numThreads: 1,
          debug: false,
        );

        vad = sherpa.VoiceActivityDetector(
          config: vadConfig,
          bufferSizeInSeconds: 60.0,
        );

        const windowSize = 512;
        final slices = <_VadAudioSlice>[];

        for (int i = 0; i + windowSize <= samples.length; i += windowSize) {
          final chunk = Float32List.sublistView(samples, i, i + windowSize);
          vad.acceptWaveform(chunk);
          while (!vad.isEmpty()) {
            final seg = vad.front();
            vad.pop();
            if (seg.samples.isNotEmpty) {
              slices.add(
                _VadAudioSlice(
                  startSample: seg.start,
                  samples: seg.samples,
                ),
              );
            }
          }
        }

        vad.flush();
        while (!vad.isEmpty()) {
          final seg = vad.front();
          vad.pop();
          if (seg.samples.isNotEmpty) {
            slices.add(
              _VadAudioSlice(
                startSample: seg.start,
                samples: seg.samples,
              ),
            );
          }
        }

        if (slices.isNotEmpty) {
          return slices;
        }
      } catch (_) {
        // Fallback to chunking below
      } finally {
        vad?.free();
      }
    }

    // Fallback 20-second window chunking if VAD model not present or single continuous phrase
    final maxChunkSamples = sampleRate * 20;
    final slices = <_VadAudioSlice>[];
    for (int offset = 0;
        offset < samples.length;
        offset += maxChunkSamples) {
      final end = math.min(offset + maxChunkSamples, samples.length);
      slices.add(
        _VadAudioSlice(
          startSample: offset,
          samples: Float32List.sublistView(samples, offset, end),
        ),
      );
    }
    return slices;
  }

  static sherpa.OfflineRecognizerConfig? _buildRecognizerConfig({
    required String modelsRootPath,
    required String modelId,
    required String language,
    required int sampleRate,
  }) {
    final dirPath = '$modelsRootPath${Platform.pathSeparator}$modelId';
    final tokensPath = '$dirPath${Platform.pathSeparator}tokens.txt';
    final normalizedLang =
        (language == 'auto' || language.isEmpty) ? '' : language;

    if (modelId.startsWith('whisper') || modelId == 'meta_mms_khmer') {
      final whisperLang =
          modelId == 'meta_mms_khmer' && normalizedLang.isEmpty
              ? 'km'
              : normalizedLang;
      return sherpa.OfflineRecognizerConfig(
        feat: sherpa.FeatureConfig(sampleRate: sampleRate, featureDim: 80),
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: '$dirPath${Platform.pathSeparator}encoder.onnx',
            decoder: '$dirPath${Platform.pathSeparator}decoder.onnx',
            language: whisperLang,
            task: 'transcribe',
          ),
          tokens: tokensPath,
          numThreads: 2,
          debug: false,
        ),
      );
    }

    if (modelId.startsWith('moonshine')) {
      return sherpa.OfflineRecognizerConfig(
        feat: sherpa.FeatureConfig(sampleRate: sampleRate, featureDim: 80),
        model: sherpa.OfflineModelConfig(
          moonshine: sherpa.OfflineMoonshineModelConfig(
            preprocessor: '$dirPath${Platform.pathSeparator}preprocess.onnx',
            encoder: '$dirPath${Platform.pathSeparator}encode.int8.onnx',
            uncachedDecoder:
                '$dirPath${Platform.pathSeparator}uncached_decode.int8.onnx',
            cachedDecoder:
                '$dirPath${Platform.pathSeparator}cached_decode.int8.onnx',
          ),
          tokens: tokensPath,
          numThreads: 2,
          debug: false,
        ),
      );
    }

    if (modelId == 'sense_voice') {
      return sherpa.OfflineRecognizerConfig(
        feat: sherpa.FeatureConfig(sampleRate: sampleRate, featureDim: 80),
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: '$dirPath${Platform.pathSeparator}model.int8.onnx',
            language: normalizedLang.isEmpty ? 'auto' : normalizedLang,
            useInverseTextNormalization: true,
          ),
          tokens: tokensPath,
          numThreads: 2,
          debug: false,
        ),
      );
    }

    return null;
  }

  static String _assignSpeakerForSpan({
    required double startSec,
    required double endSec,
    required List<NativeDiarizationTurn> turns,
    required int fallbackIndex,
  }) {
    if (turns.isEmpty) {
      return 'Speaker 1';
    }

    String bestSpeaker = turns.first.speakerLabel;
    double bestOverlap = -1.0;

    for (final turn in turns) {
      final overlapStart = math.max(startSec, turn.startSec);
      final overlapEnd = math.min(endSec, turn.endSec);
      final overlap = overlapEnd - overlapStart;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestSpeaker = turn.speakerLabel;
      }
    }

    return bestSpeaker;
  }

  static String _cleanRecognizedText(String raw) {
    // Strip special SenseVoice / Whisper control tags such as <|en|><|NEUTRAL|><|Speech|>
    final withoutTags = raw.replaceAll(RegExp(r'<\|[^|>]+\|>'), ' ').trim();
    final collapsed = withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed;
  }
}

class _VadAudioSlice {
  const _VadAudioSlice({
    required this.startSample,
    required this.samples,
  });

  final int startSample;
  final Float32List samples;
}
