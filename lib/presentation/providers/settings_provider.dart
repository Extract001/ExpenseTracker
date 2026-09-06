import 'package:flutter/material.dart';
import '../../core/constants/currency_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/repositories/i_settings_repository.dart';
import '../core/async_value.dart';

class SettingsProvider extends ChangeNotifier {
  final ISettingsRepository _repository;

  ThemeMode _themeMode = ThemeMode.system;
  String _currency = CurrencyConstants.defaultCurrencyCode;
  bool _isFirstLaunch = true;
  bool _isBiometricEnabled = false;
  bool _isPinSet = false;
  Map<String, String> _customSettings = {};

  AsyncValue<void> _state = const AsyncValue.initial();
  int _generation = 0;
  bool _isDisposed = false;

  // Keys
  static const String keyThemeMode = 'app_theme_mode';
  static const String keyCurrency = 'app_currency';
  static const String keyFirstLaunch = 'app_first_launch';
  static const String keyBiometricEnabled = 'app_biometric_enabled';
  static const String keyPinSet = 'app_pin_set';

  SettingsProvider({required ISettingsRepository repository})
    : _repository = repository;

  // Getters
  ThemeMode get themeMode => _themeMode;
  String get currency => _currency;
  bool get isFirstLaunch => _isFirstLaunch;
  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isPinSet => _isPinSet;
  Map<String, String> get customSettings => Map.unmodifiable(_customSettings);
  AsyncValue<void> get state => _state;
  bool get isLoading => _state.isLoading;

  /// Loads all settings from repository with generation guard.
  Future<void> loadSettings() async {
    _generation++;
    final currentGen = _generation;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final all = await _repository.getAllSettings();
      if (currentGen != _generation || _isDisposed) return;

      _customSettings = Map.from(all);

      // Parse ThemeMode
      final savedTheme = all[keyThemeMode];
      if (savedTheme == 'light') {
        _themeMode = ThemeMode.light;
      } else if (savedTheme == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.system;
      }

      // Parse Currency
      _currency = all[keyCurrency] ?? CurrencyConstants.defaultCurrencyCode;

      // Parse First Launch
      _isFirstLaunch = all[keyFirstLaunch] != 'false';

      // Parse Biometric & PIN flags (flags only, NO secrets stored here)
      _isBiometricEnabled = all[keyBiometricEnabled] == 'true';
      _isPinSet = all[keyPinSet] == 'true';

      _state = const AsyncValue.data(null);
    } catch (e, st) {
      if (currentGen != _generation || _isDisposed) return;
      AppLogger.error('SETTINGS_LOAD_ERROR', error: e, stackTrace: st);
      _state = AsyncValue.error('Failed to load settings.', e, st);
    } finally {
      if (currentGen == _generation && !_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Updates theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _safeNotifyListeners();

    String value = 'system';
    if (mode == ThemeMode.light) value = 'light';
    if (mode == ThemeMode.dark) value = 'dark';

    await _repository.setSetting(keyThemeMode, value);
  }

  /// Updates default currency.
  Future<void> setCurrency(String currencyCode) async {
    if (_currency == currencyCode) return;
    _currency = currencyCode;
    _safeNotifyListeners();

    await _repository.setSetting(keyCurrency, currencyCode);
  }

  /// Marks the first-launch onboarding / greeting as completed.
  Future<void> setFirstLaunchCompleted() async {
    _isFirstLaunch = false;
    _safeNotifyListeners();
    await _repository.setSetting(keyFirstLaunch, 'false');
  }

  /// Updates biometric authentication enabled flag.
  Future<void> setBiometricEnabled(bool enabled) async {
    _isBiometricEnabled = enabled;
    _safeNotifyListeners();
    await _repository.setSetting(keyBiometricEnabled, enabled.toString());
  }

  /// Updates PIN set flag (actual PIN hash is stored in SecureStorage).
  Future<void> setPinSet(bool isSet) async {
    _isPinSet = isSet;
    _safeNotifyListeners();
    await _repository.setSetting(keyPinSet, isSet.toString());
  }

  /// Exact and tokenized patterns for forbidden sensitive secrets.
  static const Set<String> _exactForbiddenKeys = {
    'pin',
    'pin_hash',
    'pin_salt',
    'db_key',
    'database_key',
    'encryption_key',
    'master_key',
    'private_key',
    'secret',
    'secret_key',
    'token',
    'auth_token',
    'access_token',
    'refresh_token',
    'password',
    'passcode',
    'salt',
  };

  static const List<String> _forbiddenSubstrings = [
    'pin_hash',
    'pin_salt',
    'encryption_key',
    'db_key',
    'auth_token',
    'refresh_token',
    'access_token',
    'private_key',
    'master_key',
  ];

  /// Checks if a key represents a sensitive secret that must not be stored in ordinary settings.
  static bool isSecretKey(String key) {
    final lower = key.trim().toLowerCase();
    if (_exactForbiddenKeys.contains(lower)) return true;
    for (final pattern in _forbiddenSubstrings) {
      if (lower.contains(pattern)) return true;
    }
    final segments = lower.split(RegExp(r'[_.\-]'));
    for (final seg in segments) {
      if (seg == 'pin' ||
          seg == 'password' ||
          seg == 'passcode' ||
          seg == 'secret' ||
          seg == 'token') {
        return true;
      }
    }
    return false;
  }

  /// Sets custom non-sensitive key-value setting. Enforces strict security boundary against secrets.
  Future<void> setCustomSetting(String key, String value) async {
    if (isSecretKey(key)) {
      throw const SecurityException(
        'Sensitive secrets (PIN, encryption keys, tokens) must be stored in SecureStorageService, not ordinary Settings.',
      );
    }
    _customSettings[key] = value;
    _safeNotifyListeners();
    await _repository.setSetting(key, value);
  }

  /// Resets settings provider to clean initial defaults.
  Future<void> reset({bool reload = false}) async {
    _generation++;
    _themeMode = ThemeMode.system;
    _currency = CurrencyConstants.defaultCurrencyCode;
    _isFirstLaunch = true;
    _isBiometricEnabled = false;
    _isPinSet = false;
    _customSettings.clear();
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadSettings();
    }
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
