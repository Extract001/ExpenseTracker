// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exchange_rates_dao.dart';

// ignore_for_file: type=lint
mixin _$ExchangeRatesDaoMixin on DatabaseAccessor<AppDatabase> {
  $ExchangeRatesTableTable get exchangeRatesTable =>
      attachedDatabase.exchangeRatesTable;
  ExchangeRatesDaoManager get managers => ExchangeRatesDaoManager(this);
}

class ExchangeRatesDaoManager {
  final _$ExchangeRatesDaoMixin _db;
  ExchangeRatesDaoManager(this._db);
  $$ExchangeRatesTableTableTableManager get exchangeRatesTable =>
      $$ExchangeRatesTableTableTableManager(
        _db.attachedDatabase,
        _db.exchangeRatesTable,
      );
}
