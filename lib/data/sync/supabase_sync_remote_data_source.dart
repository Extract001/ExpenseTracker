import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../core/errors/app_exception.dart';
import '../../core/sync/i_sync_remote_data_source.dart';
import '../../core/sync/sync_cursor.dart';

/// Production implementation of [ISyncRemoteDataSource] backed by Supabase.
class SupabaseSyncRemoteDataSource implements ISyncRemoteDataSource {
  final supa.SupabaseClient _supabase;

  SupabaseSyncRemoteDataSource({required supa.SupabaseClient supabase})
    : _supabase = supabase;

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
    try {
      final response = await _supabase.rpc(
        'apply_sync_mutation',
        params: {
          'p_operation_id': operationId,
          'p_entity_type': entityType,
          'p_entity_id': entityId,
          'p_operation_type': operationType,
          'p_payload': payload,
          'p_field_timestamps': fieldTimestamps,
          'p_updated_at_utc': updatedAtUtc.toUtc().toIso8601String(),
          'p_deleted_at_utc': deletedAtUtc?.toUtc().toIso8601String(),
        },
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'status': 'applied', 'operation_id': operationId};
    } on supa.PostgrestException catch (e) {
      throw SyncException(
        'Supabase RPC apply_sync_mutation failed: ${e.message}',
        details: e,
      );
    } catch (e) {
      throw SyncException('Failed to apply sync mutation: $e', details: e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullEntities({
    required String userId,
    required String entityType,
    SyncCursor? cursor,
    int limit = 50,
  }) async {
    try {
      final tableName = _resolveTableName(entityType);
      final remoteUserId = _supabase.auth.currentUser?.id ?? userId;
      var query = _supabase.from(tableName).select().eq('user_id', remoteUserId);

      if (cursor != null) {
        final cursorIso = cursor.timestampUtc.toUtc().toIso8601String();
        final cursorId = cursor.entityId;

        if (cursorId.isNotEmpty) {
          query = query.or(
            'updated_at_utc.gt.$cursorIso,and(updated_at_utc.eq.$cursorIso,id.gt.$cursorId)',
          );
        } else {
          query = query.gt('updated_at_utc', cursorIso);
        }
      }

      final response = await query
          .order('updated_at_utc', ascending: true)
          .order('id', ascending: true)
          .limit(limit);

      return (response as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } on supa.PostgrestException catch (e) {
      throw SyncException(
        'Supabase pullEntities failed for $entityType: ${e.message}',
        details: e,
      );
    } catch (e) {
      throw SyncException(
        'Failed to pull entities for $entityType: $e',
        details: e,
      );
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
