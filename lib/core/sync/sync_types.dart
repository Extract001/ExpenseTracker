import '../../domain/entities/enums.dart';

/// Represents high-level state of the synchronization coordinator.
enum SyncEngineState {
  idle,
  syncing,
  offline,
  error,
  paused;

  bool get isSyncing => this == SyncEngineState.syncing;
  bool get isOffline => this == SyncEngineState.offline;
  bool get isIdle => this == SyncEngineState.idle;
}

/// Progress metrics during an active synchronization batch.
class SyncProgress {
  final int totalOperations;
  final int completedOperations;
  final EntityType? currentEntity;
  final String? currentOperationId;

  const SyncProgress({
    this.totalOperations = 0,
    this.completedOperations = 0,
    this.currentEntity,
    this.currentOperationId,
  });

  double get percentage =>
      totalOperations > 0 ? (completedOperations / totalOperations) : 1.0;

  SyncProgress copyWith({
    int? totalOperations,
    int? completedOperations,
    EntityType? currentEntity,
    String? currentOperationId,
  }) {
    return SyncProgress(
      totalOperations: totalOperations ?? this.totalOperations,
      completedOperations: completedOperations ?? this.completedOperations,
      currentEntity: currentEntity ?? this.currentEntity,
      currentOperationId: currentOperationId ?? this.currentOperationId,
    );
  }
}

/// Result summary of a synchronization attempt.
class SyncResult {
  final bool success;
  final int pushedCount;
  final int pulledCount;
  final int conflictsResolvedCount;
  final String? errorMessage;
  final DateTime timestampUtc;

  const SyncResult({
    required this.success,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.conflictsResolvedCount = 0,
    this.errorMessage,
    required this.timestampUtc,
  });

  factory SyncResult.success({
    int pushed = 0,
    int pulled = 0,
    int conflicts = 0,
  }) {
    return SyncResult(
      success: true,
      pushedCount: pushed,
      pulledCount: pulled,
      conflictsResolvedCount: conflicts,
      timestampUtc: DateTime.now().toUtc(),
    );
  }

  factory SyncResult.failure(String errorMessage) {
    return SyncResult(
      success: false,
      errorMessage: errorMessage,
      timestampUtc: DateTime.now().toUtc(),
    );
  }

  @override
  String toString() =>
      'SyncResult(success: $success, pushed: $pushedCount, pulled: $pulledCount, conflicts: $conflictsResolvedCount, error: $errorMessage)';
}

/// Result of field-level conflict reconciliation.
class FieldConflictResult {
  final Map<String, dynamic> mergedPayload;
  final Map<String, String> mergedFieldTimestamps;
  final int fieldsUpdatedFromRemote;
  final int fieldsRetainedFromLocal;
  final List<String> resolvedFieldNames;

  const FieldConflictResult({
    required this.mergedPayload,
    required this.mergedFieldTimestamps,
    this.fieldsUpdatedFromRemote = 0,
    this.fieldsRetainedFromLocal = 0,
    this.resolvedFieldNames = const [],
  });
}
