import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sync_metadata_table.dart';

part 'sync_metadata_dao.g.dart';

@DriftAccessor(tables: [SyncMetadataTable])
class SyncMetadataDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetadataDaoMixin {
  SyncMetadataDao(super.db);

  /// Retrieves global metadata for a user.
  Future<SyncMetadataData?> getMetadata(String userId) {
    return (select(syncMetadataTable)
          ..where((m) => m.userId.equals(userId) & m.id.equals('meta_$userId')))
        .getSingleOrNull();
  }

  /// Sets global sync timestamp for a user.
  Future<int> setLastSyncTimestamp({
    required String userId,
    required DateTime lastSyncUtc,
    String? cursor,
  }) {
    final id = 'meta_$userId';
    return into(syncMetadataTable).insertOnConflictUpdate(
      SyncMetadataTableCompanion(
        id: Value(id),
        userId: Value(userId),
        lastSyncTimestampUtc: Value(lastSyncUtc),
        syncCursor: Value(cursor),
        updatedAtUtc: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Retrieves entity-type scoped cursor metadata for a user.
  Future<SyncMetadataData?> getEntityMetadata({
    required String userId,
    required String entityType,
  }) {
    final id = 'meta_${userId}_$entityType';
    return (select(
      syncMetadataTable,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
  }

  /// Sets entity-type scoped cursor for a user.
  Future<int> setEntityCursor({
    required String userId,
    required String entityType,
    required DateTime lastSyncUtc,
    required String cursor,
  }) {
    final id = 'meta_${userId}_$entityType';
    return into(syncMetadataTable).insertOnConflictUpdate(
      SyncMetadataTableCompanion(
        id: Value(id),
        userId: Value(userId),
        lastSyncTimestampUtc: Value(lastSyncUtc),
        syncCursor: Value(cursor),
        updatedAtUtc: Value(DateTime.now().toUtc()),
      ),
    );
  }
}
