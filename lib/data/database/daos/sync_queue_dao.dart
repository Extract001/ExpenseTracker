import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sync_operations_table.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncOperationsTable])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<int> enqueueOperation(SyncOperationsTableCompanion entry) {
    return into(syncOperationsTable).insert(entry);
  }

  Future<List<SyncOperationData>> getPendingOperations({
    required String userId,
    int limit = 50,
    int maxRetries = 10,
  }) {
    return (select(syncOperationsTable)
          ..where(
            (op) =>
                op.userId.equals(userId) &
                op.retryCount.isSmallerThanValue(maxRetries),
          )
          ..orderBy([(op) => OrderingTerm.asc(op.createdAtUtc)])
          ..limit(limit))
        .get();
  }

  Future<int> deleteOperation(String id) {
    return (delete(syncOperationsTable)..where((op) => op.id.equals(id))).go();
  }

  Future<int> recordOperationFailure({
    required String id,
    required String errorMessage,
    required DateTime attemptTimeUtc,
  }) async {
    final current = await (select(
      syncOperationsTable,
    )..where((op) => op.id.equals(id))).getSingleOrNull();
    final newRetryCount = (current?.retryCount ?? 0) + 1;
    return (update(syncOperationsTable)..where((op) => op.id.equals(id))).write(
      SyncOperationsTableCompanion(
        retryCount: Value(newRetryCount),
        lastAttemptAtUtc: Value(attemptTimeUtc),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  Future<int> getPendingCount(String userId) async {
    final countCol = syncOperationsTable.id.count();
    final query = selectOnly(syncOperationsTable)
      ..addColumns([countCol])
      ..where(syncOperationsTable.userId.equals(userId));
    final result = await query.map((r) => r.read(countCol)).getSingleOrNull();
    return result ?? 0;
  }

  Stream<int> watchPendingCount(String userId) {
    final countCol = syncOperationsTable.id.count();
    final query = selectOnly(syncOperationsTable)
      ..addColumns([countCol])
      ..where(syncOperationsTable.userId.equals(userId));
    return query.map((r) => r.read(countCol) ?? 0).watchSingle();
  }

  Stream<List<SyncOperationData>> watchPendingOperations({
    required String userId,
    int limit = 50,
  }) {
    return (select(syncOperationsTable)
          ..where((op) => op.userId.equals(userId))
          ..orderBy([(op) => OrderingTerm.asc(op.createdAtUtc)])
          ..limit(limit))
        .watch();
  }
}
