import 'package:drift/drift.dart';

@DataClassName('ExchangeRateData')
@TableIndex(
  name: 'idx_exchange_rates_pair',
  columns: {#baseCurrency, #targetCurrency},
)
class ExchangeRatesTable extends Table {
  @override
  String get tableName => 'exchange_rates';

  TextColumn get baseCurrency =>
      text().withLength(min: 3, max: 5)(); // e.g. 'USD'
  TextColumn get targetCurrency =>
      text().withLength(min: 3, max: 5)(); // e.g. 'INR'
  IntColumn get rateMicroUnits =>
      integer()(); // 1 base = rateMicroUnits / 10^6 target (e.g. 83500000 for 83.50)
  DateTimeColumn get fetchedAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();
  TextColumn get source => text().withDefault(const Constant('cache'))();

  @override
  Set<Column> get primaryKey => {baseCurrency, targetCurrency};
}
