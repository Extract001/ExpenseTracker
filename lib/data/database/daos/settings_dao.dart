import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/settings_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [SettingsTable])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<String?> getSetting({
    required String userId,
    required String key,
  }) async {
    final query = select(settingsTable)
      ..where((s) => s.userId.equals(userId) & s.key.equals(key));
    final record = await query.getSingleOrNull();
    return record?.value;
  }

  Future<int> setSetting({
    required String userId,
    required String key,
    required String value,
    required DateTime updatedAtUtc,
  }) {
    return into(settingsTable).insertOnConflictUpdate(
      SettingsTableCompanion(
        key: Value(key),
        userId: Value(userId),
        value: Value(value),
        updatedAtUtc: Value(updatedAtUtc),
      ),
    );
  }

  Future<Map<String, String>> getAllSettings(String userId) async {
    final rows = await (select(
      settingsTable,
    )..where((s) => s.userId.equals(userId))).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<int> clearSettings(String userId) {
    return (delete(settingsTable)..where((s) => s.userId.equals(userId))).go();
  }
}
