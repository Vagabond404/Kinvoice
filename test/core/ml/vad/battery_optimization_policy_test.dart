import 'package:flutter_test/flutter_test.dart';
import 'package:kinvoice/core/ml/vad/battery_optimization_policy.dart';

void main() {
  group('BatteryOptimizationPolicy Unit Tests', () {
    late BatteryOptimizationPolicy policy;
    final baseTime = DateTime(2026, 11, 8, 12, 0, 0);

    setUp(() {
      policy = BatteryOptimizationPolicy(
        maxSilenceBeforeSleep: const Duration(seconds: 30),
        sleepThrottleFactor: 3,
        wakeEnergyThreshold: 0.05,
      );
    });

    test('Initial power mode is active and processes all frames', () {
      expect(policy.powerMode, AmbientPowerMode.active);
      expect(policy.isSleeping, isFalse);

      final shouldInfer = policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: baseTime,
      );
      expect(shouldInfer, isTrue);
    });

    test('Silence under 30 seconds maintains active mode', () {
      // 25 seconds later
      final t25 = baseTime.add(const Duration(seconds: 25));
      final shouldInfer = policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: t25,
      );

      expect(policy.powerMode, AmbientPowerMode.active);
      expect(shouldInfer, isTrue);
    });

    test('Silence exceeding 30 seconds triggers sleep cycle and CPU throttling', () {
      // Start tracking silence
      policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: baseTime,
      );

      // 31 seconds later -> enters sleep mode (1st frame in sleep: skipped)
      final t31 = baseTime.add(const Duration(seconds: 31));
      final f1 = policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: t31,
      );

      expect(policy.powerMode, AmbientPowerMode.sleep);
      expect(policy.isSleeping, isTrue);
      expect(f1, isFalse); // Frame 1: skipped

      // Test CPU throttling in sleep (throttleFactor = 3: skip 2, process 1)
      final f2 = policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: t31.add(const Duration(milliseconds: 32)),
      );
      expect(f2, isFalse); // Frame 2: skipped

      final f3 = policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: t31.add(const Duration(milliseconds: 64)),
      );
      expect(f3, isTrue); // Frame 3: processed (1 in every 3 frames)
    });

    test('High acoustic energy above wakeEnergyThreshold immediately wakes policy from sleep', () {
      // Enter sleep
      policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: baseTime,
      );
      final t35 = baseTime.add(const Duration(seconds: 35));
      policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.01,
        timestamp: t35,
      );
      expect(policy.isSleeping, isTrue);

      // Loud sound occurs (e.g. user begins speaking: energy 0.12 > threshold 0.05)
      final shouldInfer = policy.shouldProcessInference(
        isSpeaking: false,
        rmsEnergy: 0.12,
        timestamp: t35.add(const Duration(milliseconds: 32)),
      );

      expect(shouldInfer, isTrue);
      expect(policy.powerMode, AmbientPowerMode.active);
      expect(policy.isSleeping, isFalse);
    });

    test('Speech onset immediately resets sleep timer and preserves active mode', () {
      policy.shouldProcessInference(
        isSpeaking: true,
        rmsEnergy: 0.2,
        timestamp: baseTime,
      );
      expect(policy.powerMode, AmbientPowerMode.active);

      policy.wakeUp();
      expect(policy.powerMode, AmbientPowerMode.active);
    });
  });
}
