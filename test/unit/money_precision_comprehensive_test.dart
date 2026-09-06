import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/money_utils.dart';

void main() {
  group('Money Representation & Precision Verification', () {
    test(
      'Zero floating-point rounding errors during repeated arithmetic in minor units',
      () {
        // Problem with double: 0.1 + 0.2 = 0.30000000000000004
        // In minor units: 10 + 20 = 30 (exact!)
        final item1 = MoneyUtils.parseToMinorUnits('0.10'); // 10 paise
        final item2 = MoneyUtils.parseToMinorUnits('0.20'); // 20 paise
        final sum = item1 + item2;
        expect(sum, equals(30));
        expect(MoneyUtils.formatPlain(sum), equals('0.30'));
      },
    );

    test(
      'Accurately handles large financial quantities without precision loss',
      () {
        const largeInput = '10000000.50'; // 1 Crore 50 paise
        final minorUnits = MoneyUtils.parseToMinorUnits(largeInput);
        expect(minorUnits, equals(1000000050));
        expect(
          MoneyUtils.format(minorUnits, currencySymbol: '?'),
          equals('?10,000,000.50'),
        );
      },
    );

    test('Accurately formats zero and negative balances', () {
      expect(MoneyUtils.format(0, currencySymbol: '?'), equals('?0.00'));
      expect(
        MoneyUtils.format(-15000, currencySymbol: '?'),
        equals('-?150.00'),
      );
    });
  });
}
