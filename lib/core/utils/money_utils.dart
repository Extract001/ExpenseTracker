import 'package:intl/intl.dart';

/// Utilities for precise financial calculations using integer minor units (e.g. cents, paise).
/// Eliminates all binary floating-point rounding errors.
class MoneyUtils {
  /// Converts a major units decimal string (e.g. "125.50") or number to integer minor units (e.g. 12550).
  static int parseToMinorUnits(String input, {int decimalDigits = 2}) {
    final cleaned = input.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return 0;

    final parts = cleaned.split('.');
    final integerPart = int.tryParse(parts[0]) ?? 0;

    if (decimalDigits == 0 || parts.length == 1) {
      return integerPart * _multiplier(decimalDigits);
    }

    String fractionPart = parts[1];
    if (fractionPart.length > decimalDigits) {
      fractionPart = fractionPart.substring(0, decimalDigits);
    } else {
      fractionPart = fractionPart.padRight(decimalDigits, '0');
    }

    final fractionInt = int.tryParse(fractionPart) ?? 0;
    final sign = integerPart < 0 || cleaned.startsWith('-') ? -1 : 1;
    return (integerPart.abs() * _multiplier(decimalDigits) + fractionInt) *
        sign;
  }

  /// Converts integer minor units (e.g. 12550) to major units double (e.g. 125.50) for UI display or charts.
  static double toMajorUnits(int minorUnits, {int decimalDigits = 2}) {
    if (decimalDigits == 0) return minorUnits.toDouble();
    return minorUnits / _multiplier(decimalDigits);
  }

  /// Formats integer minor units to a clean currency display string.
  /// Example: 12550 minor units -> "$125.50" or "₹125.50"
  static String format(
    int minorUnits, {
    String currencySymbol = '₹',
    int decimalDigits = 2,
    bool showSign = false,
  }) {
    final isNegative = minorUnits < 0;
    final absMinor = minorUnits.abs();
    final major = absMinor ~/ _multiplier(decimalDigits);
    final minor = absMinor % _multiplier(decimalDigits);

    final formatter = NumberFormat('#,##0');
    final formattedMajor = formatter.format(major);

    String result;
    if (decimalDigits > 0) {
      final formattedMinor = minor.toString().padLeft(decimalDigits, '0');
      result = '$currencySymbol$formattedMajor.$formattedMinor';
    } else {
      result = '$currencySymbol$formattedMajor';
    }

    if (isNegative) {
      return '-$result';
    } else if (showSign && minorUnits > 0) {
      return '+$result';
    }
    return result;
  }

  /// Formats as plain amount without currency symbol.
  static String formatPlain(int minorUnits, {int decimalDigits = 2}) {
    final absMinor = minorUnits.abs();
    final major = absMinor ~/ _multiplier(decimalDigits);
    final minor = absMinor % _multiplier(decimalDigits);

    if (decimalDigits > 0) {
      final formattedMinor = minor.toString().padLeft(decimalDigits, '0');
      return '$major.$formattedMinor';
    }
    return '$major';
  }

  static int _multiplier(int decimalDigits) {
    int m = 1;
    for (int i = 0; i < decimalDigits; i++) {
      m *= 10;
    }
    return m;
  }
}
