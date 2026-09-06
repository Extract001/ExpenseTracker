import 'package:flutter/material.dart';
import '../../core/currency/currency_converter.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/account_entity.dart';
import '../../domain/repositories/i_exchange_rate_repository.dart';
import 'settings_provider.dart';

class CurrencyProvider extends ChangeNotifier {
  final IExchangeRateRepository _repository;
  final SettingsProvider _settingsProvider;

  bool _isRefreshing = false;
  String? _lastError;
  bool _isDisposed = false;

  CurrencyProvider({
    required IExchangeRateRepository repository,
    required SettingsProvider settingsProvider,
  }) : _repository = repository,
       _settingsProvider = settingsProvider;

  String get baseCurrency => _settingsProvider.currency;
  bool get isRefreshing => _isRefreshing;
  String? get lastError => _lastError;

  /// Converts an amount in minor units from [fromCurrency] to target currency (defaults to [baseCurrency]).
  /// Returns null if conversion rate is completely unavailable.
  Future<int?> convert({
    required int amountMinor,
    required String fromCurrency,
    String? toCurrency,
  }) async {
    final target = (toCurrency ?? baseCurrency).toUpperCase();
    final source = fromCurrency.toUpperCase();

    if (source == target) return amountMinor;
    if (amountMinor == 0) return 0;

    try {
      final rateEntity = await _repository.getRate(source, target);
      if (rateEntity == null || rateEntity.rateMicroUnits <= 0) {
        return null;
      }
      return CurrencyConverter.convert(
        amountMinor: amountMinor,
        fromCurrency: source,
        toCurrency: target,
        rateMicroUnits: rateEntity.rateMicroUnits,
      );
    } catch (e) {
      AppLogger.warning('CURRENCY_CONVERT_FAILED', error: e);
      return null;
    }
  }

  /// Calculates total net worth in [baseCurrency] across all active accounts.
  /// If an account's rate is unavailable, its native balance is included as a fallback.
  Future<int> calculateTotalNetWorthInBaseCurrency({
    required List<AccountEntity> accounts,
    required Future<int> Function(String accountId) getAccountBalance,
  }) async {
    int totalMinor = 0;
    final targetBase = baseCurrency.toUpperCase();

    for (final acc in accounts) {
      if (acc.isDeleted) continue;
      final balanceMinor = await getAccountBalance(acc.id);
      final accCurrency = acc.currency.toUpperCase();

      if (accCurrency == targetBase) {
        totalMinor += balanceMinor;
      } else {
        final converted = await convert(
          amountMinor: balanceMinor,
          fromCurrency: accCurrency,
          toCurrency: targetBase,
        );
        totalMinor += (converted ?? balanceMinor);
      }
    }

    return totalMinor;
  }

  /// Refreshes exchange rates from remote network in background.
  Future<void> refreshRatesOnline() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _lastError = null;
    _safeNotifyListeners();

    try {
      await _repository.refreshRatesFromRemote(baseCurrency: baseCurrency);
    } catch (e) {
      _lastError = 'Exchange rate update failed';
      AppLogger.warning('EXCHANGE_RATE_ONLINE_REFRESH_ERROR', error: e);
    } finally {
      _isRefreshing = false;
      _safeNotifyListeners();
    }
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
