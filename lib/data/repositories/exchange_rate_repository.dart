import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/exchange_rate_entity.dart';
import '../../domain/repositories/i_exchange_rate_repository.dart';
import '../database/app_database.dart';

class ExchangeRateRepository implements IExchangeRateRepository {
  final AppDatabase _db;
  final HttpClient Function()? _clientFactory;

  ExchangeRateRepository(this._db, [this._clientFactory]);

  /// Default baseline rates relative to USD (1 USD = X Target Currency)
  /// Used to seed baseline offline cache on clean installs.
  static final Map<String, int> defaultUsdRatesMicro = {
    'USD': 1000000, // 1.00
    'INR': 83500000, // 83.50
    'EUR': 920000, // 0.92
    'GBP': 780000, // 0.78
    'JPY': 155000000, // 155.00
    'CAD': 1360000, // 1.36
    'AUD': 1520000, // 1.52
    'AED': 3672500, // 3.6725
    'SGD': 1340000, // 1.34
  };

  @override
  Future<ExchangeRateEntity?> getRate(
    String fromCurrency,
    String toCurrency, {
    bool allowBootstrapFallback = true,
  }) async {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();

    if (from == to) {
      final now = DateTime.now().toUtc();
      return ExchangeRateEntity(
        baseCurrency: from,
        targetCurrency: to,
        rateMicroUnits: 1000000,
        fetchedAt: now,
        updatedAt: now,
        source: 'identity',
      );
    }

    // 1. Check direct pair in Drift SQLite (persisted online fetch or saved rate)
    final direct = await _db.exchangeRatesDao.getRate(from, to);
    if (direct != null && direct.rateMicroUnits > 0) {
      return ExchangeRateEntity(
        baseCurrency: direct.baseCurrency,
        targetCurrency: direct.targetCurrency,
        rateMicroUnits: direct.rateMicroUnits,
        fetchedAt: direct.fetchedAtUtc,
        updatedAt: direct.updatedAtUtc,
        source: direct.source,
      );
    }

    // 2. Check inverse pair in Drift SQLite
    final inverse = await _db.exchangeRatesDao.getRate(to, from);
    if (inverse != null && inverse.rateMicroUnits > 0) {
      final invRateMicro = ((1000000 * 1000000) ~/ inverse.rateMicroUnits);
      return ExchangeRateEntity(
        baseCurrency: from,
        targetCurrency: to,
        rateMicroUnits: invRateMicro,
        fetchedAt: inverse.fetchedAtUtc,
        updatedAt: inverse.updatedAtUtc,
        source: '${inverse.source}_inverse',
      );
    }

    // 3. Check triangulated pair via USD in Drift SQLite
    final fromToUsd = await _db.exchangeRatesDao.getRate(from, 'USD');
    final usdToTarget = await _db.exchangeRatesDao.getRate('USD', to);
    if (fromToUsd != null &&
        usdToTarget != null &&
        fromToUsd.rateMicroUnits > 0 &&
        usdToTarget.rateMicroUnits > 0) {
      final crossMicro =
          ((fromToUsd.rateMicroUnits * usdToTarget.rateMicroUnits) ~/ 1000000);
      return ExchangeRateEntity(
        baseCurrency: from,
        targetCurrency: to,
        rateMicroUnits: crossMicro,
        fetchedAt: fromToUsd.fetchedAtUtc,
        updatedAt: fromToUsd.updatedAtUtc,
        source: 'persisted_triangulated',
      );
    }

    // 4. Fallback to bootstrap/default rates only if explicitly allowed
    if (allowBootstrapFallback) {
      final fromUsdRate = defaultUsdRatesMicro[from];
      final toUsdRate = defaultUsdRatesMicro[to];
      if (fromUsdRate != null && toUsdRate != null && fromUsdRate > 0) {
        final crossRateMicro = ((toUsdRate * 1000000) ~/ fromUsdRate);
        final now = DateTime.now().toUtc();
        return ExchangeRateEntity(
          baseCurrency: from,
          targetCurrency: to,
          rateMicroUnits: crossRateMicro,
          fetchedAt: now,
          updatedAt: now,
          source: 'bootstrap_default',
        );
      }
    }

    return null;
  }

  @override
  Future<List<ExchangeRateEntity>> getAllRates() async {
    final list = await _db.exchangeRatesDao.getAllRates();
    return list
        .map(
          (r) => ExchangeRateEntity(
            baseCurrency: r.baseCurrency,
            targetCurrency: r.targetCurrency,
            rateMicroUnits: r.rateMicroUnits,
            fetchedAt: r.fetchedAtUtc,
            updatedAt: r.updatedAtUtc,
            source: r.source,
          ),
        )
        .toList();
  }

  @override
  Stream<List<ExchangeRateEntity>> watchAllRates() {
    return _db.exchangeRatesDao.watchAllRates().map(
      (list) => list
          .map(
            (r) => ExchangeRateEntity(
              baseCurrency: r.baseCurrency,
              targetCurrency: r.targetCurrency,
              rateMicroUnits: r.rateMicroUnits,
              fetchedAt: r.fetchedAtUtc,
              updatedAt: r.updatedAtUtc,
              source: r.source,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> saveRate(ExchangeRateEntity rate) async {
    final companion = ExchangeRatesTableCompanion(
      baseCurrency: Value(rate.baseCurrency.toUpperCase()),
      targetCurrency: Value(rate.targetCurrency.toUpperCase()),
      rateMicroUnits: Value(rate.rateMicroUnits),
      fetchedAtUtc: Value(rate.fetchedAt.toUtc()),
      updatedAtUtc: Value(rate.updatedAt.toUtc()),
      source: Value(rate.source),
    );
    await _db.exchangeRatesDao.insertOrUpdateRate(companion);
  }

  @override
  Future<void> saveRates(List<ExchangeRateEntity> rates) async {
    final companions = rates
        .map(
          (r) => ExchangeRatesTableCompanion(
            baseCurrency: Value(r.baseCurrency.toUpperCase()),
            targetCurrency: Value(r.targetCurrency.toUpperCase()),
            rateMicroUnits: Value(r.rateMicroUnits),
            fetchedAtUtc: Value(r.fetchedAt.toUtc()),
            updatedAtUtc: Value(r.updatedAt.toUtc()),
            source: Value(r.source),
          ),
        )
        .toList();
    await _db.exchangeRatesDao.insertOrUpdateRates(companions);
  }

  @override
  Future<bool> refreshRatesFromRemote({String baseCurrency = 'USD'}) async {
    HttpClient? client;
    try {
      final base = baseCurrency.toUpperCase();
      client = _clientFactory?.call() ?? HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final uri = Uri.parse('https://open.er-api.com/v6/latest/$base');
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final ratesMap = json['rates'] as Map<String, dynamic>?;

        if (ratesMap != null && ratesMap.isNotEmpty) {
          final now = DateTime.now().toUtc();
          final List<ExchangeRateEntity> entities = [];

          for (final entry in ratesMap.entries) {
            final targetCode = entry.key.toUpperCase();
            final numVal = entry.value;
            if (numVal is num && numVal > 0) {
              final rateMicro = (numVal * 1000000).round();
              entities.add(
                ExchangeRateEntity(
                  baseCurrency: base,
                  targetCurrency: targetCode,
                  rateMicroUnits: rateMicro,
                  fetchedAt: now,
                  updatedAt: now,
                  source: 'open.er-api.com',
                ),
              );
            }
          }

          if (entities.isNotEmpty) {
            await saveRates(entities);
            AppLogger.info(
              'EXCHANGE_RATES_REFRESHED',
              metadata: {'base': base, 'count': entities.length},
            );
            return true;
          }
        }
      }
    } catch (e) {
      AppLogger.warning('EXCHANGE_RATE_FETCH_FAILED', error: e);
    } finally {
      client?.close();
    }
    return false;
  }
}
