import 'sync_cursor.dart';

/// Contract for communicating with the remote cloud synchronization backend (Supabase).
abstract class ISyncRemoteDataSource {
  /// Dispatches an atomic mutation operation to the server RPC `apply_sync_mutation`.
  ///
  /// Returns a map with `status` (`'applied'`, `'already_processed'`, or error details).
  Future<Map<String, dynamic>> applySyncMutation({
    required String operationId,
    required String entityType,
    required String entityId,
    required String operationType,
    required Map<String, dynamic> payload,
    required Map<String, String> fieldTimestamps,
    required DateTime updatedAtUtc,
    DateTime? deletedAtUtc,
  });

  /// Fetches an incremental page of records for [entityType] updated after [cursor].
  ///
  /// Records are deterministically ordered by `updated_at_utc ASC, id ASC`.
  Future<List<Map<String, dynamic>>> pullEntities({
    required String userId,
    required String entityType,
    SyncCursor? cursor,
    int limit = 50,
  });
}
