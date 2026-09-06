import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import 'hashing_service.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  /// Validates whether a key string is a valid 256-bit hex string (64 hex characters).
  static bool isValidKeyFormat(String? key) {
    if (key == null || key.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key);
  }

  /// Retrieves the 256-bit database encryption key, or generates a new one on first install.
  ///
  /// CRITICAL FAIL-SAFE: If [databaseFileExists] is true but no valid key is present in secure
  /// storage, this method throws [DatabaseKeyMissingException] instead of generating a new key.
  /// Silently generating a new key for an existing database would result in permanent data loss.
  /// If an existing key does not pass 256-bit format validation, throws [DatabaseKeyCorruptedException].
  Future<String> getOrInitializeDatabaseKey({
    required bool databaseFileExists,
  }) async {
    final key = await _storage.read(key: AppConstants.keyDbEncryptionKey);
    if (key != null && key.isNotEmpty) {
      if (!isValidKeyFormat(key)) {
        throw const DatabaseKeyCorruptedException();
      }
      return key;
    }

    // Key is missing from secure storage
    if (databaseFileExists) {
      throw const DatabaseKeyMissingException();
    }

    // First install: database file does not exist on disk yet. Safe to generate a new key.
    final newKey = _generateSecurePassphrase(32);
    await _storage.write(key: AppConstants.keyDbEncryptionKey, value: newKey);
    return newKey;
  }

  /// Backward-compatible method for existing callers.
  ///
  /// Set [databaseFileExists] to true if an existing encrypted database file is present on disk.
  Future<String> getOrCreateDatabaseKey({bool databaseFileExists = false}) {
    return getOrInitializeDatabaseKey(databaseFileExists: databaseFileExists);
  }

  /// Retrieves the existing database key without generating a new one.
  Future<String?> getDatabaseKey() async {
    final key = await _storage.read(key: AppConstants.keyDbEncryptionKey);
    if (key != null && !isValidKeyFormat(key)) {
      throw const DatabaseKeyCorruptedException();
    }
    return key;
  }

  /// Returns true if a valid 256-bit database encryption key is stored.
  Future<bool> hasDatabaseKey() async {
    final key = await _storage.read(key: AppConstants.keyDbEncryptionKey);
    return isValidKeyFormat(key);
  }

  /// Generates a 256-bit (or specified length) hex passphrase using CSPRNG.
  static String _generateSecurePassphrase(int byteLength) {
    final random = Random.secure();
    final bytes = Uint8List(byteLength);
    for (int i = 0; i < byteLength; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Sets up a new PIN for App Lock.
  Future<void> setAppPin(String pin) async {
    final salt = HashingService.generateSalt();
    final hash = HashingService.hashPin(pin, salt);
    await _storage.write(key: AppConstants.keyUserPinSalt, value: salt);
    await _storage.write(key: AppConstants.keyUserPinHash, value: hash);
    await _storage.write(key: AppConstants.keyIsAppLockEnabled, value: 'true');
  }

  /// Verifies entered PIN against stored hash.
  Future<bool> verifyAppPin(String enteredPin) async {
    final salt = await _storage.read(key: AppConstants.keyUserPinSalt);
    final hash = await _storage.read(key: AppConstants.keyUserPinHash);
    if (salt == null || hash == null) return false;
    return HashingService.verifyPin(enteredPin, hash, salt);
  }

  /// Checks if PIN is configured.
  Future<bool> hasAppPin() async {
    final hash = await _storage.read(key: AppConstants.keyUserPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Disables App Lock PIN.
  Future<void> clearAppPin() async {
    await _storage.delete(key: AppConstants.keyUserPinHash);
    await _storage.delete(key: AppConstants.keyUserPinSalt);
    await _storage.write(key: AppConstants.keyIsAppLockEnabled, value: 'false');
  }

  /// Biometrics preference
  Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(
      key: AppConstants.keyIsBiometricsEnabled,
      value: enabled.toString(),
    );
  }

  Future<bool> isBiometricsEnabled() async {
    final val = await _storage.read(key: AppConstants.keyIsBiometricsEnabled);
    return val == 'true';
  }

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> delete(String key) => _storage.delete(key: key);
  Future<void> deleteAll() => _storage.deleteAll();
}
