import 'package:drift/drift.dart';
import 'accounts_table.dart';
import 'categories_table.dart';

@DataClassName('RecurringTransactionData')
@TableIndex(
  name: 'idx_recurring_user_next',
  columns: {#userId, #isActive, #nextOccurrenceUtc, #deletedAtUtc},
)
class RecurringTransactionsTable extends Table {
  @override
  String get tableName => 'recurring_transactions';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  IntColumn get amountMinor => integer()(); // minor units
  TextColumn get transactionType => text()(); // 'income', 'expense'
  TextColumn get categoryId => text().references(CategoriesTable, #id)();
  TextColumn get accountId => text().references(AccountsTable, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get frequency =>
      text()(); // 'daily', 'weekly', 'monthly', 'yearly'
  DateTimeColumn get startDateUtc => dateTime()();
  DateTimeColumn get nextOccurrenceUtc => dateTime()();
  DateTimeColumn get lastExecutedDateUtc => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
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
