import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Native FFI Typedefs matching native/silero_vad/kinvoice_silero_vad.h
// ---------------------------------------------------------------------------

final class SileroVadContext extends Opaque {}

typedef SileroVadCreateC = Pointer<SileroVadContext> Function(
  Pointer<Utf8> modelPath,
  Int32 sampleRate,
);
typedef SileroVadCreateDart = Pointer<SileroVadContext> Function(
  Pointer<Utf8> modelPath,
  int sampleRate,
);

typedef SileroVadProcessFrameC = Float Function(
  Pointer<SileroVadContext> ctx,
  Pointer<Float> audioFrame,
  Int32 frameSize,
);
typedef SileroVadProcessFrameDart = double Function(
  Pointer<SileroVadContext> ctx,
  Pointer<Float> audioFrame,
  int frameSize,
);

typedef SileroVadResetC = Void Function(Pointer<SileroVadContext> ctx);
typedef SileroVadResetDart = void Function(Pointer<SileroVadContext> ctx);

typedef SileroVadDestroyC = Void Function(Pointer<SileroVadContext> ctx);
typedef SileroVadDestroyDart = void Function(Pointer<SileroVadContext> ctx);

/// Dart FFI bindings for ONNX Runtime Silero VAD native C++ library.
class NativeSileroVadBindings {
  NativeSileroVadBindings(DynamicLibrary library) {
    create = library
        .lookup<NativeFunction<SileroVadCreateC>>('silero_vad_create')
        .asFunction();
    processFrame = library
        .lookup<NativeFunction<SileroVadProcessFrameC>>('silero_vad_process_frame')
        .asFunction();
    reset = library
        .lookup<NativeFunction<SileroVadResetC>>('silero_vad_reset')
        .asFunction();
    destroy = library
        .lookup<NativeFunction<SileroVadDestroyC>>('silero_vad_destroy')
        .asFunction();
  }

  late final SileroVadCreateDart create;
  late final SileroVadProcessFrameDart processFrame;
  late final SileroVadResetDart reset;
  late final SileroVadDestroyDart destroy;

  /// Loads the platform-specific native dynamic library.
  static DynamicLibrary? loadLibrary({String? customLibraryPath}) {
    if (customLibraryPath != null) {
      return DynamicLibrary.open(customLibraryPath);
    }

    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libkinvoice_silero_vad.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        return DynamicLibrary.process();
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('kinvoice_silero_vad.dll');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libkinvoice_silero_vad.so');
      }
    } catch (e) {
      debugPrint('NativeSileroVadBindings: DynamicLibrary load failed: $e');
    }
    return null;
  }
}

/// Abstract interface for VAD inference backends (ONNX FFI vs Heuristic/Simulated).
abstract interface class VadInferenceBackend {
  /// Processes a 512-sample Float32 normalized audio frame, returning probability [0.0, 1.0].
  double processFrame(Float32List frame);

  /// Resets the internal recurrent context state.
  void reset();

  /// Releases native and backend resources.
  void dispose();
}

/// Production VAD backend using the C++/ONNX Runtime FFI dynamic library.
class OnnxRuntimeVadBackend implements VadInferenceBackend {
  OnnxRuntimeVadBackend._(
    this._bindings,
    this._context,
  ) : _nativeFrameBuffer = calloc<Float>(512);

  final NativeSileroVadBindings _bindings;
  final Pointer<SileroVadContext> _context;
  final Pointer<Float> _nativeFrameBuffer;
  bool _isDisposed = false;

  /// Creates an ONNX Runtime VAD backend from the model file.
  static OnnxRuntimeVadBackend? create({
    required String modelPath,
    int sampleRate = 16000,
    String? dynamicLibraryPath,
  }) {
    final dylib =
        NativeSileroVadBindings.loadLibrary(customLibraryPath: dynamicLibraryPath);
    if (dylib == null) return null;

    final bindings = NativeSileroVadBindings(dylib);
    final modelPathUtf8 = modelPath.toNativeUtf8();

    try {
      final ctx = bindings.create(modelPathUtf8, sampleRate);
      if (ctx == nullptr) return null;
      return OnnxRuntimeVadBackend._(bindings, ctx);
    } finally {
      calloc.free(modelPathUtf8);
    }
  }

  @override
  double processFrame(Float32List frame) {
    if (_isDisposed) return 0.0;
    assert(frame.length == 512, 'Frame must be exactly 512 samples');

    try {
      final nativeList = _nativeFrameBuffer.asTypedList(512);
      nativeList.setAll(0, frame);
      return _bindings.processFrame(_context, _nativeFrameBuffer, 512);
    } catch (e) {
      debugPrint('OnnxRuntimeVadBackend processFrame error: $e');
      return 0.0;
    }
  }

  @override
  void reset() {
    if (!_isDisposed) {
      _bindings.reset(_context);
    }
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _bindings.destroy(_context);
      calloc.free(_nativeFrameBuffer);
    }
  }
}

/// Fallback and testable VAD backend implementing acoustic energy and envelope analysis.
class SimulatedVadBackend implements VadInferenceBackend {
  SimulatedVadBackend({this.customThreshold = 0.5});

  final double customThreshold;
  double _recurrentEnergy = 0.0;

  @override
  double processFrame(Float32List frame) {
    if (frame.isEmpty) return 0.0;

    double sumSquares = 0.0;
    for (int i = 0; i < frame.length; i++) {
      final s = frame[i];
      sumSquares += s * s;
    }

    final rms = (sumSquares / frame.length > 0)
        ? (sumSquares / frame.length)
        : 0.0;

    // Smooth with pseudo-recurrent context
    _recurrentEnergy = (_recurrentEnergy * 0.7) + (rms * 0.3);

    // Probability mapped from normalized energy (e.g., speech typically > 0.005)
    final prob = (_recurrentEnergy * 25.0).clamp(0.0, 1.0);
    return prob;
  }

  @override
  void reset() {
    _recurrentEnergy = 0.0;
  }

  @override
  void dispose() {
    _recurrentEnergy = 0.0;
  }
}
