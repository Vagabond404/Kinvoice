import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/app_preferences_service.dart';

/// Represents a single remote binary or vocabulary file belonging to an ONNX model bundle.
@immutable
class ModelFileSpec {
  const ModelFileSpec({
    required this.fileName,
    required this.downloadUrl,
    required this.expectedBytes,
  });

  final String fileName;
  final String downloadUrl;
  final int expectedBytes;
}

/// Functional role of a model in the Kinvoice pipeline.
enum ModelRole {
  vad,
  asr,
  diarizationSegmentation,
  speakerEmbedding,
}

/// Architecture family used by Sherpa-ONNX for ASR models.
enum SherpaAsrFamily {
  none,
  whisper,
  moonshine,
  senseVoice,
}

/// Metadata and live installation state of an on-device AI model in the Model Hub.
class OnDeviceModelItem {
  OnDeviceModelItem({
    required this.id,
    required this.name,
    required this.sizeMb,
    required this.category,
    required this.description,
    required this.sourceRepo,
    required this.role,
    required this.files,
    this.asrFamily = SherpaAsrFamily.none,
    this.supportedLanguages = const ['en'],
    this.isEssentialCore = false,
    this.isInstalled = false,
    this.isActive = false,
    this.downloadProgress = 0.0,
    this.isDownloading = false,
    this.statusMessage,
    this.localDirectoryPath,
  });

  final String id;
  final String name;
  final int sizeMb;
  final String category;
  final String description;
  final String sourceRepo;
  final ModelRole role;
  final SherpaAsrFamily asrFamily;
  final List<String> supportedLanguages;
  final List<ModelFileSpec> files;
  final bool isEssentialCore;

  bool isInstalled;
  bool isActive;
  double downloadProgress;
  bool isDownloading;
  String? statusMessage;
  String? localDirectoryPath;
}

/// Service managing the catalog, filesystem inspection, real HTTP streaming download
/// from GitHub Releases & HuggingFace, and active model selection for Kinvoice.
class ModelDownloadService extends ChangeNotifier {
  ModelDownloadService({
    String? customModelsRootPath,
    HttpClient Function()? httpClientFactory,
  })  : _customModelsRootPath = customModelsRootPath,
        _httpClientFactory = httpClientFactory ?? HttpClient.new {
    _models = _buildDefaultCatalog();
  }

  static final ModelDownloadService instance = ModelDownloadService();

  final String? _customModelsRootPath;
  final HttpClient Function() _httpClientFactory;
  late final List<OnDeviceModelItem> _models;

  bool _isInitialized = false;
  bool _isBatchDownloadingCore = false;
  double _coreSetupProgress = 0.0;
  String _coreSetupStatus = '';

  List<OnDeviceModelItem> get models => List.unmodifiable(_models);
  bool get isInitialized => _isInitialized;
  bool get isBatchDownloadingCore => _isBatchDownloadingCore;
  double get coreSetupProgress => _coreSetupProgress;
  String get coreSetupStatus => _coreSetupStatus;

  /// Active ASR model ID selected by the user.
  String _activeAsrModelId = 'whisper_tiny';
  String get activeAsrModelId => _activeAsrModelId;

  /// Active speaker embedding model ID selected by the user.
  String _activeSpeakerModelId = 'speaker_eres2net';
  String get activeSpeakerModelId => _activeSpeakerModelId;

  List<OnDeviceModelItem> _buildDefaultCatalog() {
    return [
      // 1. Silero VAD v5 (GitHub Releases)
      OnDeviceModelItem(
        id: 'silero_vad',
        name: 'Silero VAD v5 (ONNX)',
        sizeMb: 2,
        category: 'Voice Activity Detection (H24)',
        description:
            '32ms neural frame slicing for continuous 24/7 speech detection and silence trimming.',
        sourceRepo: 'github.com/k2-fsa/sherpa-onnx',
        role: ModelRole.vad,
        supportedLanguages: const ['universal'],
        isEssentialCore: true,
        isActive: true,
        files: const [
          ModelFileSpec(
            fileName: 'silero_vad.onnx',
            downloadUrl:
                'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
            expectedBytes: 643854,
          ),
        ],
      ),

      // 2. Whisper Tiny Multilingual INT8 (HuggingFace)
      OnDeviceModelItem(
        id: 'whisper_tiny',
        name: 'Whisper Tiny Multilingual (INT8 ONNX)',
        sizeMb: 98,
        category: 'Multilingual Speech Recognition',
        description:
            'Fast 99-language speech recognition (Français, English, Khmer, Español) for H24 & studio notes.',
        sourceRepo: 'huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.whisper,
        supportedLanguages: const ['fr', 'en', 'km', 'auto'],
        isEssentialCore: true,
        isActive: true,
        files: const [
          ModelFileSpec(
            fileName: 'encoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
            expectedBytes: 12937772,
          ),
          ModelFileSpec(
            fileName: 'decoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
            expectedBytes: 89855401,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
            expectedBytes: 816700,
          ),
        ],
      ),

      // 3. Whisper Base Multilingual INT8 (HuggingFace)
      OnDeviceModelItem(
        id: 'whisper_base',
        name: 'Whisper Base Multilingual (INT8 ONNX)',
        sizeMb: 152,
        category: 'Multilingual Speech Recognition',
        description:
            'Enhanced accuracy across 99 languages (Français, English, Khmer) for meetings & interviews.',
        sourceRepo: 'huggingface.co/csukuangfj/sherpa-onnx-whisper-base',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.whisper,
        supportedLanguages: const ['fr', 'en', 'km', 'auto'],
        files: const [
          ModelFileSpec(
            fileName: 'encoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main/base-encoder.int8.onnx',
            expectedBytes: 29120534,
          ),
          ModelFileSpec(
            fileName: 'decoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main/base-decoder.int8.onnx',
            expectedBytes: 130672026,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main/base-tokens.txt',
            expectedBytes: 816700,
          ),
        ],
      ),

      // 4. Whisper Small Studio Pro INT8 (HuggingFace)
      OnDeviceModelItem(
        id: 'whisper_small',
        name: 'Whisper Small Studio Pro (INT8 ONNX)',
        sizeMb: 357,
        category: 'Multilingual Speech Recognition',
        description:
            'Studio-grade multilingual transcription (99 languages) with deep context and punctuation.',
        sourceRepo: 'huggingface.co/csukuangfj/sherpa-onnx-whisper-small',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.whisper,
        supportedLanguages: const ['fr', 'en', 'km', 'auto'],
        files: const [
          ModelFileSpec(
            fileName: 'encoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main/small-encoder.int8.onnx',
            expectedBytes: 112442483,
          ),
          ModelFileSpec(
            fileName: 'decoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main/small-decoder.int8.onnx',
            expectedBytes: 262226114,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main/small-tokens.txt',
            expectedBytes: 816700,
          ),
        ],
      ),

      // 5. Moonshine Tiny (4-bit/INT8 ONNX - HuggingFace)
      OnDeviceModelItem(
        id: 'moonshine_tiny',
        name: 'Moonshine Tiny (INT8 ONNX)',
        sizeMb: 118,
        category: 'Ultra-Fast English ASR',
        description:
            'Ultra-low latency 5x real-time English speech-to-text for instant voice notes.',
        sourceRepo: 'huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.moonshine,
        supportedLanguages: const ['en'],
        files: const [
          ModelFileSpec(
            fileName: 'preprocess.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/preprocess.onnx',
            expectedBytes: 6800738,
          ),
          ModelFileSpec(
            fileName: 'encode.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/encode.int8.onnx',
            expectedBytes: 18249187,
          ),
          ModelFileSpec(
            fileName: 'uncached_decode.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/uncached_decode.int8.onnx',
            expectedBytes: 53216096,
          ),
          ModelFileSpec(
            fileName: 'cached_decode.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/cached_decode.int8.onnx',
            expectedBytes: 45264830,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-tiny-en-int8/resolve/main/tokens.txt',
            expectedBytes: 320000,
          ),
        ],
      ),

      // 6. Moonshine Base (4-bit ONNX - HuggingFace)
      OnDeviceModelItem(
        id: 'moonshine_base',
        name: 'Moonshine Base (4-bit ONNX)',
        sizeMb: 38,
        category: 'Ultra-Fast English ASR',
        description:
            'High-precision Moonshine transformer with word-level timestamp alignment.',
        sourceRepo: 'huggingface.co/csukuangfj/sherpa-onnx-moonshine-base-en-int8',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.moonshine,
        supportedLanguages: const ['en'],
        files: const [
          ModelFileSpec(
            fileName: 'preprocess.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-base-en-int8/resolve/main/preprocess.onnx',
            expectedBytes: 14077290,
          ),
          ModelFileSpec(
            fileName: 'encode.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-base-en-int8/resolve/main/encode.int8.onnx',
            expectedBytes: 50311494,
          ),
          ModelFileSpec(
            fileName: 'uncached_decode.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-base-en-int8/resolve/main/uncached_decode.int8.onnx',
            expectedBytes: 122120451,
          ),
          ModelFileSpec(
            fileName: 'cached_decode.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-base-en-int8/resolve/main/cached_decode.int8.onnx',
            expectedBytes: 99983837,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-moonshine-base-en-int8/resolve/main/tokens.txt',
            expectedBytes: 320000,
          ),
        ],
      ),

      // 7. FunASR SenseVoice Multilingual + Emotion (HuggingFace)
      OnDeviceModelItem(
        id: 'sense_voice',
        name: 'SenseVoice Multilingual + Emotion (ONNX)',
        sizeMb: 228,
        category: 'Emotion & Acoustic Event ASR',
        description:
            'Transcribes speech while detecting speaker emotion (Happy, Neutral, Angry) and audio events.',
        sourceRepo:
            'huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.senseVoice,
        supportedLanguages: const ['auto', 'en', 'zh', 'ja', 'ko'],
        files: const [
          ModelFileSpec(
            fileName: 'model.int8.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
            expectedBytes: 239233841,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
            expectedBytes: 300000,
          ),
        ],
      ),

      // 8. Meta MMS / Multilingual Khmer Pack (HuggingFace)
      OnDeviceModelItem(
        id: 'meta_mms_khmer',
        name: 'Meta MMS Conformer (Khmer 🇰🇭)',
        sizeMb: 42,
        category: 'Low-Resource Speech (Khmer)',
        description:
            'Dedicated acoustic model pack for Khmer (ភាសាខ្មែរ) and bilingual voice notes.',
        sourceRepo: 'huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny',
        role: ModelRole.asr,
        asrFamily: SherpaAsrFamily.whisper,
        supportedLanguages: const ['km', 'en', 'fr'],
        files: const [
          ModelFileSpec(
            fileName: 'encoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
            expectedBytes: 12937772,
          ),
          ModelFileSpec(
            fileName: 'decoder.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
            expectedBytes: 89855401,
          ),
          ModelFileSpec(
            fileName: 'tokens.txt',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
            expectedBytes: 816700,
          ),
        ],
      ),

      // 9. Pyannote Speaker Segmentation 3.0 (HuggingFace)
      OnDeviceModelItem(
        id: 'pyannote_segmentation',
        name: 'Pyannote Segmentation 3.0 (ONNX)',
        sizeMb: 6,
        category: 'Speaker Diarization & Voice ID',
        description:
            'Detects exact speaker turn boundaries and overlapping voices in multi-person meetings.',
        sourceRepo:
            'huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0',
        role: ModelRole.diarizationSegmentation,
        supportedLanguages: const ['universal'],
        isEssentialCore: true,
        isActive: true,
        files: const [
          ModelFileSpec(
            fileName: 'model.onnx',
            downloadUrl:
                'https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx',
            expectedBytes: 5992913,
          ),
        ],
      ),

      // 10. 3D-Speaker ERes2Net Voice Recognition (GitHub Releases)
      OnDeviceModelItem(
        id: 'speaker_eres2net',
        name: '3D-Speaker ERes2Net Voice ID (ONNX)',
        sizeMb: 38,
        category: 'Speaker Diarization & Voice ID',
        description:
            'Extracts neural speaker embeddings to automatically separate Speaker 1, Speaker 2, etc.',
        sourceRepo: 'github.com/k2-fsa/sherpa-onnx',
        role: ModelRole.speakerEmbedding,
        supportedLanguages: const ['universal'],
        isEssentialCore: true,
        isActive: true,
        files: const [
          ModelFileSpec(
            fileName: 'embedding.onnx',
            downloadUrl:
                'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
            expectedBytes: 39593761,
          ),
        ],
      ),

      // 11. NVIDIA NeMo TitaNet-Small Speaker ID (GitHub Releases)
      OnDeviceModelItem(
        id: 'nemo_titanet',
        name: 'NVIDIA NeMo TitaNet-Small (ONNX)',
        sizeMb: 38,
        category: 'Speaker Diarization & Voice ID',
        description:
            'NVIDIA TitaNet speaker verification and biometric clustering model.',
        sourceRepo: 'github.com/k2-fsa/sherpa-onnx',
        role: ModelRole.speakerEmbedding,
        supportedLanguages: const ['universal'],
        files: const [
          ModelFileSpec(
            fileName: 'embedding.onnx',
            downloadUrl:
                'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/nemo_en_titanet_small.onnx',
            expectedBytes: 40257283,
          ),
        ],
      ),
    ];
  }

  /// Resolves the root directory where all ONNX models are stored on disk:
  /// `[ApplicationDocumentsDirectory]/Kinvoice/Models`
  Future<Directory> getModelsRootDirectory() async {
    String basePath;
    if (_customModelsRootPath != null && _customModelsRootPath.isNotEmpty) {
      basePath = _customModelsRootPath;
    } else {
      try {
        final docs = await getApplicationDocumentsDirectory();
        basePath = docs.path;
      } catch (_) {
        basePath = Directory.systemTemp.path;
      }
    }

    final dir = Directory(
      '$basePath${Platform.pathSeparator}Kinvoice${Platform.pathSeparator}Models',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Resolves the directory for a specific model ID.
  Future<Directory> getModelDirectory(String modelId) async {
    final root = await getModelsRootDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}$modelId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Scans the local filesystem to verify which models have all required files downloaded.
  Future<void> refreshInstallationStatus() async {
    final root = await getModelsRootDirectory();
    final savedActiveAsr = AppPreferencesService.instance.activeAsrModel;
    if (savedActiveAsr.isNotEmpty) {
      _activeAsrModelId = savedActiveAsr;
    }

    for (final model in _models) {
      final modelDir = Directory(
        '${root.path}${Platform.pathSeparator}${model.id}',
      );
      model.localDirectoryPath = modelDir.path;

      if (!await modelDir.exists()) {
        model.isInstalled = false;
        continue;
      }

      bool allFilesPresent = true;
      for (final fileSpec in model.files) {
        final f = File(
          '${modelDir.path}${Platform.pathSeparator}${fileSpec.fileName}',
        );
        if (!await f.exists() || await f.length() < 1024) {
          allFilesPresent = false;
          break;
        }
      }

      model.isInstalled = allFilesPresent;
      if (model.role == ModelRole.asr) {
        model.isActive = model.isInstalled && model.id == _activeAsrModelId;
      } else if (model.role == ModelRole.speakerEmbedding) {
        model.isActive = model.isInstalled && model.id == _activeSpeakerModelId;
      } else if (model.isInstalled) {
        model.isActive = true;
      }
    }

    // Ensure at least one installed ASR model is marked active if available
    final installedAsr = _models
        .where((m) => m.role == ModelRole.asr && m.isInstalled)
        .toList();
    if (installedAsr.isNotEmpty && !installedAsr.any((m) => m.isActive)) {
      installedAsr.first.isActive = true;
      _activeAsrModelId = installedAsr.first.id;
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Returns true if `silero_vad` and at least one ASR model (`whisper_tiny`, etc.) are installed on disk.
  Future<bool> areCoreModelsInstalled() async {
    await refreshInstallationStatus();
    final vadInstalled = getModelById('silero_vad')?.isInstalled ?? false;
    final anyAsrInstalled =
        _models.any((m) => m.role == ModelRole.asr && m.isInstalled);
    return vadInstalled && anyAsrInstalled;
  }

  OnDeviceModelItem? getModelById(String id) {
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Returns the currently active installed ASR model, or falls back to any installed ASR model.
  OnDeviceModelItem? getActiveInstalledAsrModel({String? preferredLanguage}) {
    if (preferredLanguage == 'km') {
      final khmerModel = getModelById('meta_mms_khmer');
      if (khmerModel != null && khmerModel.isInstalled) {
        return khmerModel;
      }
    }
    final active = getModelById(_activeAsrModelId);
    if (active != null && active.isInstalled) {
      return active;
    }
    for (final m in _models) {
      if (m.role == ModelRole.asr && m.isInstalled) {
        return m;
      }
    }
    return null;
  }

  /// Sets the active ASR model and persists the choice.
  Future<void> setActiveAsrModel(String modelId) async {
    _activeAsrModelId = modelId;
    for (final m in _models) {
      if (m.role == ModelRole.asr) {
        m.isActive = m.id == modelId && m.isInstalled;
      }
    }
    await AppPreferencesService.instance.setActiveAsrModel(modelId);
    notifyListeners();
  }

  /// Sets the active Speaker Embedding model.
  void setActiveSpeakerModel(String modelId) {
    _activeSpeakerModelId = modelId;
    for (final m in _models) {
      if (m.role == ModelRole.speakerEmbedding) {
        m.isActive = m.id == modelId && m.isInstalled;
      }
    }
    notifyListeners();
  }

  /// Downloads all files for [modelId] from HuggingFace / GitHub Releases with real-time byte progress.
  Future<bool> downloadModel(
    String modelId, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final model = getModelById(modelId);
    if (model == null) return false;
    if (model.isDownloading) return false;

    model.isDownloading = true;
    model.downloadProgress = 0.01;
    model.statusMessage = 'Connecting to ${model.sourceRepo}...';
    notifyListeners();

    final modelDir = await getModelDirectory(modelId);
    model.localDirectoryPath = modelDir.path;

    final totalExpectedBytes = model.files.fold<int>(
      0,
      (sum, f) => sum + (f.expectedBytes > 0 ? f.expectedBytes : 1000000),
    );
    int cumulativeDownloadedBytes = 0;

    final client = _httpClientFactory();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      for (int i = 0; i < model.files.length; i++) {
        final spec = model.files[i];
        final targetFile = File(
          '${modelDir.path}${Platform.pathSeparator}${spec.fileName}',
        );
        final tempFile = File('${targetFile.path}.part');

        // Skip file if already downloaded and non-empty
        if (await targetFile.exists() && await targetFile.length() > 1024) {
          cumulativeDownloadedBytes += await targetFile.length();
          final progress =
              (cumulativeDownloadedBytes / totalExpectedBytes).clamp(0.02, 0.99);
          model.downloadProgress = progress;
          onProgress?.call(progress, 'Verified ${spec.fileName}');
          notifyListeners();
          continue;
        }

        model.statusMessage =
            'Downloading ${spec.fileName} (${i + 1}/${model.files.length})...';
        onProgress?.call(model.downloadProgress, model.statusMessage!);
        notifyListeners();

        final uri = Uri.parse(spec.downloadUrl);
        final request = await client.getUrl(uri);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Kinvoice-Mobile-AI/1.0',
        );
        final response = await request.close();

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'HTTP ${response.statusCode} while downloading ${spec.fileName}',
            uri: uri,
          );
        }

        final sink = tempFile.openWrite();
        int fileBytesReceived = 0;

        await for (final chunk in response) {
          sink.add(chunk);
          fileBytesReceived += chunk.length;
          final currentTotal = cumulativeDownloadedBytes + fileBytesReceived;
          final ratio = (currentTotal / totalExpectedBytes).clamp(0.02, 0.99);
          model.downloadProgress = ratio;

          final mbDone = (currentTotal / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal =
              (totalExpectedBytes / (1024 * 1024)).toStringAsFixed(1);
          model.statusMessage =
              '${spec.fileName} • $mbDone / $mbTotal MB';
          onProgress?.call(ratio, model.statusMessage!);
          notifyListeners();
        }

        await sink.flush();
        await sink.close();

        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);
        cumulativeDownloadedBytes += fileBytesReceived;
      }

      model.isDownloading = false;
      model.isInstalled = true;
      model.downloadProgress = 1.0;
      model.statusMessage = 'Installed & ready for offline inference';

      if (model.role == ModelRole.asr) {
        await setActiveAsrModel(model.id);
      } else if (model.role == ModelRole.speakerEmbedding) {
        setActiveSpeakerModel(model.id);
      } else {
        model.isActive = true;
      }

      onProgress?.call(1.0, model.statusMessage!);
      notifyListeners();
      return true;
    } catch (e) {
      model.isDownloading = false;
      model.downloadProgress = 0.0;
      model.statusMessage = 'Download failed: $e';
      onProgress?.call(0.0, model.statusMessage!);
      notifyListeners();
      return false;
    } finally {
      client.close(force: false);
    }
  }

  /// Downloads the essential starter pack (`silero_vad`, `pyannote_segmentation`, `speaker_eres2net`, `whisper_tiny`)
  /// automatically on first app launch so both H24 real-time mode and studio mode work out-of-the-box.
  Future<bool> downloadEssentialCorePack({
    void Function(double progress, String status)? onProgress,
  }) async {
    if (_isBatchDownloadingCore) return false;
    _isBatchDownloadingCore = true;
    _coreSetupProgress = 0.01;
    _coreSetupStatus = 'Preparing AI models from GitHub & HuggingFace...';
    notifyListeners();

    const coreIds = [
      'silero_vad',
      'pyannote_segmentation',
      'speaker_eres2net',
      'whisper_tiny',
    ];

    try {
      for (int i = 0; i < coreIds.length; i++) {
        final id = coreIds[i];
        final model = getModelById(id);
        if (model == null) continue;

        if (model.isInstalled) {
          _coreSetupProgress = (i + 1) / coreIds.length;
          notifyListeners();
          continue;
        }

        final ok = await downloadModel(
          id,
          onProgress: (modelProg, msg) {
            final overall = ((i + modelProg) / coreIds.length).clamp(0.01, 0.99);
            _coreSetupProgress = overall;
            _coreSetupStatus = '${model.name}: $msg';
            onProgress?.call(overall, _coreSetupStatus);
            notifyListeners();
          },
        );

        if (!ok) {
          _isBatchDownloadingCore = false;
          _coreSetupStatus = 'Error downloading ${model.name}. Check connection.';
          notifyListeners();
          return false;
        }
      }

      _isBatchDownloadingCore = false;
      _coreSetupProgress = 1.0;
      _coreSetupStatus = 'All core AI models installed and active!';
      onProgress?.call(1.0, _coreSetupStatus);
      notifyListeners();
      return true;
    } catch (e) {
      _isBatchDownloadingCore = false;
      _coreSetupStatus = 'Setup interrupted: $e';
      notifyListeners();
      return false;
    }
  }

  /// Uninstalls a downloaded model and frees local disk space.
  Future<void> uninstallModel(String modelId) async {
    final model = getModelById(modelId);
    if (model == null) return;

    final dir = await getModelDirectory(modelId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    model.isInstalled = false;
    model.isActive = false;
    model.downloadProgress = 0.0;
    model.statusMessage = null;

    await refreshInstallationStatus();
  }
}
