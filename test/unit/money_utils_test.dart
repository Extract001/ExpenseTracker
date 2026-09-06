import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/money_utils.dart';

void main() {
  group('MoneyUtils Tests', () {
    test('Converts decimal string to integer minor units correctly', () {
      expect(MoneyUtils.parseToMinorUnits('125.50'), equals(12550));
      expect(MoneyUtils.parseToMinorUnits('500'), equals(50000));
      expect(MoneyUtils.parseToMinorUnits('0.99'), equals(99));
      expect(MoneyUtils.parseToMinorUnits('1,234.56'), equals(123456));
      expect(
        MoneyUtils.parseToMinorUnits('100', decimalDigits: 0),
        equals(100),
      );
      expect(MoneyUtils.parseToMinorUnits('-50.25'), equals(-5025));
    });

    test('Converts integer minor units to major units double correctly', () {
      expect(MoneyUtils.toMajorUnits(12550), equals(125.50));
      expect(MoneyUtils.toMajorUnits(50000), equals(500.00));
      expect(MoneyUtils.toMajorUnits(99), equals(0.99));
      expect(MoneyUtils.toMajorUnits(100, decimalDigits: 0), equals(100.0));
    });

    test('Formats integer minor units to currency string correctly', () {
      expect(
        MoneyUtils.format(12550, currencySymbol: r'$'),
        equals(r'$125.50'),
      );
      expect(MoneyUtils.format(50000, currencySymbol: '₹'), equals('₹500.00'));
      expect(MoneyUtils.format(-5025, currencySymbol: '₹'), equals('-₹50.25'));
      expect(
        MoneyUtils.format(10000, currencySymbol: '₹', showSign: true),
        equals('+₹100.00'),
      );
    });
  });
}
