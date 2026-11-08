import 'dart:typed_data';

/// Helper to generate and parse standard 44-byte RIFF WAV headers for 16-bit PCM audio.
abstract final class WavHeaderHelper {
  static const int headerSize = 44;

  /// Creates a standard 44-byte WAV header for the specified audio attributes.
  static Uint8List createWavHeader({
    required int pcmDataLength,
    required int sampleRate,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final totalDataLen = pcmDataLength + 36;

    final header = ByteData(headerSize);

    // 0..3: "RIFF"
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'

    // 4..7: Overall size - 8
    header.setUint32(4, totalDataLen, Endian.little);

    // 8..11: "WAVE"
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // 12..15: "fmt "
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '

    // 16..19: Subchunk1Size = 16 for PCM
    header.setUint32(16, 16, Endian.little);

    // 20..21: AudioFormat = 1 (Linear PCM)
    header.setUint16(20, 1, Endian.little);

    // 22..23: NumChannels
    header.setUint16(22, channels, Endian.little);

    // 24..27: SampleRate
    header.setUint32(24, sampleRate, Endian.little);

    // 28..31: ByteRate
    header.setUint32(28, byteRate, Endian.little);

    // 32..33: BlockAlign
    header.setUint16(32, blockAlign, Endian.little);

    // 34..35: BitsPerSample
    header.setUint16(34, bitsPerSample, Endian.little);

    // 36..39: "data"
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'

    // 40..43: Subchunk2Size = PCM data length
    header.setUint32(40, pcmDataLength, Endian.little);

    return header.buffer.asUint8List();
  }
}
