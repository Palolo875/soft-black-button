/// A standard wrapper for operation results that can either succeed with a value
/// or fail with an error.
/// 
/// Encourages explicit error handling across the application.
sealed class Result<T> {
  const Result();

  factory Result.success(T value) = Success<T>;
  factory Result.failure(Object error, [StackTrace? stackTrace]) = Failure<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get valueOrNull => (this is Success<T>) ? (this as Success<T>).value : null;

  Object? get errorOrNull => (this is Failure<T>) ? (this as Failure<T>).error : null;

  /// Transformation of the internal value if successful.
  Result<R> map<R>(R Function(T value) transform) {
    if (this is Success<T>) {
      return Result.success(transform((this as Success<T>).value));
    } else {
      final f = this as Failure<T>;
      return Result.failure(f.error, f.stackTrace);
    }
  }

  /// Pattern matching helper.
  R when<R>({
    required R Function(T value) success,
    required R Function(Object error, StackTrace? stackTrace) failure,
  }) {
    if (this is Success<T>) {
      return success((this as Success<T>).value);
    } else {
      final f = this as Failure<T>;
      return failure(f.error, f.stackTrace);
    }
  }
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

class Failure<T> extends Result<T> {
  final Object error;
  final StackTrace? stackTrace;
  const Failure(this.error, [this.stackTrace]);
}
