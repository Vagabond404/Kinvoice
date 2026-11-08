import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure encrypted key-value storage for BYOK (Bring Your Own Key) credentials.
class SecureStorageService {
  SecureStorageService({
    FlutterSecureStorage? storage,
    Map<String, String>? initialInMemoryFallback,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _inMemoryFallback = initialInMemoryFallback;

  final FlutterSecureStorage _storage;
  final Map<String, String>? _inMemoryFallback;

  static const String keyProvider = 'kinvoice_byok_provider';
  static const String keyApiKey = 'kinvoice_byok_api_key';
  static const String keyEndpointUrl = 'kinvoice_byok_endpoint_url';
  static const String keyModelName = 'kinvoice_byok_model_name';

  Future<String?> read(String key) async {
    if (_inMemoryFallback != null) {
      return _inMemoryFallback[key];
    }
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    if (_inMemoryFallback != null) {
      _inMemoryFallback[key] = value;
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<void> delete(String key) async {
    if (_inMemoryFallback != null) {
      _inMemoryFallback.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  // BYOK specific getters & setters
  Future<String?> getApiKey() => read(keyApiKey);
  Future<void> setApiKey(String key) => write(keyApiKey, key);

  Future<String?> getEndpointUrl() => read(keyEndpointUrl);
  Future<void> setEndpointUrl(String url) => write(keyEndpointUrl, url);

  Future<String?> getModelName() => read(keyModelName);
  Future<void> setModelName(String model) => write(keyModelName, model);

  Future<String?> getProvider() => read(keyProvider);
  Future<void> setProvider(String provider) => write(keyProvider, provider);

  Future<void> clearByokCredentials() async {
    await delete(keyProvider);
    await delete(keyApiKey);
    await delete(keyEndpointUrl);
    await delete(keyModelName);
  }
}
