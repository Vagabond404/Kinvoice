import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'rms_calculator.dart';
import 'wav_header_helper.dart';

// ---------------------------------------------------------------------------
// Isolate Commands (Main UI -> Background Isolate)
// ---------------------------------------------------------------------------

@immutable
sealed class AudioIsolateCommand {
  const AudioIsolateCommand();
}

final class StartCaptureCommand extends AudioIsolateCommand {
  const StartCaptureCommand({
    required this.outputPath,
    this.sampleRate = 16000,
  });

  final String outputPath;
  final int sampleRate;
}

final class ProcessChunkCommand extends AudioIsolateCommand {
  const ProcessChunkCommand(this.pcmChunk);

  final Uint8List pcmChunk;
}

final class PauseCaptureCommand extends AudioIsolateCommand {
  const PauseCaptureCommand();
}

final class ResumeCaptureCommand extends AudioIsolateCommand {
  const ResumeCaptureCommand();
}

final class StopCaptureCommand extends AudioIsolateCommand {
  const StopCaptureCommand();
}

final class CancelCaptureCommand extends AudioIsolateCommand {
  const CancelCaptureCommand();
}

// ---------------------------------------------------------------------------
// Isolate Events (Background Isolate -> Main UI)
// ---------------------------------------------------------------------------

@immutable
sealed class AudioIsolateEvent {
  const AudioIsolateEvent();
}

final class IsolateReadyEvent extends AudioIsolateEvent {
  const IsolateReadyEvent(this.commandSendPort);

  final SendPort commandSendPort;
}

final class IsolateMetricsEvent extends AudioIsolateEvent {
  const IsolateMetricsEvent({
    required this.rms,
    required this.isVoiceDetected,
    required this.elapsed,
  });

  final double rms;
  final bool isVoiceDetected;
  final Duration elapsed;
}

final class IsolateFinishedEvent extends AudioIsolateEvent {
  const IsolateFinishedEvent({
    required this.wavFilePath,
    required this.totalBytes,
    required this.duration,
  });

  final String wavFilePath;
  final int totalBytes;
  final Duration duration;
}

final class IsolateErrorEvent extends AudioIsolateEvent {
  const IsolateErrorEvent(this.message);

  final String message;
}

// ---------------------------------------------------------------------------
// Worker Isolate Controller & Entry Point
// ---------------------------------------------------------------------------

/// Manager for the dedicated background audio worker isolate.
class AudioCaptureIsolateController {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _commandSendPort;

  final StreamController<AudioIsolateEvent> _eventController =
      StreamController<AudioIsolateEvent>.broadcast();

  Stream<AudioIsolateEvent> get events => _eventController.stream;

  /// Spawns the dedicated background Isolate.
  Future<void> start() async {
    _receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _audioWorkerIsolateEntryPoint,
      _receivePort!.sendPort,
      debugName: 'KinvoiceAudioWorker',
    );

    final readyCompleter = Completer<void>();

    _receivePort!.listen((message) {
      if (message is IsolateReadyEvent) {
        _commandSendPort = message.commandSendPort;
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }
      if (message is AudioIsolateEvent) {
        _eventController.add(message);
      }
    });

    await readyCompleter.future;
  }

  /// Sends a command to the background isolate.
  void sendCommand(AudioIsolateCommand command) {
    _commandSendPort?.send(command);
  }

  /// Terminates the isolate and cleans up resources.
  Future<void> dispose() async {
    _commandSendPort?.send(const CancelCaptureCommand());
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    await _eventController.close();
  }
}

/// The entry point function executing in the background Isolate.
void _audioWorkerIsolateEntryPoint(SendPort uiSendPort) {
  final commandPort = ReceivePort();
  uiSendPort.send(IsolateReadyEvent(commandPort.sendPort));

  IOSink? fileSink;
  File? outputFile;
  int sampleRate = 16000;
  int totalPcmBytes = 0;
  bool isPaused = false;
  int lastMetricsEmitTimeMs = 0;
  final stopwatch = Stopwatch();

  commandPort.listen((message) async {
    if (message is StartCaptureCommand) {
      sampleRate = message.sampleRate;
      outputFile = File(message.outputPath);
      totalPcmBytes = 0;
      isPaused = false;

      try {
        // Leave 44 bytes placeholder space for the standard WAV header
        if (await outputFile!.exists()) {
          await outputFile!.delete();
        }
        fileSink = outputFile!.openWrite(mode: FileMode.writeOnly);
        final emptyHeader = Uint8List(WavHeaderHelper.headerSize);
        fileSink!.add(emptyHeader);
        stopwatch.reset();
        stopwatch.start();
      } catch (e) {
        uiSendPort.send(IsolateErrorEvent('Failed to initialize audio file: $e'));
      }
    } else if (message is ProcessChunkCommand) {
      if (isPaused || fileSink == null) return;

      final chunk = message.pcmChunk;
      if (chunk.isEmpty) return;

      // 1. Write chunk to disk asynchronously inside background isolate
      fileSink!.add(chunk);
      totalPcmBytes += chunk.length;

      // 2. Compute RMS amplitude
      final rms = RmsCalculator.calculateNormalizedRms(chunk);
      final isVoice = RmsCalculator.isVoiceDetected(rms);

      // 3. Emit metrics throttled to 30 FPS (~33ms intervals)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastMetricsEmitTimeMs >= 33) {
        lastMetricsEmitTimeMs = now;
        uiSendPort.send(
          IsolateMetricsEvent(
            rms: rms,
            isVoiceDetected: isVoice,
            elapsed: stopwatch.elapsed,
          ),
        );
      }
    } else if (message is PauseCaptureCommand) {
      isPaused = true;
      stopwatch.stop();
    } else if (message is ResumeCaptureCommand) {
      isPaused = false;
      stopwatch.start();
    } else if (message is StopCaptureCommand) {
      stopwatch.stop();
      if (fileSink != null && outputFile != null) {
        try {
          await fileSink!.flush();
          await fileSink!.close();
          fileSink = null;

          // Prepend RIFF WAV header with exact PCM byte length
          final wavHeader = WavHeaderHelper.createWavHeader(
            pcmDataLength: totalPcmBytes,
            sampleRate: sampleRate,
            channels: 1,
            bitsPerSample: 16,
          );

          final randomAccess = await outputFile!.open(mode: FileMode.append);
          await randomAccess.setPosition(0);
          await randomAccess.writeFrom(wavHeader);
          await randomAccess.close();

          final duration = Duration(
            milliseconds: (totalPcmBytes / (sampleRate * 2) * 1000).round(),
          );

          uiSendPort.send(
            IsolateFinishedEvent(
              wavFilePath: outputFile!.path,
              totalBytes: totalPcmBytes + WavHeaderHelper.headerSize,
              duration: duration,
            ),
          );
        } catch (e) {
          uiSendPort.send(IsolateErrorEvent('Failed to finalize WAV header: $e'));
        }
      }
    } else if (message is CancelCaptureCommand) {
      stopwatch.stop();
      if (fileSink != null) {
        await fileSink!.close();
        fileSink = null;
      }
      if (outputFile != null && await outputFile!.exists()) {
        try {
          await outputFile!.delete();
        } catch (_) {}
      }
    }
  });
}
