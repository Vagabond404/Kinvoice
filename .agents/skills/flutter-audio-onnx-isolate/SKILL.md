---
name: flutter-audio-onnx-isolate
description: Guidelines for implementing low-latency 16kHz PCM audio capture, background Dart Isolates, Silero VAD frame slicing, and ONNX Runtime FFI tensor handling without UI jank.
---

# Flutter Audio & ONNX Runtime Background Isolate Architecture

## Purpose
This skill establishes strict architectural patterns for high-performance, real-time audio acquisition and on-device machine learning inference (such as Silero VAD, Whisper, or custom models) in Flutter applications. It prevents UI frame drops (jank) and native memory leaks.

---

## Architectural Rules

### 1. Isolate Isolation (Zero UI Thread Blocking)
- **Never** process raw audio buffers, resample audio frames, or execute ONNX Runtime inferences on the main Flutter UI thread.
- Always spawn a dedicated background worker Isolate via `Isolate.spawn` (or `compute` for one-off tasks).
- Long-running audio capture and ML inference pipelines must run in a persistent worker isolate controlled via bi-directional message ports (`SendPort` and `ReceivePort`).

### 2. UI Amplitude Streaming & Frame Budgeting
- Compute audio decibel/RMS amplitude values inside the background isolate.
- Communicate audio visualizer metrics to the UI thread using a lightweight `SendPort` stream throttled/capped at **30 FPS** (maximum 1 message every ~33ms).
- Avoid flooding the Flutter event loop with high-frequency audio chunk messages (e.g. 100+ callbacks/sec).

### 3. Native FFI & ONNX Memory Management
- **Always** free allocated native FFI memory (`calloc.free(ptr)`, `malloc.free(ptr)`) and ONNX tensor buffers explicitly within `try/finally` blocks.
- Wrap native session, environment, and tensor pointers in finalizable wrappers or register them with Dart `NativeFinalizer` to guard against unexpected isolate terminations.
- Explicitly release ONNX model inference outputs and tensors immediately after consuming prediction results.

---

## Core Pipeline Architecture

```
[Microphone Hardware]
        │ (16kHz, 16-bit Mono PCM)
        ▼
[Audio Stream / Record Plugin]
        │ (TransferableTypedData / Buffers)
        ▼
[Background Worker Isolate]
   ├── Audio Ring Buffer / Sliding Window (e.g., 512-sample chunks for Silero VAD)
   ├── Fast RMS / Decibel Calculator ───(Capped @ 30 FPS)───► [Main UI SendPort]
   └── ONNX Runtime FFI Engine
         ├── Pre-processing / Float32 normalization
         ├── Tensor Allocation (try/finally guarded)
         ├── Session Run (Inference)
         └── Speech Detection / VAD Event Emission ───────► [Main UI SendPort]
```

---

## Code Patterns & Best Practices

### Background Isolate Entry Point Setup
```dart
import 'dart:isolate';
import 'dart:typed_data';

class AudioIsolateInitParams {
  final SendPort uiSendPort;
  final RootIsolateToken rootToken;

  const AudioIsolateInitParams({
    required this.uiSendPort,
    required this.rootToken,
  });
}

void audioWorkerIsolateEntryPoint(AudioIsolateInitParams initParams) {
  // Initialize BackgroundIsolateBinaryMessenger for platform channels if needed
  BackgroundIsolateBinaryMessenger.ensureInitialized(initParams.rootToken);

  final commandReceivePort = ReceivePort();
  initParams.uiSendPort.send(commandReceivePort.sendPort);

  commandReceivePort.listen((message) {
    if (message is AudioBufferMessage) {
      _processAudioFrame(message.bytes, initParams.uiSendPort);
    } else if (message is StopCommand) {
      commandReceivePort.close();
      Isolate.current.kill();
    }
  });
}
```

### Safe FFI Tensor Allocation & Cleanup Pattern
```dart
void executeOnnxInference(Pointer<Float> inputBuffer, int length) {
  Pointer<OrtSession> session = nullptr;
  Pointer<OrtValue> inputTensor = nullptr;
  Pointer<OrtValue> outputTensor = nullptr;

  try {
    // 1. Allocate & bind tensors
    // ... setup OrtMemoryInfo and create OrtValue ...
    
    // 2. Run inference synchronously inside worker isolate
    // ... ortRun(...) ...

    // 3. Process output predictions
  } finally {
    // CRITICAL: Always clean up native FFI allocations and ONNX handles
    if (inputTensor != nullptr) {
      ortApi.ReleaseValue(inputTensor);
    }
    if (outputTensor != nullptr) {
      ortApi.ReleaseValue(outputTensor);
    }
    calloc.free(inputBuffer);
  }
}
```

### Throttling UI Amplitude Updates
```dart
int _lastUiEmitTimeMs = 0;

void emitAmplitudeIfNeeded(double rms, SendPort uiSendPort) {
  final now = DateTime.now().millisecondsSinceEpoch;
  // 30 FPS throttle ~ 33ms
  if (now - _lastUiEmitTimeMs >= 33) {
    _lastUiEmitTimeMs = now;
    uiSendPort.send(AmplitudeUpdate(rms));
  }
}
```
