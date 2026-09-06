import 'package:drift/drift.dart';

@DataClassName('SettingData')
class SettingsTable extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get userId => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {key, userId};
}
