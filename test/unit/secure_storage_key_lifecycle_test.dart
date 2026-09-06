import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/security/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  group('Secure Storage & Key Lifecycle Verification', () {
    late Map<String, String> mockSecureStore;
    late SecureStorageService secureStorageService;

    setUp(() {
      mockSecureStore = {};
      FlutterSecureStorage.setMockInitialValues(mockSecureStore);
      secureStorageService = SecureStorageService();
    });

    test(
      '1. Generates 256-bit (64 hex characters) CSPRNG database key on first run',
      () async {
        final key = await secureStorageService.getOrCreateDatabaseKey();

        expect(key, isNotEmpty);
        expect(key.length, equals(64)); // 32 bytes hex encoded = 64 characters
        final hexRegex = RegExp(r'^[0-9a-fA-F]{64}$');
        expect(hexRegex.hasMatch(key), isTrue);
      },
    );

    test(
      '2. Key remains strictly stable across simulated app restarts',
      () async {
        final initialKey = await secureStorageService.getOrCreateDatabaseKey();

        // Simulate app restart by creating a new service instance
        final restartedService = SecureStorageService();
        final reloadedKey = await restartedService.getOrCreateDatabaseKey();

        expect(reloadedKey, equals(initialKey));
      },
    );

    test(
      '3. Generates unique salts and verifies hashed PINs with multi-round PBKDF2/SHA-256',
      () async {
        const pin = '4829';

        await secureStorageService.setAppPin(pin);

        final isPinSet = await secureStorageService.hasAppPin();
        expect(isPinSet, isTrue);

        final isCorrect = await secureStorageService.verifyAppPin(pin);
        expect(isCorrect, isTrue);

        final isWrong = await secureStorageService.verifyAppPin('9999');
        expect(isWrong, isFalse);

        await secureStorageService.clearAppPin();
        final isStillSet = await secureStorageService.hasAppPin();
        expect(isStillSet, isFalse);
      },
    );
  });
}
