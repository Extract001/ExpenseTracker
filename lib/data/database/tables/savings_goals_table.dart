import 'package:drift/drift.dart';

@DataClassName('SavingsGoalData')
@TableIndex(name: 'idx_goals_user', columns: {#userId, #deletedAtUtc})
class SavingsGoalsTable extends Table {
  @override
  String get tableName => 'savings_goals';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get targetAmountMinor => integer()(); // minor units
  IntColumn get currentAmountMinor =>
      integer().withDefault(const Constant(0))(); // minor units
  DateTimeColumn get targetDateUtc => dateTime()();
  IntColumn get iconCodePoint =>
      integer().withDefault(const Constant(0xe66c))();
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF10B981))();
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
