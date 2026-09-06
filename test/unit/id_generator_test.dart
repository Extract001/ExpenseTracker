import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/id_generator.dart';

void main() {
  group('IdGenerator Tests', () {
    test('Generates valid UUID v4', () {
      final id1 = IdGenerator.generateUuid();
      final id2 = IdGenerator.generateUuid();
      expect(id1, isNotEmpty);
      expect(id2, isNotEmpty);
      expect(id1, isNot(equals(id2)));
      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      );
      expect(uuidRegex.hasMatch(id1), isTrue);
      expect(uuidRegex.hasMatch(id2), isTrue);
    });
  });
}
