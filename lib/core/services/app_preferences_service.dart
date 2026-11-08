import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/storage_keys.dart';

/// Supported audio recording formats.
enum AudioRecordingFormat {
  /// Standard Voice (AAC / M4A - lightweight, ~1MB/min).
  standardM4a(
    code: 'm4a',
    extension: 'm4a',
    title: 'Standard Voice (AAC / M4A)',
    subtitle: 'Lightweight compressed audio (~1 MB/min)',
    badgeLabel: 'AAC • M4A',
  ),

  /// Pro Audio Studio (PCM WAV 16kHz, 16-bit Mono - uncompressed for maximum AI accuracy).
  proWav(
    code: 'wav',
    extension: 'wav',
    title: 'Pro Audio Studio (PCM WAV 16kHz)',
    subtitle: '16-bit Mono uncompressed for maximum AI accuracy',
    badgeLabel: '16 kHz Mono PCM • WAV',
  );

  const AudioRecordingFormat({
    required this.code,
    required this.extension,
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
  });

  final String code;
  final String extension;
  final String title;
  final String subtitle;
  final String badgeLabel;

  static AudioRecordingFormat fromCode(String? code) {
    if (code == standardM4a.code) return standardM4a;
    return proWav;
  }
}

/// Persistent preferences service backed by [SharedPreferences].
class AppPreferencesService extends ChangeNotifier {
  AppPreferencesService({SharedPreferences? prefs}) : _prefs = prefs;

  static final AppPreferencesService instance = AppPreferencesService();

  SharedPreferences? _prefs;
  final Map<String, Object> _fallbackMemoryStore = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initializes the underlying [SharedPreferences] instance.
  Future<void> init() async {
    if (_isInitialized && _prefs != null) return;
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      // Fallback to in-memory map in headless test environments without platform channels
    }
    _isInitialized = true;
    notifyListeners();
  }

  AudioRecordingFormat get audioFormat {
    final code = _getString(StorageKeys.audioRecordingFormat);
    return AudioRecordingFormat.fromCode(code);
  }

  Future<void> setAudioFormat(AudioRecordingFormat format) async {
    await _setString(StorageKeys.audioRecordingFormat, format.code);
    notifyListeners();
  }

  bool get autoTranscribeOnSave {
    return _getBool(StorageKeys.autoTranscribeOnSave) ?? true;
  }

  Future<void> setAutoTranscribeOnSave(bool enabled) async {
    await _setBool(StorageKeys.autoTranscribeOnSave, enabled);
    notifyListeners();
  }

  /// Primary transcription language: 'en', 'km', 'fr', or 'auto'.
  String get primaryLanguage {
    return _getString(StorageKeys.activeLanguage) ?? 'en';
  }

  Future<void> setPrimaryLanguage(String languageCode) async {
    await _setString(StorageKeys.activeLanguage, languageCode);
    notifyListeners();
  }

  bool get wordLevelTimestamps {
    return _getBool(StorageKeys.wordLevelTimestamps) ?? true;
  }

  Future<void> setWordLevelTimestamps(bool enabled) async {
    await _setBool(StorageKeys.wordLevelTimestamps, enabled);
    notifyListeners();
  }

  /// Microphone VAD sensitivity normalized in [0.0, 1.0]:
  /// 0.0 = Low, 0.5 = Medium, 1.0 = High.
  double get vadSensitivity {
    return (_getDouble(StorageKeys.vadSensitivity) ?? 0.5).clamp(0.0, 1.0);
  }

  /// Converts user-facing sensitivity (0.0 Low -> 1.0 High) into Silero VAD
  /// activation threshold (higher sensitivity = lower activation threshold).
  double get sileroVadThreshold {
    final s = vadSensitivity;
    // Maps 0.0 -> 0.65 (Low sensitivity), 0.5 -> 0.50 (Medium), 1.0 -> 0.35 (High)
    return (0.65 - (s * 0.30)).clamp(0.25, 0.75);
  }

  String get vadSensitivityLabel {
    final s = vadSensitivity;
    if (s < 0.34) return 'Low';
    if (s < 0.67) return 'Medium';
    return 'High';
  }

  Future<void> setVadSensitivity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    await _setDouble(StorageKeys.vadSensitivity, clamped);
    notifyListeners();
  }

  bool get lowBatteryAutoThrottle {
    return _getBool(StorageKeys.lowBatteryAutoThrottle) ?? true;
  }

  Future<void> setLowBatteryAutoThrottle(bool enabled) async {
    await _setBool(StorageKeys.lowBatteryAutoThrottle, enabled);
    notifyListeners();
  }

  String get activeAsrModel {
    return _getString(StorageKeys.selectedAsrModel) ?? 'whisper_tiny';
  }

  Future<void> setActiveAsrModel(String modelId) async {
    await _setString(StorageKeys.selectedAsrModel, modelId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal storage helpers with automatic fallback
  // ---------------------------------------------------------------------------

  String? _getString(String key) {
    try {
      if (_prefs != null) return _prefs!.getString(key);
    } catch (_) {}
    return _fallbackMemoryStore[key] as String?;
  }

  Future<void> _setString(String key, String value) async {
    _fallbackMemoryStore[key] = value;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(key, value);
    } catch (_) {}
  }

  bool? _getBool(String key) {
    try {
      if (_prefs != null) return _prefs!.getBool(key);
    } catch (_) {}
    return _fallbackMemoryStore[key] as bool?;
  }

  Future<void> _setBool(String key, bool value) async {
    _fallbackMemoryStore[key] = value;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(key, value);
    } catch (_) {}
  }

  double? _getDouble(String key) {
    try {
      if (_prefs != null) return _prefs!.getDouble(key);
    } catch (_) {}
    return _fallbackMemoryStore[key] as double?;
  }

  Future<void> _setDouble(String key, double value) async {
    _fallbackMemoryStore[key] = value;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setDouble(key, value);
    } catch (_) {}
  }
}
