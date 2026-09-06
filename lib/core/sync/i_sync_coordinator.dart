import 'sync_types.dart';

/// Contract for the cloud synchronization engine.
abstract class ISyncCoordinator {
  /// Stream emitting real-time changes to the sync engine state.
  Stream<SyncEngineState> get syncStateStream;

  /// Current state of the sync engine.
  SyncEngineState get currentState;

  /// Stream emitting real-time batch progress metrics.
  Stream<SyncProgress> get progressStream;

  /// Result of the most recent synchronization run.
  SyncResult? get lastSyncResult;

  /// Timestamp of the last successful synchronization in UTC.
  DateTime? get lastSyncTimeUtc;

  /// Initiates a synchronization cycle (Push pending operations -> Pull remote updates).
  Future<SyncResult> synchronize({bool force = false});

  /// Migrates all local records, settings, and pending queue operations
  /// from a guest user to an authenticated cloud user inside an atomic database transaction.
  Future<void> migrateGuestData({
    required String guestUserId,
    required String targetUserId,
  });

  /// Retrieves the current pending operations count for a given user.
  Future<int> getPendingOperationsCount(String userId);

  /// Immediately cancels/aborts any active synchronization loop.
  void abortActiveSync();

  /// Cleans up subscriptions, resources, and background timers.
  void dispose();
}
