import 'dart:typed_data';
import 'onnx_vad_bindings.dart';

/// Silero VAD v5 Engine processing 512-sample audio frames at 16,000 Hz (32ms).
/// Converts 16-bit linear PCM into normalized Float32 values and executes inference.
class SileroVadEngine {
  SileroVadEngine({
    VadInferenceBackend? backend,
    this.sampleRate = 16000,
  }) : _backend = backend ?? SimulatedVadBackend();

  final VadInferenceBackend _backend;
  final int sampleRate;

  static const int frameSize = 512; // 512 samples = 32ms at 16kHz
  static const int frameBytes = frameSize * 2; // 16-bit PCM = 1024 bytes per frame

  // Reusable Float32 frame buffer to eliminate per-frame GC allocations
  final Float32List _floatBuffer = Float32List(frameSize);

  bool _isDisposed = false;

  /// Factory constructing engine backed by ONNX Runtime native dynamic library.
  static SileroVadEngine createOnnx({
    required String modelPath,
    int sampleRate = 16000,
    String? dynamicLibraryPath,
  }) {
    final nativeBackend = OnnxRuntimeVadBackend.create(
      modelPath: modelPath,
      sampleRate: sampleRate,
      dynamicLibraryPath: dynamicLibraryPath,
    );

    return SileroVadEngine(
      backend: nativeBackend ?? SimulatedVadBackend(),
      sampleRate: sampleRate,
    );
  }

  /// Processes a 512-sample (1024 bytes) 16-bit Mono PCM byte buffer.
  /// Returns speech probability [0.0, 1.0].
  double processPcmBytes(Uint8List pcmBytes) {
    if (_isDisposed) return 0.0;
    if (pcmBytes.length < frameBytes) return 0.0;

    // Convert 16-bit signed PCM (Little-Endian) to Float32 [-1.0, 1.0]
    final byteData = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < frameSize; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      _floatBuffer[i] = sample / 32768.0;
    }

    return _backend.processFrame(_floatBuffer);
  }

  /// Processes raw 16-bit integer samples.
  double processInt16Samples(Int16List samples) {
    if (_isDisposed) return 0.0;
    final count = samples.length < frameSize ? samples.length : frameSize;

    for (int i = 0; i < count; i++) {
      _floatBuffer[i] = samples[i] / 32768.0;
    }
    for (int i = count; i < frameSize; i++) {
      _floatBuffer[i] = 0.0;
    }

    return _backend.processFrame(_floatBuffer);
  }

  /// Processes a pre-normalized Float32 buffer directly.
  double processFloat32Frame(Float32List floatFrame) {
    if (_isDisposed) return 0.0;
    assert(floatFrame.length == frameSize, 'Frame must be 512 samples');
    return _backend.processFrame(floatFrame);
  }

  /// Resets internal recurrent context state.
  void resetState() {
    if (!_isDisposed) {
      _backend.reset();
    }
  }

  /// Releases engine resources.
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _backend.dispose();
    }
  }
}
