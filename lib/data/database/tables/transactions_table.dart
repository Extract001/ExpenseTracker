import 'package:drift/drift.dart';
import 'accounts_table.dart';
import 'categories_table.dart';

@DataClassName('TransactionData')
@TableIndex(
  name: 'idx_tx_user_date',
  columns: {#userId, #deletedAtUtc, #transactionDateUtc, #id},
)
@TableIndex(
  name: 'idx_tx_user_account',
  columns: {#userId, #accountId, #deletedAtUtc, #transactionDateUtc},
)
@TableIndex(
  name: 'idx_tx_user_category',
  columns: {#userId, #categoryId, #deletedAtUtc, #transactionDateUtc},
)
@TableIndex(name: 'idx_tx_sync_status', columns: {#userId, #syncStatus})
class TransactionsTable extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  IntColumn get amountMinor => integer()(); // minor units (paise/cents)
  TextColumn get transactionType => text()(); // 'income', 'expense', 'transfer'
  TextColumn get categoryId => text().references(CategoriesTable, #id)();
  @ReferenceName('primaryAccount')
  TextColumn get accountId => text().references(AccountsTable, #id)();
  @ReferenceName('transferDestinationAccount')
  TextColumn get toAccountId =>
      text().nullable().references(AccountsTable, #id)(); // only for transfer
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get transactionDateUtc => dateTime()();
  TextColumn get transactionTime => text().nullable()();
  TextColumn get attachmentPath => text().nullable()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurringRuleId => text().nullable()();
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
