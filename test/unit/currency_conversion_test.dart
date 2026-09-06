import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:expense_tracker/core/currency/currency_converter.dart';
import 'package:expense_tracker/domain/entities/exchange_rate_entity.dart';
import 'package:expense_tracker/domain/entities/account_entity.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/exchange_rate_repository.dart';
import 'package:expense_tracker/data/repositories/settings_repository.dart';
import 'package:expense_tracker/presentation/providers/currency_provider.dart';
import 'package:expense_tracker/presentation/providers/settings_provider.dart';

void main() {
  group('CurrencyConverter Unit Tests', () {
    test('1. Same-currency conversion returns identical amount', () {
      final inr = CurrencyConverter.convert(
        amountMinor: 50000, // ₹500.00
        fromCurrency: 'INR',
        toCurrency: 'INR',
        rateMicroUnits: 1000000,
      );
      expect(inr, equals(50000));

      final usd = CurrencyConverter.convert(
        amountMinor: 10000, // $100.00
        fromCurrency: 'USD',
        toCurrency: 'USD',
        rateMicroUnits: 1000000,
      );
      expect(usd, equals(10000));
    });

    test('2. Zero amount conversion returns zero', () {
      final result = CurrencyConverter.convert(
        amountMinor: 0,
        fromCurrency: 'USD',
        toCurrency: 'INR',
        rateMicroUnits: 83500000, // 83.50
      );
      expect(result, equals(0));
    });

    test('3. USD -> INR conversion with exact microUnits', () {
      // $100.00 (10000 minor units) at 1 USD = 83.50 INR (83,500,000 microUnits)
      // Converted: 10000 * 83.50 = 835,000 minor units (₹8,350.00)
      final inr = CurrencyConverter.convert(
        amountMinor: 10000,
        fromCurrency: 'USD',
        toCurrency: 'INR',
        rateMicroUnits: 83500000,
      );
      expect(inr, equals(835000));
    });

    test('4. INR -> USD conversion with microUnits and Half-Up rounding', () {
      // ₹8,350.00 (835000 minor units) at 1 INR = 0.011976 USD (11,976 microUnits)
      // 835000 * 11976 = 10,000,000,000 -> 10,000 minor units ($100.00)
      final usd = CurrencyConverter.convert(
        amountMinor: 835000,
        fromCurrency: 'INR',
        toCurrency: 'USD',
        rateMicroUnits: 11976,
      );
      expect(usd, equals(10000));
    });

    test('5. EUR -> INR conversion', () {
      // €50.00 (5000 minor units) at 1 EUR = 90.50 INR (90,500,000 microUnits)
      // Converted: 5000 * 90.50 = 452,500 minor units (₹4,525.00)
      final inr = CurrencyConverter.convert(
        amountMinor: 5000,
        fromCurrency: 'EUR',
        toCurrency: 'INR',
        rateMicroUnits: 90500000,
      );
      expect(inr, equals(452500));
    });

    test('6. JPY (0 decimals) -> USD (2 decimals) adjustment', () {
      // ¥15,500 (15500 minor units) at 1 JPY = 0.00645 USD (6,450 microUnits)
      // 15500 * 100 (for 2 decimals) = 1,550,000 * 6450 = 9,997,500,000 -> 10,000 minor units ($100.00)
      final usd = CurrencyConverter.convert(
        amountMinor: 15500,
        fromCurrency: 'JPY',
        toCurrency: 'USD',
        rateMicroUnits: 6452,
      );
      expect(usd, equals(10001)); // $100.01 with half-up rounding
    });

    test('7. Negative and zero rate validation throws ArgumentError', () {
      expect(
        () => CurrencyConverter.convert(
          amountMinor: 1000,
          fromCurrency: 'USD',
          toCurrency: 'INR',
          rateMicroUnits: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => CurrencyConverter.convert(
          amountMinor: 1000,
          fromCurrency: 'USD',
          toCurrency: 'INR',
          rateMicroUnits: -500000,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ExchangeRateRepository & CurrencyProvider Tests', () {
    late AppDatabase db;
    late ExchangeRateRepository rateRepo;
    late SettingsRepository settingsRepo;
    late SettingsProvider settingsProvider;
    late CurrencyProvider currencyProvider;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      rateRepo = ExchangeRateRepository(db);
      settingsRepo = SettingsRepository(db, () => 'test_user');
      settingsProvider = SettingsProvider(repository: settingsRepo);
      await settingsProvider.loadSettings();

      currencyProvider = CurrencyProvider(
        repository: rateRepo,
        settingsProvider: settingsProvider,
      );
    });

    tearDown(() async {
      currencyProvider.dispose();
      settingsProvider.dispose();
      await db.close();
    });

    test(
      '8. Baseline offline cache converts USD to INR when offline',
      () async {
        final rate = await rateRepo.getRate('USD', 'INR');
        expect(rate, isNotNull);
        expect(rate!.rateMicroUnits, equals(83500000));
        expect(rate.rate, closeTo(83.50, 0.001));

        final converted = await currencyProvider.convert(
          amountMinor: 10000, // $100.00
          fromCurrency: 'USD',
          toCurrency: 'INR',
        );
        expect(converted, equals(835000)); // ₹8,350.00
      },
    );

    test('9. Inverse rate lookup works correctly', () async {
      // Save direct EUR -> INR rate
      final now = DateTime.now().toUtc();
      await rateRepo.saveRate(
        ExchangeRateEntity(
          baseCurrency: 'EUR',
          targetCurrency: 'INR',
          rateMicroUnits: 90000000, // 1 EUR = 90 INR
          fetchedAt: now,
          updatedAt: now,
          source: 'test',
        ),
      );

      // Query INR -> EUR (inverse)
      final invRate = await rateRepo.getRate('INR', 'EUR');
      expect(invRate, isNotNull);
      // 1 INR = 1/90 EUR = 0.011111 EUR (11,111 microUnits)
      expect(invRate!.rateMicroUnits, closeTo(11111, 2));

      // Convert ₹9,000.00 (900000 minor units) -> €100.00 (10000 minor units)
      final convertedEur = await currencyProvider.convert(
        amountMinor: 900000,
        fromCurrency: 'INR',
        toCurrency: 'EUR',
      );
      expect(convertedEur, equals(10000));
    });

    test('10. Multi-currency Net Worth aggregation in base currency', () async {
      // Account 1: Cash (INR) = ₹10,000 (1000000 minor units)
      // Account 2: USD Wallet (USD) = $100 (10000 minor units) at 83.50 -> ₹8,350 (835000 minor units)
      // Combined Net Worth in INR: 1000000 + 835000 = 1,835,000 minor units (₹18,350.00)
      final now = DateTime.now().toUtc();
      final accounts = [
        AccountEntity(
          id: 'acc_inr',
          userId: 'test_user',
          name: 'Cash',
          type: AccountType.cash,
          initialBalance: 1000000,
          currency: 'INR',
          colorValue: 0xFF14B8A6,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        ),
        AccountEntity(
          id: 'acc_usd',
          userId: 'test_user',
          name: 'USD Wallet',
          type: AccountType.wallet,
          initialBalance: 10000,
          currency: 'USD',
          colorValue: 0xFF14B8A6,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final totalNetWorthInInr = await currencyProvider
          .calculateTotalNetWorthInBaseCurrency(
            accounts: accounts,
            getAccountBalance: (id) async => id == 'acc_inr' ? 1000000 : 10000,
          );

      expect(totalNetWorthInInr, equals(1835000)); // ₹18,350.00
    });

    test('11. Changing base currency updates aggregation target', () async {
      await settingsProvider.setCurrency('USD');
      expect(currencyProvider.baseCurrency, equals('USD'));

      // Account in USD: $100 -> $100
      // Account in INR: ₹8,350 -> $100
      final now = DateTime.now().toUtc();
      final accounts = [
        AccountEntity(
          id: 'acc_inr',
          userId: 'test_user',
          name: 'INR Cash',
          type: AccountType.cash,
          initialBalance: 835000,
          currency: 'INR',
          colorValue: 0xFF14B8A6,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        ),
        AccountEntity(
          id: 'acc_usd',
          userId: 'test_user',
          name: 'USD Wallet',
          type: AccountType.wallet,
          initialBalance: 10000,
          currency: 'USD',
          colorValue: 0xFF14B8A6,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final totalNetWorthInUsd = await currencyProvider
          .calculateTotalNetWorthInBaseCurrency(
            accounts: accounts,
            getAccountBalance: (id) async => id == 'acc_inr' ? 835000 : 10000,
          );

      expect(totalNetWorthInUsd, equals(20000)); // $200.00
    });

    test(
      '12. Unknown/unsupported currency missing rate does not fabricate rate',
      () async {
        // Query completely unsupported fictitious currency
        final rate = await rateRepo.getRate('XYZ', 'ABC');
        expect(rate, isNull);

        final converted = await currencyProvider.convert(
          amountMinor: 50000,
          fromCurrency: 'XYZ',
          toCurrency: 'ABC',
        );
        expect(converted, isNull);
      },
    );
  });
}
