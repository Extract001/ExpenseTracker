class ExchangeRateEntity {
  final String baseCurrency;
  final String targetCurrency;
  final int
  rateMicroUnits; // Rate multiplied by 1,000,000 (e.g. 83.50 INR/USD -> 83,500,000)
  final DateTime fetchedAt;
  final DateTime updatedAt;
  final String source;

  const ExchangeRateEntity({
    required this.baseCurrency,
    required this.targetCurrency,
    required this.rateMicroUnits,
    required this.fetchedAt,
    required this.updatedAt,
    this.source = 'cache',
  });

  /// Approximate decimal representation for display or logging purposes.
  double get rate => rateMicroUnits / 1000000.0;

  ExchangeRateEntity copyWith({
    String? baseCurrency,
    String? targetCurrency,
    int? rateMicroUnits,
    DateTime? fetchedAt,
    DateTime? updatedAt,
    String? source,
  }) {
    return ExchangeRateEntity(
      baseCurrency: baseCurrency ?? this.baseCurrency,
      targetCurrency: targetCurrency ?? this.targetCurrency,
      rateMicroUnits: rateMicroUnits ?? this.rateMicroUnits,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
    );
  }
}
