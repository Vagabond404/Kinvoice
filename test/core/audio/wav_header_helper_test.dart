import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/audio/wav_header_helper.dart';

void main() {
  group('WavHeaderHelper Unit Tests', () {
    test('createWavHeader produces valid standard 44-byte RIFF WAV structure', () {
      const pcmLength = 32000; // 1 second of 16kHz 16-bit mono
      const sampleRate = 16000;

      final header = WavHeaderHelper.createWavHeader(
        pcmDataLength: pcmLength,
        sampleRate: sampleRate,
        channels: 1,
        bitsPerSample: 16,
      );

      expect(header.length, 44);

      // Check RIFF chunk
      final riffMarker = ascii.decode(header.sublist(0, 4));
      expect(riffMarker, 'RIFF');

      final byteData = ByteData.sublistView(header);
      final fileSizeMinus8 = byteData.getUint32(4, Endian.little);
      expect(fileSizeMinus8, pcmLength + 36);

      // Check WAVE marker
      final waveMarker = ascii.decode(header.sublist(8, 12));
      expect(waveMarker, 'WAVE');

      // Check "fmt " marker
      final fmtMarker = ascii.decode(header.sublist(12, 16));
      expect(fmtMarker, 'fmt ');

      // Subchunk1Size = 16
      expect(byteData.getUint32(16, Endian.little), 16);

      // AudioFormat = 1 (PCM)
      expect(byteData.getUint16(20, Endian.little), 1);

      // NumChannels = 1
      expect(byteData.getUint16(22, Endian.little), 1);

      // SampleRate = 16000
      expect(byteData.getUint32(24, Endian.little), 16000);

      // ByteRate = 16000 * 1 * 2 = 32000
      expect(byteData.getUint32(28, Endian.little), 32000);

      // BlockAlign = 2
      expect(byteData.getUint16(32, Endian.little), 2);

      // BitsPerSample = 16
      expect(byteData.getUint16(34, Endian.little), 16);

      // "data" marker
      final dataMarker = ascii.decode(header.sublist(36, 40));
      expect(dataMarker, 'data');

      // Subchunk2Size = pcmLength
      expect(byteData.getUint32(40, Endian.little), pcmLength);
    });
  });
}
