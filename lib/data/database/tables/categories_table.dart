import 'package:drift/drift.dart';

@DataClassName('CategoryData')
@TableIndex(
  name: 'idx_categories_user',
  columns: {#userId, #isArchived, #deletedAtUtc},
)
class CategoriesTable extends Table {
  @override
  String get tableName => 'categories';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get type => text()(); // 'income' or 'expense'
  IntColumn get iconCodePoint => integer()();
  IntColumn get colorValue => integer()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();
  DateTimeColumn get deletedAtUtc => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pendingCreate'))();
  TextColumn get fieldTimestampsJson =>
      text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
