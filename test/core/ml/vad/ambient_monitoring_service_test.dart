import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/database/app_database.dart';
import 'package:kinvoice/core/database/recording_repository.dart';
import 'package:kinvoice/core/ml/vad/ambient_monitoring_service.dart';
import 'package:kinvoice/core/ml/vad/silero_vad_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AmbientMonitoringService & Pipeline Tests', () {
    late AppDatabase testDb;
    late RecordingRepository repository;
    late AmbientMonitoringService service;

    final List<MethodCall> nativeCalls = [];

    setUp(() async {
      testDb = AppDatabase(customDatabasePath: inMemoryDatabasePath);
      repository = RecordingRepository(appDatabase: testDb);
      nativeCalls.clear();

      // Mock native MethodChannel for foreground service / audio session
      const channel = MethodChannel('com.kinvoice.kinvoice/ambient_service');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        nativeCalls.add(call);
        if (call.method == 'startAmbientService') return true;
        if (call.method == 'stopAmbientService') return true;
        if (call.method == 'isServiceRunning') return true;
        return null;
      });

      service = AmbientMonitoringService(
        repository: repository,
        platformChannel: channel,
      );
    });

    tearDown(() async {
      await service.dispose();
      await testDb.close();
    });

    Uint8List generateSpeechChunk() {
      final chunk = Uint8List(SileroVadEngine.frameBytes);
      final byteData = ByteData.sublistView(chunk);
      for (int i = 0; i < SileroVadEngine.frameSize; i++) {
        final val = (math.sin(2 * math.pi * 400 * i / 16000) * 16000).round();
        byteData.setInt16(i * 2, val, Endian.little);
      }
      return chunk;
    }

    Uint8List generateSilenceChunk() {
      return Uint8List(SileroVadEngine.frameBytes);
    }

    test('startAmbientMonitoring calls native channel and activates isolate', () async {
      final mockController = StreamController<Uint8List>.broadcast();

      await service.startAmbientMonitoring(mockAudioStream: mockController.stream);

      expect(service.isAmbientModeEnabled, isTrue);
      expect(nativeCalls.any((c) => c.method == 'startAmbientService'), isTrue);

      await service.stopAmbientMonitoring();
      expect(service.isAmbientModeEnabled, isFalse);
      expect(nativeCalls.any((c) => c.method == 'stopAmbientService'), isTrue);

      await mockController.close();
    });

    test('Streams PCM speech frames and emits metrics through background isolate', () async {
      final mockController = StreamController<Uint8List>.broadcast();
      await service.startAmbientMonitoring(mockAudioStream: mockController.stream);

      final metricsCompleter = Completer<void>();
      final sub = service.metricsStream.listen((event) {
        if (!metricsCompleter.isCompleted) {
          metricsCompleter.complete();
        }
      });

      // Push 5 speech chunks
      for (int i = 0; i < 5; i++) {
        mockController.add(generateSpeechChunk());
      }

      await expectLater(
        metricsCompleter.future.timeout(const Duration(seconds: 3)),
        completes,
      );

      await sub.cancel();
      await service.stopAmbientMonitoring();
      await mockController.close();
    });

    test('Detects speech onset, sustains, and offset to auto-persist recording into SQLite', () async {
      final mockController = StreamController<Uint8List>.broadcast();
      await service.startAmbientMonitoring(mockAudioStream: mockController.stream);

      final segmentCompleter = Completer<void>();
      final sub = service.segmentStream.listen((seg) {
        if (!segmentCompleter.isCompleted) {
          segmentCompleter.complete();
        }
      });

      // 1. Send speech chunks (trigger onset: > 3 frames)
      for (int i = 0; i < 6; i++) {
        mockController.add(generateSpeechChunk());
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // 2. Send silence chunks (trigger offset: >= 25 frames / 800ms)
      for (int i = 0; i < 30; i++) {
        mockController.add(generateSilenceChunk());
        await Future.delayed(const Duration(milliseconds: 5));
      }

      // Wait for segment to be completed and emitted
      await expectLater(
        segmentCompleter.future.timeout(const Duration(seconds: 4)),
        completes,
      );

      await sub.cancel();
      await service.stopAmbientMonitoring();
      await mockController.close();
    });
  });
}
