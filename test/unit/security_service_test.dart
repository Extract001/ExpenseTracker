import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/security/hashing_service.dart';

void main() {
  group('HashingService Tests', () {
    test('Generates random salt of requested length', () {
      final salt1 = HashingService.generateSalt(16);
      final salt2 = HashingService.generateSalt(16);
      expect(salt1, isNotEmpty);
      expect(salt2, isNotEmpty);
      expect(salt1, isNot(equals(salt2)));
    });

    test('Hashes PIN and verifies correctly', () {
      const pin = '1234';
      final salt = HashingService.generateSalt();
      final hash = HashingService.hashPin(pin, salt);

      expect(HashingService.verifyPin(pin, hash, salt), isTrue);
      expect(HashingService.verifyPin('0000', hash, salt), isFalse);
    });
  });
}
