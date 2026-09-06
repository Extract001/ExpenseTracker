class AppConstants {
  static const String appName = 'Expense Tracker';
  static const String appVersion = '1.0.0';
  static const String defaultUserId = 'local_guest_user';
  static const String databaseFileName = 'expense_tracker.enc.sqlite';
  static const int databaseSchemaVersion = 1;
  static const int defaultPageSize = 50;
  static const int maxBatchSyncSize = 100;

  // Storage Keys
  static const String keyDbEncryptionKey = 'db_encryption_key_v1';
  static const String keyUserPinHash = 'user_pin_hash';
  static const String keyUserPinSalt = 'user_pin_salt';
  static const String keyIsBiometricsEnabled = 'is_biometrics_enabled';
  static const String keyIsAppLockEnabled = 'is_app_lock_enabled';
  static const String keyLastSyncTimestamp = 'last_sync_timestamp';
  static const String keySelectedCurrency = 'selected_currency';
  static const String keyThemeMode = 'theme_mode';

  // Performance
  static const int maxCachedRecords = 10000;
}
