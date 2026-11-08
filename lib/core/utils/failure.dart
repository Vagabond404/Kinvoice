import 'package:flutter/foundation.dart';

/// Base class for all domain and operational failures in Kinvoice.
@immutable
sealed class Failure {
  const Failure(this.message, [this.cause, this.stackTrace]);

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    if (cause != null) {
      return '$runtimeType: $message (Caused by: $cause)';
    }
    return '$runtimeType: $message';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Failure &&
        other.runtimeType == runtimeType &&
        other.message == message &&
        other.cause == cause;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, cause);
}

/// Failure occurring during SQLite FTS5 database operations.
final class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, [super.cause, super.stackTrace]);
}

/// Failure occurring during native audio capture or circular buffer operations.
final class AudioCaptureFailure extends Failure {
  const AudioCaptureFailure(super.message, [super.cause, super.stackTrace]);
}

/// Failure occurring during on-device ONNX / VAD / ASR inference.
final class InferenceFailure extends Failure {
  const InferenceFailure(super.message, [super.cause, super.stackTrace]);
}

/// Failure occurring when required permissions (e.g. microphone) are missing or denied.
final class PermissionFailure extends Failure {
  const PermissionFailure(super.message, [super.cause, super.stackTrace]);
}

/// Failure occurring during file I/O or storage management.
final class StorageFailure extends Failure {
  const StorageFailure(super.message, [super.cause, super.stackTrace]);
}

/// Failure occurring during input validation or model parsing.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [super.cause, super.stackTrace]);
}

/// Fallback failure for unhandled or unexpected exceptions.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, [super.cause, super.stackTrace]);
}
