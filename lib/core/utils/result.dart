import 'package:flutter/foundation.dart';
import 'failure.dart';

/// A robust algebraic Result type representing either a successful outcome of type [T]
/// or an operation failure of type [E] extending [Failure].
@immutable
sealed class Result<T, E extends Failure> {
  const Result();

  /// Creates a successful [Result] holding a [value].
  const factory Result.success(T value) = Success<T, E>;

  /// Creates an error [Result] holding a [failure].
  const factory Result.error(E failure) = Error<T, E>;

  /// Returns true if this instance represents a successful outcome.
  bool get isSuccess => this is Success<T, E>;

  /// Returns true if this instance represents an error outcome.
  bool get isError => this is Error<T, E>;

  /// Extracts the underlying value if successful, or returns null.
  T? getOrNull() {
    return switch (this) {
      Success(value: final v) => v,
      Error() => null,
    };
  }

  /// Extracts the underlying value if successful, or returns [fallback].
  T getOrElse(T Function() fallback) {
    return switch (this) {
      Success(value: final v) => v,
      Error() => fallback(),
    };
  }

  /// Transforms the value using [transform] if successful, returning a new [Result].
  Result<R, E> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success(value: final v) => Result.success(transform(v)),
      Error(failure: final f) => Result.error(f),
    };
  }

  /// Monadic flatMap: chains another operation returning a [Result].
  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) {
    return switch (this) {
      Success(value: final v) => transform(v),
      Error(failure: final f) => Result.error(f),
    };
  }

  /// Pattern-matches over both branches: executing [onSuccess] on success,
  /// or [onError] on error.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(E failure) onError,
  }) {
    return switch (this) {
      Success(value: final v) => onSuccess(v),
      Error(failure: final f) => onError(f),
    };
  }
}

/// Success branch of [Result].
final class Success<T, E extends Failure> extends Result<T, E> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Success<T, E> && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Result.success($value)';
}

/// Error branch of [Result].
final class Error<T, E extends Failure> extends Result<T, E> {
  const Error(this.failure);

  final E failure;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Error<T, E> && other.failure == failure;
  }

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Result.error($failure)';
}
