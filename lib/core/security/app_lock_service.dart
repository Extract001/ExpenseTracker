import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../errors/app_exception.dart';
import 'secure_storage_service.dart';

enum AppLockTimeout {
  immediate(0, 'Immediately'),
  oneMinute(60, '1 minute'),
  fiveMinutes(300, '5 minutes'),
  fifteenMinutes(900, '15 minutes'),
  never(-1, 'Never');

  final int seconds;
  final String label;
  const AppLockTimeout(this.seconds, this.label);

  static AppLockTimeout fromSeconds(int? seconds) {
    if (seconds == null) return AppLockTimeout.immediate;
    for (final t in AppLockTimeout.values) {
      if (t.seconds == seconds) return t;
    }
    return AppLockTimeout.immediate;
  }
}

class AppLockService extends ChangeNotifier {
  final SecureStorageService _secureStorage;
  final LocalAuthentication _localAuth;

  bool _isLocked = false;
  bool _isAppLockConfigured = false;
  AppLockTimeout _lockTimeout = AppLockTimeout.immediate;
  DateTime? _lastActiveTimestamp;
  int _failedAttempts = 0;
  DateTime? _lockoutUntilUtc;

  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);
  static const String keyLockTimeoutSeconds = 'app_lock_timeout_seconds';

  AppLockService({
    SecureStorageService? secureStorage,
    LocalAuthentication? localAuth,
  }) : _secureStorage = secureStorage ?? SecureStorageService(),
       _localAuth = localAuth ?? LocalAuthentication();

  bool get isLocked => _isLocked;
  bool get isAppLockConfigured => _isAppLockConfigured;
  AppLockTimeout get lockTimeout => _lockTimeout;
  DateTime? get lastActiveTimestamp => _lastActiveTimestamp;
  int get failedAttempts => _failedAttempts;
  bool get isRateLimited =>
      _lockoutUntilUtc != null &&
      DateTime.now().toUtc().isBefore(_lockoutUntilUtc!);

  /// Initializes app lock state from secure storage.
  Future<void> initialize() async {
    _isAppLockConfigured = await _secureStorage.hasAppPin();
    final savedTimeout = await _secureStorage.read(keyLockTimeoutSeconds);
    if (savedTimeout != null) {
      _lockTimeout = AppLockTimeout.fromSeconds(int.tryParse(savedTimeout));
    }
    _isLocked = _isAppLockConfigured;
    _lastActiveTimestamp = DateTime.now().toUtc();
    notifyListeners();
  }

  /// Configures timeout preference.
  Future<void> setLockTimeout(AppLockTimeout timeout) async {
    _lockTimeout = timeout;
    await _secureStorage.write(
      keyLockTimeoutSeconds,
      timeout.seconds.toString(),
    );
    notifyListeners();
  }

  /// Lifecycle callback when app moves to background.
  void onAppPaused() {
    _lastActiveTimestamp = DateTime.now().toUtc();
  }

  /// Lifecycle callback when app moves to foreground.
  void onAppResumed() {
    if (!_isAppLockConfigured) return;
    if (_lockTimeout == AppLockTimeout.never) return;

    if (_lastActiveTimestamp != null) {
      final elapsed = DateTime.now().toUtc().difference(_lastActiveTimestamp!);
      if (elapsed.inSeconds >= _lockTimeout.seconds) {
        _isLocked = true;
        notifyListeners();
      }
    } else {
      _isLocked = true;
      notifyListeners();
    }
  }

  /// Explicitly locks the application.
  void lock() {
    if (_isAppLockConfigured) {
      _isLocked = true;
      notifyListeners();
    }
  }

  /// Attempts to unlock using the entered PIN.
  Future<bool> unlockWithPin(String enteredPin) async {
    if (isRateLimited) {
      throw SecurityException(
        'Too many failed attempts. Please try again after ${_lockoutUntilUtc!.difference(DateTime.now().toUtc()).inSeconds} seconds.',
        code: 'RATE_LIMITED',
      );
    }

    final isValid = await _secureStorage.verifyAppPin(enteredPin);
    if (isValid) {
      _failedAttempts = 0;
      _lockoutUntilUtc = null;
      _isLocked = false;
      _lastActiveTimestamp = DateTime.now().toUtc();
      notifyListeners();
      return true;
    } else {
      _failedAttempts++;
      if (_failedAttempts >= maxFailedAttempts) {
        _lockoutUntilUtc = DateTime.now().toUtc().add(lockoutDuration);
      }
      notifyListeners();
      return false;
    }
  }

  /// Attempts to unlock using biometric authentication.
  Future<bool> unlockWithBiometrics() async {
    if (isRateLimited) return false;

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to access Expense Tracker',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuth) {
        _failedAttempts = 0;
        _lockoutUntilUtc = null;
        _isLocked = false;
        _lastActiveTimestamp = DateTime.now().toUtc();
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Wipes all sensitive session state from memory (on logout or account switch).
  void wipeSession() {
    _isLocked = false;
    _isAppLockConfigured = false;
    _lastActiveTimestamp = null;
    _failedAttempts = 0;
    _lockoutUntilUtc = null;
    notifyListeners();
  }
}
