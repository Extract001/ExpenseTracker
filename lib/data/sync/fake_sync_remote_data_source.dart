import '../../core/errors/app_exception.dart';
import '../../core/sync/conflict_resolver.dart';
import '../../core/sync/i_sync_remote_data_source.dart';
import '../../core/sync/sync_cursor.dart';

/// In-memory cloud simulation of the Supabase PostgreSQL backend.
///
/// Accurately simulates Row-Level Security, the `apply_sync_mutation` RPC procedure,
/// operation idempotency logging, 5-minute clock skew clamping, field-level LWW,
/// and deterministic composite cursor pagination (`ORDER BY updated_at_utc ASC, id ASC`).
class FakeSyncRemoteDataSource implements ISyncRemoteDataSource {
  /// Stores cloud tables: `tableName -> {recordId: Map<String, dynamic>}`
  final Map<String, Map<String, Map<String, dynamic>>> _cloudStore = {};

  /// Stores processed idempotency tokens: `"userId:idempotencyToken"` -> DateTime
  final Set<String> _processedTokens = {};

  /// Set of processed tokens (read/write for test setup).
  Set<String> get processedTokens => _processedTokens;

  /// Underlying cloud store for direct test inspection.
  Map<String, Map<String, Map<String, dynamic>>> get cloudStore => _cloudStore;

  /// History of applied mutations for verification.
  final List<Map<String, dynamic>> appliedMutations = [];

  /// Current active simulated user ID (simulating auth.uid() in PostgreSQL).
  String activeAuthUserId = 'authenticated_user_1';

  /// Testing controls
  bool simulateNetworkError = false;
  int transientFailuresRemaining = 0;
  int simulatedLatencyMs = 0;
  String? forcedErrorMessage;

  FakeSyncRemoteDataSource();

  /// Resets cloud storage for clean test setup.
  void clear() {
    _cloudStore.clear();
    _processedTokens.clear();
    appliedMutations.clear();
    simulateNetworkError = false;
    transientFailuresRemaining = 0;
    simulatedLatencyMs = 0;
    forcedErrorMessage = null;
  }

  /// Directly seeds a remote record into the simulated cloud store.
  void seedRemoteRecord({
    required String entityType,
    required String id,
    required String userId,
    required Map<String, dynamic> payload,
    required Map<String, String> fieldTimestamps,
    required DateTime updatedAtUtc,
    DateTime? deletedAtUtc,
  }) {
    final table = _resolveTableName(entityType);
    _cloudStore.putIfAbsent(table, () => {});

    final record = Map<String, dynamic>.from(payload);
    record['id'] = id;
    record['user_id'] = userId;
    record['updated_at_utc'] = updatedAtUtc.toUtc().toIso8601String();
    record['deleted_at_utc'] = deletedAtUtc?.toUtc().toIso8601String();
    record['field_timestamps_json'] = fieldTimestamps;
    record['sync_status'] = 'synced';

    _cloudStore[table]![id] = record;
  }

  /// Directly inspects a remote record.
  Map<String, dynamic>? getRemoteRecord({
    required String entityType,
    required String id,
  }) {
    final table = _resolveTableName(entityType);
    return _cloudStore[table]?[id];
  }

  @override
  Future<Map<String, dynamic>> applySyncMutation({
    required String operationId,
    required String entityType,
    required String entityId,
    required String operationType,
    required Map<String, dynamic> payload,
    required Map<String, String> fieldTimestamps,
    required DateTime updatedAtUtc,
    DateTime? deletedAtUtc,
  }) async {
    if (simulatedLatencyMs > 0) {
      await Future.delayed(Duration(milliseconds: simulatedLatencyMs));
    }
    _checkErrors();

    final userId = activeAuthUserId;
    final tokenKey = '$userId:$operationId';

    // 1. Check Operation-Level Idempotency in sync_audit_log
    if (_processedTokens.contains(tokenKey)) {
      final table = _resolveTableName(entityType);
      return {
        'status': 'already_processed',
        'operation_id': operationId,
        'entity_id': entityId,
        'merged_record': _cloudStore[table]?[entityId],
      };
    }

    final nowUtc = DateTime.now().toUtc();
    final table = _resolveTableName(entityType);
    _cloudStore.putIfAbsent(table, () => {});

    // 2. Clamp any future timestamps exceeding now + 5 min (Clock Skew Protection)
    final clampedIncomingTimestamps = ConflictResolver.sanitizeFieldTimestamps(
      fieldTimestamps,
      nowUtc: nowUtc,
    );

    final existingRecord = _cloudStore[table]![entityId];

    if (existingRecord == null) {
      // 3a. Fresh Insert
      final newRecord = Map<String, dynamic>.from(payload);
      newRecord['id'] = entityId;
      newRecord['user_id'] = userId;
      newRecord['updated_at_utc'] = updatedAtUtc.toUtc().toIso8601String();
      newRecord['deleted_at_utc'] = deletedAtUtc?.toUtc().toIso8601String();
      newRecord['field_timestamps_json'] = clampedIncomingTimestamps;
      newRecord['sync_status'] = 'synced';

      _cloudStore[table]![entityId] = newRecord;
    } else {
      // 3b. Field-Level LWW Reconciliation against existing cloud record
      final existingTimestamps = Map<String, String>.from(
        existingRecord['field_timestamps_json'] as Map? ?? {},
      );
      final existingUpdatedAt =
          DateTime.tryParse(
            existingRecord['updated_at_utc'] as String? ?? '',
          )?.toUtc() ??
          nowUtc;
      final existingDeletedAt = existingRecord['deleted_at_utc'] != null
          ? DateTime.tryParse(
              existingRecord['deleted_at_utc'] as String,
            )?.toUtc()
          : null;

      final conflictResult = ConflictResolver.reconcileEntityState(
        localPayload: existingRecord,
        remotePayload: payload,
        localFieldTimestamps: existingTimestamps,
        remoteFieldTimestamps: clampedIncomingTimestamps,
        localUpdatedAtUtc: existingUpdatedAt,
        remoteUpdatedAtUtc: updatedAtUtc,
        localDeletedAtUtc: existingDeletedAt,
        remoteDeletedAtUtc: deletedAtUtc,
      );

      final mergedRecord = Map<String, dynamic>.from(
        conflictResult.mergedPayload,
      );
      mergedRecord['id'] = entityId;
      mergedRecord['user_id'] = userId;
      mergedRecord['updated_at_utc'] =
          conflictResult.mergedPayload['updatedAtUtc'];
      mergedRecord['deleted_at_utc'] =
          conflictResult.mergedPayload['deletedAtUtc'];
      mergedRecord['field_timestamps_json'] =
          conflictResult.mergedFieldTimestamps;
      mergedRecord['sync_status'] = 'synced';

      _cloudStore[table]![entityId] = mergedRecord;
    }

    // 4. Record token in sync_audit_log
    _processedTokens.add(tokenKey);
    appliedMutations.add({
      'operation_id': operationId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation_type': operationType,
      'user_id': userId,
      'timestamp': nowUtc.toIso8601String(),
    });

    return {
      'status': 'applied',
      'operation_id': operationId,
      'entity_id': entityId,
      'merged_record': _cloudStore[table]?[entityId],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> pullEntities({
    required String userId,
    required String entityType,
    SyncCursor? cursor,
    int limit = 50,
  }) async {
    if (simulatedLatencyMs > 0) {
      await Future.delayed(Duration(milliseconds: simulatedLatencyMs));
    }
    _checkErrors();

    final table = _resolveTableName(entityType);
    final recordsMap = _cloudStore[table] ?? {};

    // Filter by user_id (RLS simulation)
    final userRecords = recordsMap.values
        .where((rec) => rec['user_id'] == userId)
        .toList();

    // Filter by cursor (strictly after cursor in updated_at_utc ASC, id ASC)
    final filtered = userRecords.where((rec) {
      if (cursor == null) return true;
      final recUpdatedStr = rec['updated_at_utc'] as String?;
      final recTime =
          DateTime.tryParse(recUpdatedStr ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final recId = rec['id'] as String? ?? '';

      return cursor.isAfterCursor(candidateTime: recTime, candidateId: recId);
    }).toList();

    // Sort deterministically ORDER BY updated_at_utc ASC, id ASC
    filtered.sort((a, b) {
      final aTime =
          DateTime.tryParse(a['updated_at_utc'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bTime =
          DateTime.tryParse(b['updated_at_utc'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      final compTime = aTime.compareTo(bTime);
      if (compTime != 0) return compTime;

      final aId = a['id'] as String? ?? '';
      final bId = b['id'] as String? ?? '';
      return aId.compareTo(bId);
    });

    return filtered
        .take(limit)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _checkErrors() {
    if (simulateNetworkError) {
      throw const NetworkException('Simulated network failure');
    }
    if (transientFailuresRemaining > 0) {
      transientFailuresRemaining--;
      throw const NetworkException('Simulated transient network timeout');
    }
    if (forcedErrorMessage != null) {
      throw SyncException(forcedErrorMessage!);
    }
  }

  String _resolveTableName(String entityType) {
    switch (entityType.toLowerCase()) {
      case 'category':
      case 'categories':
        return 'categories';
      case 'account':
      case 'accounts':
        return 'accounts';
      case 'transaction':
      case 'transactions':
        return 'transactions';
      case 'budget':
      case 'budgets':
        return 'budgets';
      case 'categorybudget':
      case 'category_budget':
      case 'categorybudgets':
      case 'category_budgets':
        return 'category_budgets';
      case 'goal':
      case 'savingsgoal':
      case 'savings_goal':
      case 'savingsgoals':
      case 'savings_goals':
        return 'savings_goals';
      case 'recurringrule':
      case 'recurring_rule':
      case 'recurringtransaction':
      case 'recurring_transaction':
      case 'recurring_transactions':
        return 'recurring_transactions';
      case 'usersetting':
      case 'user_settings':
      case 'settings':
        return 'user_settings';
      default:
        return entityType;
    }
  }
}
