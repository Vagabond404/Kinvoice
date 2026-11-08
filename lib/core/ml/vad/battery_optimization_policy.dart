/// Power modes orchestrating CPU throttling and energy conservation.
enum AmbientPowerMode {
  /// Full-rate 32ms VAD inference and audio analysis.
  active,

  /// Low-power throttled mode engaged after extended silence.
  sleep,
}

/// Manages battery conservation protocols for continuous ambient listening.
/// Transitions to [AmbientPowerMode.sleep] when silence exceeds 30 seconds,
/// throttling inference frequency and pruning idle buffers.
class BatteryOptimizationPolicy {
  BatteryOptimizationPolicy({
    this.maxSilenceBeforeSleep = const Duration(seconds: 30),
    this.sleepThrottleFactor = 3, // In sleep, evaluate 1 in every 3 frames
    this.wakeEnergyThreshold = 0.04, // Fast acoustic wakeup threshold
  });

  final Duration maxSilenceBeforeSleep;
  final int sleepThrottleFactor;
  final double wakeEnergyThreshold;

  AmbientPowerMode _powerMode = AmbientPowerMode.active;
  int _sleepFrameSkipCounter = 0;
  DateTime? _lastSpeechTime;

  AmbientPowerMode get powerMode => _powerMode;
  bool get isSleeping => _powerMode == AmbientPowerMode.sleep;

  /// Informs policy of the current frame's speech state and acoustic energy.
  /// Returns true if this frame should execute full ONNX inference,
  /// or false if the frame can be throttled (skipped).
  bool shouldProcessInference({
    required bool isSpeaking,
    required double rmsEnergy,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();

    if (isSpeaking) {
      _lastSpeechTime = now;
      if (_powerMode == AmbientPowerMode.sleep) {
        _powerMode = AmbientPowerMode.active;
      }
      return true;
    }

    // Silence tracking
    _lastSpeechTime ??= now;
    final silenceDuration = now.difference(_lastSpeechTime!);

    if (silenceDuration >= maxSilenceBeforeSleep) {
      _powerMode = AmbientPowerMode.sleep;
    }

    if (_powerMode == AmbientPowerMode.sleep) {
      // Immediate wakeup if raw acoustic energy spikes
      if (rmsEnergy > wakeEnergyThreshold) {
        _powerMode = AmbientPowerMode.active;
        _sleepFrameSkipCounter = 0;
        return true;
      }

      // Throttle CPU: process only 1 out of sleepThrottleFactor frames
      _sleepFrameSkipCounter++;
      if (_sleepFrameSkipCounter >= sleepThrottleFactor) {
        _sleepFrameSkipCounter = 0;
        return true;
      }
      return false;
    }

    return true;
  }

  /// Manually forces active wakeup.
  void wakeUp() {
    _powerMode = AmbientPowerMode.active;
    _sleepFrameSkipCounter = 0;
    _lastSpeechTime = DateTime.now();
  }

  /// Resets policy tracking.
  void reset() {
    _powerMode = AmbientPowerMode.active;
    _sleepFrameSkipCounter = 0;
    _lastSpeechTime = null;
  }
}
