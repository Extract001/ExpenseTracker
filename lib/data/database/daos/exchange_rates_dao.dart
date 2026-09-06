import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/exchange_rates_table.dart';

part 'exchange_rates_dao.g.dart';

@DriftAccessor(tables: [ExchangeRatesTable])
class ExchangeRatesDao extends DatabaseAccessor<AppDatabase>
    with _$ExchangeRatesDaoMixin {
  ExchangeRatesDao(super.db);

  Future<ExchangeRateData?> getRate(
    String baseCurrency,
    String targetCurrency,
  ) {
    final base = baseCurrency.toUpperCase();
    final target = targetCurrency.toUpperCase();
    return (select(exchangeRatesTable)..where(
          (r) => r.baseCurrency.equals(base) & r.targetCurrency.equals(target),
        ))
        .getSingleOrNull();
  }

  Future<List<ExchangeRateData>> getAllRates() {
    return select(exchangeRatesTable).get();
  }

  Stream<List<ExchangeRateData>> watchAllRates() {
    return select(exchangeRatesTable).watch();
  }

  Future<int> insertOrUpdateRate(ExchangeRatesTableCompanion entry) {
    return into(exchangeRatesTable).insertOnConflictUpdate(entry);
  }

  Future<void> insertOrUpdateRates(
    List<ExchangeRatesTableCompanion> entries,
  ) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(exchangeRatesTable, entries);
    });
  }
}
