import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/date_time_utils.dart';

void main() {
  group('DateTimeUtils Tests', () {
    test('toUtcIsoString and parseUtcIso work symmetrically', () {
      final now = DateTime.now();
      final iso = DateTimeUtils.toUtcIsoString(now);
      final parsedUtc = DateTimeUtils.parseUtcIso(iso);
      expect(parsedUtc.isUtc, isTrue);
      expect(
        parsedUtc.millisecondsSinceEpoch,
        equals(now.toUtc().millisecondsSinceEpoch),
      );
    });

    test('startOfMonthUtc and endOfMonthUtc boundaries are correct', () {
      final date = DateTime(2026, 9, 15, 12, 30);
      final start = DateTimeUtils.startOfMonthUtc(date);
      final end = DateTimeUtils.endOfMonthUtc(date);

      expect(start.isUtc, isTrue);
      expect(end.isUtc, isTrue);
      expect(end.isAfter(start), isTrue);
    });

    test('toMonthKey generates correct YYYY-MM key', () {
      final date = DateTime(2026, 9, 6);
      expect(DateTimeUtils.toMonthKey(date), equals('2026-09'));
    });
  });
}
