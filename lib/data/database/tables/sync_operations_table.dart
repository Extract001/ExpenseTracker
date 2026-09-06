import 'package:drift/drift.dart';

@DataClassName('SyncOperationData')
@TableIndex(
  name: 'idx_sync_ops_user_created',
  columns: {#userId, #createdAtUtc},
)
class SyncOperationsTable extends Table {
  @override
  String get tableName => 'sync_operations';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  TextColumn get entityType =>
      text()(); // 'transaction', 'category', 'account', 'budget', etc.
  TextColumn get entityId => text()();
  TextColumn get operationType => text()(); // 'create', 'update', 'delete'
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAtUtc => dateTime().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
