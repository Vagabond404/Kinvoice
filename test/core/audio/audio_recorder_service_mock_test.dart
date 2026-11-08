import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/audio_recorder_service.dart';
import 'package:kinvoice/core/audio/wav_header_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioRecorderService Mocked Audio Pipeline Tests', () {
    late Directory tempTestDir;
    late AudioRecorderService service;

    setUp(() async {
      tempTestDir = await Directory.systemTemp.createTemp('kinvoice_audio_test_');
      service = AudioRecorderService();
    });

    tearDown(() async {
      await service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (await tempTestDir.exists()) {
        try {
          await tempTestDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('Streams synthetic 16kHz PCM chunks through background Isolate to valid WAV', () async {
      final targetWavPath = '${tempTestDir.path}/test_output.wav';
      final streamController = StreamController<Uint8List>();

      final startResult = await service.startRecording(
        customPath: targetWavPath,
        mockAudioStream: streamController.stream,
      );

      expect(startResult.isSuccess, isTrue);
      expect(service.isRecording, isTrue);
      expect(service.isPaused, isFalse);

      final List<double> capturedAmplitudes = [];
      final List<bool> capturedVoiceStates = [];

      final ampSub = service.amplitudeStream.listen(capturedAmplitudes.add);
      final voiceSub = service.voiceDetectedStream.listen(capturedVoiceStates.add);

      // Generate 4 chunks of 16kHz mono audio (each 320 bytes = 10ms = 160 samples)
      for (int c = 0; c < 4; c++) {
        final chunk = Uint8List(320);
        final byteData = ByteData.sublistView(chunk);
        for (int i = 0; i < 160; i++) {
          final sampleFloat = 0.6 * math.sin(2 * math.pi * 440 * (i / 16000));
          final sampleInt = (sampleFloat * 32767).round().clamp(-32768, 32767);
          byteData.setInt16(i * 2, sampleInt, Endian.little);
        }
        streamController.add(chunk);
        // Small delay to simulate real-time interval
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Test Pause / Resume cycle
      final pauseResult = await service.pauseRecording();
      expect(pauseResult.isSuccess, isTrue);
      expect(service.isPaused, isTrue);

      final resumeResult = await service.resumeRecording();
      expect(resumeResult.isSuccess, isTrue);
      expect(service.isPaused, isFalse);

      await streamController.close();

      // Stop recording and finalize WAV file
      final stopResult = await service.stopRecording();
      expect(stopResult.isSuccess, isTrue);
      expect(service.isRecording, isFalse);

      await ampSub.cancel();
      await voiceSub.cancel();

      // Verify Output File Exists and Contains RIFF WAV Header
      final file = File(targetWavPath);
      expect(await file.exists(), isTrue);

      final fileBytes = await file.readAsBytes();
      expect(fileBytes.length, greaterThanOrEqualTo(WavHeaderHelper.headerSize));

      // Verify RIFF & WAVE markers
      final riffMarker = String.fromCharCodes(fileBytes.sublist(0, 4));
      final waveMarker = String.fromCharCodes(fileBytes.sublist(8, 12));
      expect(riffMarker, 'RIFF');
      expect(waveMarker, 'WAVE');

      // Verify captured amplitudes received via 30 FPS throttle
      expect(capturedAmplitudes, isNotEmpty);
      expect(capturedAmplitudes.any((a) => a > 0.0), isTrue);
    });
  });
}
