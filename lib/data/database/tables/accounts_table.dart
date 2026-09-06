import 'package:drift/drift.dart';

@DataClassName('AccountData')
@TableIndex(name: 'idx_accounts_user', columns: {#userId, #deletedAtUtc})
class AccountsTable extends Table {
  @override
  String get tableName => 'accounts';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get accountType =>
      text()(); // 'cash', 'bank', 'creditCard', 'wallet', 'savings'
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  IntColumn get initialBalanceMinor =>
      integer().withDefault(const Constant(0))(); // minor units
  IntColumn get colorValue =>
      integer().withDefault(const Constant(0xFF14B8A6))();
  IntColumn get iconCodePoint =>
      integer().withDefault(const Constant(0xe040))();
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
