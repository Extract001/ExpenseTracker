import '../entities/exchange_rate_entity.dart';

abstract class IExchangeRateRepository {
  /// Retrieves the latest cached exchange rate between [fromCurrency] and [toCurrency].
  /// Returns null if no cached or direct/inverse rate is found.
  Future<ExchangeRateEntity?> getRate(String fromCurrency, String toCurrency);

  /// Retrieves all cached exchange rates.
  Future<List<ExchangeRateEntity>> getAllRates();

  /// Watches all cached exchange rates reactively.
  Stream<List<ExchangeRateEntity>> watchAllRates();

  /// Persists or updates an individual exchange rate in local cache.
  Future<void> saveRate(ExchangeRateEntity rate);

  /// Persists a batch of exchange rates in local cache.
  Future<void> saveRates(List<ExchangeRateEntity> rates);

  /// Fetches latest exchange rates from remote network provider when online.
  /// Falls back safely to local cache on network error without throwing.
  Future<bool> refreshRatesFromRemote({String baseCurrency = 'USD'});
}
