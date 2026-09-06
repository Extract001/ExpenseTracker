import 'package:drift/drift.dart';

@DataClassName('UserData')
class UsersTable extends Table {
  @override
  String get tableName => 'users';

  TextColumn get id => text()(); // UUID or local_guest_user
  TextColumn get email => text().nullable()();
  TextColumn get displayName => text().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get lastActiveAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
