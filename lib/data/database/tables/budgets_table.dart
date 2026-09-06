import 'package:drift/drift.dart';

@DataClassName('BudgetData')
@TableIndex(
  name: 'idx_budgets_user_month',
  columns: {#userId, #monthYear, #deletedAtUtc},
)
class BudgetsTable extends Table {
  @override
  String get tableName => 'budgets';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  TextColumn get monthYear => text()(); // e.g. "2026-09"
  IntColumn get amountMinor => integer()(); // monthly budget in minor units
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
