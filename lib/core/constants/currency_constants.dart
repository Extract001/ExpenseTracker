class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final int decimalDigits;

  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimalDigits = 2,
  });
}

class CurrencyConstants {
  static const String defaultCurrencyCode = 'INR';

  static const List<CurrencyInfo> supportedCurrencies = [
    CurrencyInfo(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
    CurrencyInfo(code: 'USD', symbol: r'$', name: 'US Dollar'),
    CurrencyInfo(code: 'EUR', symbol: '€', name: 'Euro'),
    CurrencyInfo(code: 'GBP', symbol: '£', name: 'British Pound'),
    CurrencyInfo(
      code: 'JPY',
      symbol: '¥',
      name: 'Japanese Yen',
      decimalDigits: 0,
    ),
    CurrencyInfo(code: 'CAD', symbol: r'CA$', name: 'Canadian Dollar'),
    CurrencyInfo(code: 'AUD', symbol: r'AU$', name: 'Australian Dollar'),
    CurrencyInfo(code: 'AED', symbol: 'AED', name: 'UAE Dirham'),
    CurrencyInfo(code: 'SGD', symbol: r'SG$', name: 'Singapore Dollar'),
  ];

  static CurrencyInfo getCurrency(String code) {
    return supportedCurrencies.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () =>
          const CurrencyInfo(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
    );
  }
}
