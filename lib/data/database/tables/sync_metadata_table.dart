import 'package:drift/drift.dart';

@DataClassName('SyncMetadataData')
class SyncMetadataTable extends Table {
  @override
  String get tableName => 'sync_metadata';

  TextColumn get id => text()(); // e.g., 'meta_local_guest_user'
  TextColumn get userId => text()();
  DateTimeColumn get lastSyncTimestampUtc => dateTime().nullable()();
  TextColumn get syncCursor => text().nullable()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
