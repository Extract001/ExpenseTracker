import '../constants/currency_constants.dart';

/// High-precision financial currency converter using deterministic integer minor units.
///
/// Multi-currency arithmetic uses micro-rate integer scaling (factor 10^6, precision 0.000001):
///   - 1 USD = 83.500000 INR -> 83,500,000 microUnits
///   - Half-Up rounding is strictly applied: ((scaledAmount * rateMicroUnits) + 500_000) ~/ 1_000_000
///   - Eliminates IEEE 754 binary floating-point roundoff errors completely.
class CurrencyConverter {
  static const int microScalingFactor = 1000000;

  /// Converts an integer minor unit amount from [fromCurrency] to [toCurrency] using [rateMicroUnits].
  ///
  /// - If [fromCurrency] == [toCurrency], returns [amountMinor] unchanged.
  /// - Automatically adjusts for differing minor unit decimal digits (e.g. JPY=0, USD/INR=2, BHD=3).
  /// - Applies Half-Up rounding to preserve monetary conservation.
  static int convert({
    required int amountMinor,
    required String fromCurrency,
    required String toCurrency,
    required int rateMicroUnits,
  }) {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();

    if (from == to) {
      return amountMinor;
    }
    if (amountMinor == 0) return 0;
    if (rateMicroUnits <= 0) {
      throw ArgumentError(
        'Exchange rate micro units must be strictly positive (> 0), got: $rateMicroUnits',
      );
    }

    final fromInfo = CurrencyConstants.getCurrency(from);
    final toInfo = CurrencyConstants.getCurrency(to);

    // Decimal adjustment factor
    final digitDiff = toInfo.decimalDigits - fromInfo.decimalDigits;
    int scaledAmount = amountMinor;
    if (digitDiff > 0) {
      for (int i = 0; i < digitDiff; i++) {
        scaledAmount *= 10;
      }
    } else if (digitDiff < 0) {
      for (int i = 0; i < -digitDiff; i++) {
        // Half-up rounding when reducing decimal places
        scaledAmount = (scaledAmount + (scaledAmount < 0 ? -5 : 5)) ~/ 10;
      }
    }

    final sign = scaledAmount < 0 ? -1 : 1;
    final absAmount = scaledAmount.abs();

    // Standard Half-Up rounding formula:
    // ((absAmount * rateMicroUnits) + (microScalingFactor / 2)) / microScalingFactor
    final convertedAbs =
        ((absAmount * rateMicroUnits) + (microScalingFactor ~/ 2)) ~/
        microScalingFactor;

    return convertedAbs * sign;
  }
}
