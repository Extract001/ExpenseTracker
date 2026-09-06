/// Reusable lightweight Async state representation for providers and UI.
sealed class AsyncValue<T> {
  const AsyncValue();

  const factory AsyncValue.initial() = AsyncInitial<T>;
  const factory AsyncValue.loading([T? previousData]) = AsyncLoading<T>;
  const factory AsyncValue.data(T data) = AsyncData<T>;
  const factory AsyncValue.error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) = AsyncError<T>;

  bool get isInitial => this is AsyncInitial<T>;
  bool get isLoading => this is AsyncLoading<T>;
  bool get hasData => this is AsyncData<T>;
  bool get hasError => this is AsyncError<T>;

  T? get dataOrNull {
    if (this is AsyncData<T>) {
      return (this as AsyncData<T>).data;
    }
    if (this is AsyncLoading<T>) {
      return (this as AsyncLoading<T>).previousData;
    }
    return null;
  }

  String? get errorOrNull {
    if (this is AsyncError<T>) {
      return (this as AsyncError<T>).message;
    }
    return null;
  }

  R when<R>({
    required R Function() initial,
    required R Function(T? previousData) loading,
    required R Function(T data) data,
    required R Function(String message, Object? error) error,
  }) {
    if (this is AsyncInitial<T>) {
      return initial();
    } else if (this is AsyncLoading<T>) {
      return loading((this as AsyncLoading<T>).previousData);
    } else if (this is AsyncData<T>) {
      return data((this as AsyncData<T>).data);
    } else if (this is AsyncError<T>) {
      final err = this as AsyncError<T>;
      return error(err.message, err.error);
    }
    throw StateError('Unknown AsyncValue subtype: $runtimeType');
  }

  R maybeWhen<R>({
    R Function()? initial,
    R Function(T? previousData)? loading,
    R Function(T data)? data,
    R Function(String message, Object? error)? error,
    required R Function() orElse,
  }) {
    if (this is AsyncInitial<T> && initial != null) {
      return initial();
    } else if (this is AsyncLoading<T> && loading != null) {
      return loading((this as AsyncLoading<T>).previousData);
    } else if (this is AsyncData<T> && data != null) {
      return data((this as AsyncData<T>).data);
    } else if (this is AsyncError<T> && error != null) {
      final err = this as AsyncError<T>;
      return error(err.message, err.error);
    }
    return orElse();
  }
}

class AsyncInitial<T> extends AsyncValue<T> {
  const AsyncInitial();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AsyncInitial<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AsyncValue<$T>.initial()';
}

class AsyncLoading<T> extends AsyncValue<T> {
  final T? previousData;
  const AsyncLoading([this.previousData]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AsyncLoading<T> && other.previousData == previousData);

  @override
  int get hashCode => Object.hash(runtimeType, previousData);

  @override
  String toString() => 'AsyncValue<$T>.loading(previousData: $previousData)';
}

class AsyncData<T> extends AsyncValue<T> {
  final T data;
  const AsyncData(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AsyncData<T> && other.data == data);

  @override
  int get hashCode => Object.hash(runtimeType, data);

  @override
  String toString() => 'AsyncValue<$T>.data($data)';
}

class AsyncError<T> extends AsyncValue<T> {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const AsyncError(this.message, [this.error, this.stackTrace]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AsyncError<T> &&
          other.message == message &&
          other.error == error);

  @override
  int get hashCode => Object.hash(runtimeType, message, error);

  @override
  String toString() => 'AsyncValue<$T>.error($message, error: $error)';
}
