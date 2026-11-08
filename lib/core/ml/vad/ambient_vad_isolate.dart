import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../vad/battery_optimization_policy.dart';
import '../vad/silero_vad_engine.dart';
import '../vad/speech_state_machine.dart';
import '../../audio/rms_calculator.dart';

// ---------------------------------------------------------------------------
// Ambient Worker Commands (Main UI -> Background Isolate)
// ---------------------------------------------------------------------------

@immutable
sealed class AmbientIsolateCommand {
  const AmbientIsolateCommand();
}

final class StartAmbientCommand extends AmbientIsolateCommand {
  const StartAmbientCommand({
    this.modelPath,
    this.sampleRate = 16000,
  });

  final String? modelPath;
  final int sampleRate;
}

final class PushAudioChunkCommand extends AmbientIsolateCommand {
  const PushAudioChunkCommand(this.pcmChunk);

  final Uint8List pcmChunk;
}

final class PauseAmbientCommand extends AmbientIsolateCommand {
  const PauseAmbientCommand();
}

final class ResumeAmbientCommand extends AmbientIsolateCommand {
  const ResumeAmbientCommand();
}

final class StopAmbientCommand extends AmbientIsolateCommand {
  const StopAmbientCommand();
}

// ---------------------------------------------------------------------------
// Ambient Worker Events (Background Isolate -> Main UI)
// ---------------------------------------------------------------------------

@immutable
sealed class AmbientIsolateEvent {
  const AmbientIsolateEvent();
}

final class AmbientReadyEvent extends AmbientIsolateEvent {
  const AmbientReadyEvent(this.commandSendPort);

  final SendPort commandSendPort;
}

final class AmbientMetricsEvent extends AmbientIsolateEvent {
  const AmbientMetricsEvent({
    required this.voiceProbability,
    required this.rmsEnergy,
    required this.isSpeaking,
    required this.powerMode,
  });

  final double voiceProbability;
  final double rmsEnergy;
  final bool isSpeaking;
  final AmbientPowerMode powerMode;
}

final class AmbientSegmentCompletedEvent extends AmbientIsolateEvent {
  const AmbientSegmentCompletedEvent(this.segment);

  final SpeechSegment segment;
}

final class AmbientErrorEvent extends AmbientIsolateEvent {
  const AmbientErrorEvent(this.errorMessage);

  final String errorMessage;
}

// ---------------------------------------------------------------------------
// Ambient Isolate Controller
// ---------------------------------------------------------------------------

/// Controller managing the persistent background worker Isolate for Silero VAD.
class AmbientVadIsolateController {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _commandSendPort;

  final StreamController<AmbientIsolateEvent> _eventController =
      StreamController<AmbientIsolateEvent>.broadcast();

  Stream<AmbientIsolateEvent> get events => _eventController.stream;
  bool get isRunning => _isolate != null;

  /// Spawns the dedicated background worker isolate.
  Future<void> start({String? modelPath}) async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();
    final readyCompleter = Completer<void>();

    _isolate = await Isolate.spawn(
      _ambientWorkerIsolateEntryPoint,
      _receivePort!.sendPort,
      debugName: 'KinvoiceAmbientVadWorker',
    );

    _receivePort!.listen((message) {
      if (message is AmbientReadyEvent) {
        _commandSendPort = message.commandSendPort;
        _commandSendPort?.send(StartAmbientCommand(modelPath: modelPath));
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      } else if (message is AmbientIsolateEvent) {
        _eventController.add(message);
      }
    });

    await readyCompleter.future;
  }

  /// Pushes a chunk of 16kHz PCM audio into the worker isolate.
  void pushChunk(Uint8List chunk) {
    _commandSendPort?.send(PushAudioChunkCommand(chunk));
  }

  /// Pauses processing.
  void pause() {
    _commandSendPort?.send(const PauseAmbientCommand());
  }

  /// Resumes processing.
  void resume() {
    _commandSendPort?.send(const ResumeAmbientCommand());
  }

  /// Terminates the isolate and cleans up resources.
  Future<void> dispose() async {
    _commandSendPort?.send(const StopAmbientCommand());
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandSendPort = null;
    await _eventController.close();
  }
}

// ---------------------------------------------------------------------------
// Background Worker Entry Point
// ---------------------------------------------------------------------------

void _ambientWorkerIsolateEntryPoint(SendPort uiSendPort) {
  final commandPort = ReceivePort();
  uiSendPort.send(AmbientReadyEvent(commandPort.sendPort));

  SileroVadEngine? vadEngine;
  final stateMachine = SpeechStateMachine();
  final batteryPolicy = BatteryOptimizationPolicy();

  // Accumulation ring buffer to slice arbitrary input buffers into 512-sample (1024-byte) frames
  final frameAccumulator = BytesBuilder(copy: false);
  const int frameBytes = SileroVadEngine.frameBytes;

  bool isPaused = false;
  int lastMetricsEmitTimeMs = 0;

  commandPort.listen((message) {
    if (message is StartAmbientCommand) {
      if (message.modelPath != null) {
        vadEngine = SileroVadEngine.createOnnx(
          modelPath: message.modelPath!,
          sampleRate: message.sampleRate,
        );
      } else {
        vadEngine = SileroVadEngine(sampleRate: message.sampleRate);
      }
      isPaused = false;
    } else if (message is PauseAmbientCommand) {
      isPaused = true;
    } else if (message is ResumeAmbientCommand) {
      isPaused = false;
    } else if (message is PushAudioChunkCommand) {
      if (isPaused || vadEngine == null) return;

      frameAccumulator.add(message.pcmChunk);
      final currentBytes = frameAccumulator.toBytes();
      frameAccumulator.clear();

      int offset = 0;
      while (offset + frameBytes <= currentBytes.length) {
        final frame = Uint8List.sublistView(currentBytes, offset, offset + frameBytes);
        offset += frameBytes;

        final rms = RmsCalculator.calculateNormalizedRms(frame);
        final shouldInfer = batteryPolicy.shouldProcessInference(
          isSpeaking: stateMachine.isSpeaking,
          rmsEnergy: rms,
        );

        double prob = 0.0;
        if (shouldInfer) {
          prob = vadEngine!.processPcmBytes(frame);
        }

        // Process through speech onset/offset state machine
        final completedSegment = stateMachine.processFrame(
          pcmChunk: frame,
          voiceProbability: prob,
        );

        if (completedSegment != null) {
          uiSendPort.send(AmbientSegmentCompletedEvent(completedSegment));
          vadEngine!.resetState();
        }

        // Emit live UI metrics throttled to 30 FPS (~33ms)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastMetricsEmitTimeMs >= 33) {
          lastMetricsEmitTimeMs = now;
          uiSendPort.send(
            AmbientMetricsEvent(
              voiceProbability: prob,
              rmsEnergy: rms,
              isSpeaking: stateMachine.isSpeaking,
              powerMode: batteryPolicy.powerMode,
            ),
          );
        }
      }

      // Re-add leftover unaligned bytes back into accumulator
      if (offset < currentBytes.length) {
        frameAccumulator.add(
          Uint8List.sublistView(currentBytes, offset, currentBytes.length),
        );
      }
    } else if (message is StopAmbientCommand) {
      final flushSegment = stateMachine.flush();
      if (flushSegment != null) {
        uiSendPort.send(AmbientSegmentCompletedEvent(flushSegment));
      }
      vadEngine?.dispose();
      commandPort.close();
      Isolate.current.kill();
    }
  });
}
