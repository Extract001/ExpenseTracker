import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:expense_tracker/core/backup/backup_models.dart';
import 'package:expense_tracker/core/database/encrypted_database_connection.dart';
import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/core/security/app_lock_service.dart';
import 'package:expense_tracker/core/security/hashing_service.dart';
import 'package:expense_tracker/core/security/secure_storage_service.dart';
import 'package:expense_tracker/core/utils/app_logger.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 8: Key Lifecycle, Cryptographic & Security Hardening Tests', () {
    late Map<String, String> mockSecureStore;
    late SecureStorageService secureStorageService;

    setUp(() {
      mockSecureStore = {};
      FlutterSecureStorage.setMockInitialValues(mockSecureStore);
      secureStorageService = SecureStorageService();
      AppLogger.enableConsoleLogging = false; // keep test output clean
    });

    // ------------------------------------------------------------------------
    // Group 1: Database Key Lifecycle & Fail-Safe Invariant
    // ------------------------------------------------------------------------
    group('1. Database Key Lifecycle & Fail-Safe Invariant', () {
      test(
        '1. First run generates 256-bit (64 hex characters) key when DB file does not exist',
        () async {
          final key = await secureStorageService.getOrInitializeDatabaseKey(
            databaseFileExists: false,
          );

          expect(key.length, equals(64));
          expect(SecureStorageService.isValidKeyFormat(key), isTrue);
          expect(await secureStorageService.hasDatabaseKey(), isTrue);
        },
      );

      test(
        '2. Restart retrieves existing key without generating a new key',
        () async {
          final initialKey = await secureStorageService
              .getOrInitializeDatabaseKey(databaseFileExists: false);

          final restartService = SecureStorageService();
          final retrievedKey = await restartService.getOrInitializeDatabaseKey(
            databaseFileExists: true,
          );

          expect(retrievedKey, equals(initialKey));
        },
      );

      test(
        '3. CRITICAL FAIL-SAFE: Database file exists but key missing throws DatabaseKeyMissingException',
        () async {
          // Database file exists on disk, but secure storage is empty (e.g. Keystore cleared)
          expect(
            () => secureStorageService.getOrInitializeDatabaseKey(
              databaseFileExists: true,
            ),
            throwsA(isA<DatabaseKeyMissingException>()),
          );

          // Verify that NO key was silently generated in secure storage!
          expect(await secureStorageService.hasDatabaseKey(), isFalse);
        },
      );

      test(
        '4. Corrupted database key (invalid length or non-hex) throws DatabaseKeyCorruptedException',
        () async {
          // Store an invalid key (e.g., truncated or corrupted)
          await secureStorageService.write(
            'db_encryption_key_v1',
            'corrupted_short_key_123',
          );

          expect(
            () => secureStorageService.getOrInitializeDatabaseKey(
              databaseFileExists: true,
            ),
            throwsA(isA<DatabaseKeyCorruptedException>()),
          );

          expect(
            () => secureStorageService.getDatabaseKey(),
            throwsA(isA<DatabaseKeyCorruptedException>()),
          );
        },
      );

      test(
        '5. EncryptedDatabaseConnection checks file.existsSync() and fails safely on missing key',
        () async {
          // Create a temporary file to simulate existing database on disk
          final tempDir = Directory.systemTemp.createTempSync('db_test_');
          final fakeDbFile = File('${tempDir.path}/test_db.sqlite')
            ..createSync();

          expect(fakeDbFile.existsSync(), isTrue);

          final lazyDb = EncryptedDatabaseConnection.createEncryptedConnection(
            secureStorage: secureStorageService,
            databaseFileOverride: fakeDbFile,
          );
          final db = AppDatabase(lazyDb);

          // Attempting to open the database must throw DatabaseKeyMissingException
          expect(
            () => db.customSelect('SELECT 1').get(),
            throwsA(isA<DatabaseKeyMissingException>()),
          );

          // Cleanup
          tempDir.deleteSync(recursive: true);
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 2: Cryptographic Standards & PIN Verification
    // ------------------------------------------------------------------------
    group('2. Cryptographic Standards & PBKDF2 Work Factor', () {
      test(
        '6. Verifies PBKDF2-HMAC-SHA256 mathematical derivation across rounds',
        () {
          final pass = utf8.encode('password');
          final salt = utf8.encode('salt');

          // Round 1 must equal direct HMAC(P, S || 1)
          final round1Expected = Hmac(
            sha256,
            pass,
          ).convert([...salt, 0, 0, 0, 1]).bytes;
          final round1Actual = HashingService.pbkdf2HmacSha256(
            password: pass,
            salt: salt,
            iterations: 1,
            keyLength: 32,
          );
          expect(round1Actual, equals(round1Expected));

          // Round 2 must equal U1 XOR HMAC(P, U1)
          final u2 = Hmac(sha256, pass).convert(round1Expected).bytes;
          final round2Expected = List<int>.generate(
            32,
            (i) => round1Expected[i] ^ u2[i],
          );
          final round2Actual = HashingService.pbkdf2HmacSha256(
            password: pass,
            salt: salt,
            iterations: 2,
            keyLength: 32,
          );
          expect(round2Actual, equals(round2Expected));

          // Deterministic multi-round consistency (4096 rounds)
          final round4096 = HashingService.pbkdf2HmacSha256(
            password: pass,
            salt: salt,
            iterations: 4096,
            keyLength: 32,
          );
          final hex4096 = round4096
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          expect(
            hex4096,
            equals(
              'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
            ),
          );
        },
      );

      test(
        '7. Generates 64-character hex hash with 10,000 iterations and random salt',
        () {
          final salt = HashingService.generateSalt(16);
          final hash = HashingService.hashPin('1234', salt, iterations: 10000);

          expect(hash.length, equals(64));
          expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
        },
      );

      test(
        '8. Constant-time comparison verifies equality without early-exit leakage',
        () {
          expect(
            HashingService.constantTimeCompare(
              'secret_pin_123',
              'secret_pin_123',
            ),
            isTrue,
          );
          expect(
            HashingService.constantTimeCompare(
              'secret_pin_123',
              'secret_pin_124',
            ),
            isFalse,
          );
          expect(
            HashingService.constantTimeCompare('short', 'much_longer_string'),
            isFalse,
          );
          expect(HashingService.constantTimeCompare('', ''), isTrue);
        },
      );

      test(
        '9. Backward compatibility: verifies PIN hashed with legacy multi-round SHA-256 algorithm',
        () {
          const pin = '5678';
          final salt = HashingService.generateSalt();
          final legacyHash = HashingService.legacyHashPin(pin, salt);

          // Verifying with verifyPin must recognize and accept the legacy hash
          final isMatch = HashingService.verifyPin(pin, legacyHash, salt);
          expect(isMatch, isTrue);

          // Incorrect PIN must still fail
          final isWrong = HashingService.verifyPin('9999', legacyHash, salt);
          expect(isWrong, isFalse);
        },
      );

      test('10. Rejects incorrect PINs deterministically', () {
        const pin = '4321';
        final salt = HashingService.generateSalt();
        final pbkdf2Hash = HashingService.hashPin(pin, salt);

        expect(HashingService.verifyPin(pin, pbkdf2Hash, salt), isTrue);
        expect(HashingService.verifyPin('0000', pbkdf2Hash, salt), isFalse);
        expect(HashingService.verifyPin('4322', pbkdf2Hash, salt), isFalse);
      });

      test(
        '11. Enforces separation between PIN work factor and backup KDF work factor with versioning',
        () {
          expect(HashingService.pinHashingIterations, equals(10000));
          expect(HashingService.backupKdfIterations, equals(100000));

          const kdfParams = BackupKdfParams(
            algorithm: 'PBKDF2-HMAC-SHA256',
            iterations: 100000,
            saltBytesLength: 16,
            keyBitsLength: 256,
            version: 1,
          );

          final json = kdfParams.toJson();
          expect(json['algorithm'], equals('PBKDF2-HMAC-SHA256'));
          expect(json['iterations'], equals(100000));
          expect(json['version'], equals(1));

          final deserialized = BackupKdfParams.fromJson(json);
          expect(deserialized.iterations, equals(100000));
          expect(deserialized.algorithm, equals('PBKDF2-HMAC-SHA256'));
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 3: App Lock & Rate Limiting
    // ------------------------------------------------------------------------
    group('3. App Lock & Rate Limiting', () {
      test('12. Enforces configurable lock timeouts on resume', () async {
        final lockService = AppLockService(secureStorage: secureStorageService);
        await secureStorageService.setAppPin('1234');
        await lockService.initialize();

        // 1. Immediately timeout
        await lockService.setLockTimeout(AppLockTimeout.immediate);
        await lockService.unlockWithPin('1234');
        expect(lockService.isLocked, isFalse);

        lockService.onAppPaused();
        lockService.onAppResumed();
        expect(lockService.isLocked, isTrue);

        // 2. 5-minute timeout
        await lockService.setLockTimeout(AppLockTimeout.fiveMinutes);
        await lockService.unlockWithPin('1234');
        expect(lockService.isLocked, isFalse);

        // Resuming after 1 second must NOT lock
        lockService.onAppPaused();
        lockService.onAppResumed();
        expect(lockService.isLocked, isFalse);

        // 3. Never timeout
        await lockService.setLockTimeout(AppLockTimeout.never);
        lockService.onAppPaused();
        lockService.onAppResumed();
        expect(lockService.isLocked, isFalse);
      });

      test(
        '13. Enforces brute-force rate limiting after 5 consecutive failed attempts',
        () async {
          final lockService = AppLockService(
            secureStorage: secureStorageService,
          );
          await secureStorageService.setAppPin('9876');
          await lockService.initialize();

          for (int i = 0; i < 4; i++) {
            final result = await lockService.unlockWithPin('0000');
            expect(result, isFalse);
            expect(lockService.isRateLimited, isFalse);
          }

          // 5th failed attempt triggers rate limit lockout
          final fifth = await lockService.unlockWithPin('0000');
          expect(fifth, isFalse);
          expect(lockService.isRateLimited, isTrue);

          // 6th attempt throws SecurityException(code: RATE_LIMITED)
          expect(
            () => lockService.unlockWithPin('9876'),
            throwsA(
              predicate(
                (e) => e is SecurityException && e.code == 'RATE_LIMITED',
              ),
            ),
          );
        },
      );

      test(
        '14. wipeSession securely resets all in-memory timestamps and state on logout',
        () async {
          final lockService = AppLockService(
            secureStorage: secureStorageService,
          );
          await secureStorageService.setAppPin('1111');
          await lockService.initialize();

          expect(lockService.isAppLockConfigured, isTrue);
          expect(lockService.lastActiveTimestamp, isNotNull);

          lockService.wipeSession();

          expect(lockService.isAppLockConfigured, isFalse);
          expect(lockService.lastActiveTimestamp, isNull);
          expect(lockService.isLocked, isFalse);
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 4: Centralized Leak-Safe Logging & Secret Filtering
    // ------------------------------------------------------------------------
    group('4. Centralized Leak-Safe Logging & Secret Filtering', () {
      test(
        '15. AppLogger.sanitize redacts all financial amounts, notes, descriptions, PINs, and keys',
        () {
          final dirtyMeta = {
            'operation': 'SYNC_PUSH',
            'amountMinor': 50000,
            'note': 'Secret business lunch with client',
            'accountName': 'Personal Checking 1234',
            'userPin': '4321',
            'dbKey': 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
            'durationMs': 120,
            'recordCount': 10,
          };

          final cleanMeta = AppLogger.sanitize(dirtyMeta);

          expect(cleanMeta['operation'], equals('SYNC_PUSH'));
          expect(cleanMeta['durationMs'], equals(120));
          expect(cleanMeta['recordCount'], equals(10));

          // Redacted fields
          expect(cleanMeta['amountMinor'], equals('[REDACTED]'));
          expect(cleanMeta['note'], equals('[REDACTED]'));
          expect(cleanMeta['accountName'], equals('[REDACTED]'));
          expect(cleanMeta['userPin'], equals('[REDACTED]'));
          expect(cleanMeta['dbKey'], equals('[REDACTED]'));
        },
      );

      test('16. AppLogger.sanitizeError strips emails and hex secret keys', () {
        const rawError =
            'Error connecting to user@company.com with token 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        final sanitized = AppLogger.sanitizeError(rawError);

        expect(sanitized.contains('user@company.com'), isFalse);
        expect(sanitized.contains('[EMAIL_REDACTED]'), isTrue);
        expect(sanitized.contains('0123456789abcdef'), isFalse);
        expect(sanitized.contains('[KEY_REDACTED]'), isTrue);
      });

      test(
        '17. SettingsProvider.isSecretKey rejects forbidden secret keys',
        () {
          expect(SettingsProvider.isSecretKey('pin_hash'), isTrue);
          expect(SettingsProvider.isSecretKey('user_pin_salt'), isTrue);
          expect(SettingsProvider.isSecretKey('db_encryption_key'), isTrue);
          expect(SettingsProvider.isSecretKey('access_token'), isTrue);
          expect(SettingsProvider.isSecretKey('supabase_auth_token'), isTrue);
          expect(SettingsProvider.isSecretKey('my_secret_passcode'), isTrue);

          // Safe application settings must not be rejected
          expect(SettingsProvider.isSecretKey('app_theme_mode'), isFalse);
          expect(SettingsProvider.isSecretKey('app_currency'), isFalse);
          expect(
            SettingsProvider.isSecretKey('show_monthly_overview'),
            isFalse,
          );
        },
      );
    });
  });
}
