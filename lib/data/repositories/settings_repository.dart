import '../../core/constants/app_constants.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../database/app_database.dart';

class SettingsRepository implements ISettingsRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  SettingsRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Future<String?> getSetting(String key) {
    return _db.settingsDao.getSetting(userId: _userId, key: key);
  }

  @override
  Future<void> setSetting(String key, String value) {
    return _db.settingsDao.setSetting(
      userId: _userId,
      key: key,
      value: value,
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<Map<String, String>> getAllSettings() {
    return _db.settingsDao.getAllSettings(_userId);
  }

  @override
  Future<void> clearAllSettings() {
    return _db.settingsDao.clearSettings(_userId);
  }
}
