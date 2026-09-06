import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:expense_tracker/domain/entities/account_entity.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:expense_tracker/domain/entities/exchange_rate_entity.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/account_repository.dart';
import 'package:expense_tracker/data/repositories/transaction_repository.dart';
import 'package:expense_tracker/data/repositories/exchange_rate_repository.dart';
import 'package:expense_tracker/data/repositories/settings_repository.dart';
import 'package:expense_tracker/presentation/providers/currency_provider.dart';
import 'package:expense_tracker/presentation/providers/settings_provider.dart';

void main() {
  group('Multi-Currency End-to-End Integration Tests', () {
    late AppDatabase db;
    late AccountRepository accountRepo;
    late TransactionRepository txRepo;
    late ExchangeRateRepository rateRepo;
    late SettingsRepository settingsRepo;
    late SettingsProvider settingsProvider;
    late CurrencyProvider currencyProvider;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      accountRepo = AccountRepository(db, () => 'user_multi_currency');
      txRepo = TransactionRepository(db, () => 'user_multi_currency');
      rateRepo = ExchangeRateRepository(db);
      settingsRepo = SettingsRepository(db, () => 'user_multi_currency');
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
      '1. End-to-End: Create INR & USD accounts, add transactions, convert combined net worth',
      () async {
        final now = DateTime.now().toUtc();

        // Step A: Create INR Account with ₹5,000 initial balance (500000 minor units)
        final inrAccount = AccountEntity(
          id: 'acc_inr_main',
          userId: 'user_multi_currency',
          name: 'HDFC INR Account',
          type: AccountType.bank,
          initialBalance: 500000,
          currency: 'INR',
          colorValue: 0xFF14B8A6,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        );
        await accountRepo.createAccount(inrAccount);

        // Step B: Create USD Account with $200 initial balance (20000 minor units)
        final usdAccount = AccountEntity(
          id: 'acc_usd_main',
          userId: 'user_multi_currency',
          name: 'US Bank USD Account',
          type: AccountType.bank,
          initialBalance: 20000,
          currency: 'USD',
          colorValue: 0xFF1A56DB,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        );
        await accountRepo.createAccount(usdAccount);

        // Step C: Add $50 expense to USD account (5000 minor units) -> USD balance becomes $150 (15000 minor)
        await txRepo.createTransaction(
          TransactionEntity(
            id: 'tx_usd_1',
            userId: 'user_multi_currency',
            amount: 5000,
            type: TransactionType.expense,
            categoryId: 'cat_food',
            accountId: 'acc_usd_main',
            note: 'US Grocery',
            date: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Step D: Add ₹2,000 income to INR account (200000 minor units) -> INR balance becomes ₹7,000 (700000 minor)
        await txRepo.createTransaction(
          TransactionEntity(
            id: 'tx_inr_1',
            userId: 'user_multi_currency',
            amount: 200000,
            type: TransactionType.income,
            categoryId: 'cat_salary',
            accountId: 'acc_inr_main',
            note: 'Salary credit',
            date: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Check native balances
        final inrBalance = await db.accountDao.getAccountBalance(
          userId: 'user_multi_currency',
          accountId: 'acc_inr_main',
        );
        expect(inrBalance, equals(700000)); // ₹7,000.00

        final usdBalance = await db.accountDao.getAccountBalance(
          userId: 'user_multi_currency',
          accountId: 'acc_usd_main',
        );
        expect(usdBalance, equals(15000)); // $150.00

        // Step E: Store custom exchange rate: 1 USD = 80.00 INR (80,000,000 microUnits)
        await rateRepo.saveRate(
          ExchangeRateEntity(
            baseCurrency: 'USD',
            targetCurrency: 'INR',
            rateMicroUnits: 80000000,
            fetchedAt: now,
            updatedAt: now,
            source: 'manual_test',
          ),
        );

        // Step F: Calculate combined net worth in INR (Base Currency):
        // INR account = ₹7,000 (700000 minor)
        // USD account = $150 (15000 minor) * 80.00 = ₹12,000 (1200000 minor)
        // Total = ₹19,000 (1900000 minor)
        final allAccounts = await accountRepo.getAllAccounts();
        final totalNetWorthInInr = await currencyProvider
            .calculateTotalNetWorthInBaseCurrency(
              accounts: allAccounts,
              getAccountBalance: (id) => db.accountDao.getAccountBalance(
                userId: 'user_multi_currency',
                accountId: id,
              ),
            );

        expect(totalNetWorthInInr, equals(1900000)); // ₹19,000.00
      },
    );

    test(
      '2. Offline persistence: cached rates survive simulated network loss',
      () async {
        final now = DateTime.now().toUtc();
        await rateRepo.saveRate(
          ExchangeRateEntity(
            baseCurrency: 'GBP',
            targetCurrency: 'INR',
            rateMicroUnits: 105000000, // 1 GBP = 105.00 INR
            fetchedAt: now,
            updatedAt: now,
            source: 'cached_network',
          ),
        );

        // Simulate offline / no network: verify cached rate is returned
        final cachedRate = await rateRepo.getRate('GBP', 'INR');
        expect(cachedRate, isNotNull);
        expect(cachedRate!.rateMicroUnits, equals(105000000));
        expect(cachedRate.source, equals('cached_network'));

        final converted = await currencyProvider.convert(
          amountMinor: 2000, // £20.00
          fromCurrency: 'GBP',
          toCurrency: 'INR',
        );
        expect(converted, equals(210000)); // ₹2,100.00
      },
    );

    test(
      '3. Exact Offline Lifecycle: USD account + cached rate + restart + offline conversion verification',
      () async {
        // Step 1: Create USD account
        final now = DateTime.now().toUtc();
        final usdAcc = AccountEntity(
          id: 'acc_usd_restart',
          userId: 'user_multi_currency',
          name: 'Overseas USD Account',
          type: AccountType.bank,
          initialBalance: 25000, // $250.00
          currency: 'USD',
          colorValue: 0xFF1A56DB,
          iconCodePoint: 0xe040,
          createdAt: now,
          updatedAt: now,
        );
        await accountRepo.createAccount(usdAcc);

        // Step 2: Store known USD -> INR exchange rate locally (84.00 INR -> 84,000,000 microUnits)
        final fetchedTime = DateTime.utc(2026, 9, 1, 12, 0, 0);
        await rateRepo.saveRate(
          ExchangeRateEntity(
            baseCurrency: 'USD',
            targetCurrency: 'INR',
            rateMicroUnits: 84000000, // 84.00
            fetchedAt: fetchedTime,
            updatedAt: fetchedTime,
            source: 'open.er-api.com',
          ),
        );

        // Step 3: Create USD transaction ($50.00 expense -> balance becomes $200.00 / 20000 minor)
        await txRepo.createTransaction(
          TransactionEntity(
            id: 'tx_usd_restart_1',
            userId: 'user_multi_currency',
            amount: 5000,
            type: TransactionType.expense,
            categoryId: 'cat_travel',
            accountId: 'acc_usd_restart',
            note: 'Flight ticket',
            date: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Step 4 & 5: Simulate app restart by instantiating new repositories & provider over the same database
        final reloadedRateRepo = ExchangeRateRepository(db);
        final reloadedSettingsRepo = SettingsRepository(
          db,
          () => 'user_multi_currency',
        );
        final reloadedSettingsProvider = SettingsProvider(
          repository: reloadedSettingsRepo,
        );
        await reloadedSettingsProvider.loadSettings();
        await reloadedSettingsProvider.setCurrency(
          'INR',
        ); // Base currency is INR

        final reloadedCurrencyProvider = CurrencyProvider(
          repository: reloadedRateRepo,
          settingsProvider: reloadedSettingsProvider,
        );

        // Step 6 & 7: Verify cached rate is fetched from Drift without network access
        final loadedRate = await reloadedRateRepo.getRate(
          'USD',
          'INR',
          allowBootstrapFallback: false,
        );
        expect(loadedRate, isNotNull);
        expect(loadedRate!.rateMicroUnits, equals(84000000));
        expect(loadedRate.source, equals('open.er-api.com'));
        expect(loadedRate.fetchedAt.toUtc(), equals(fetchedTime));

        // Step 8: Verify converted INR value is correct: $200.00 (20000 minor) * 84.00 = ₹16,800.00 (1680000 minor)
        final balance = await db.accountDao.getAccountBalance(
          userId: 'user_multi_currency',
          accountId: 'acc_usd_restart',
        );
        expect(balance, equals(20000));

        final convertedMinor = await reloadedCurrencyProvider.convert(
          amountMinor: balance,
          fromCurrency: 'USD',
          toCurrency: 'INR',
        );
        expect(convertedMinor, equals(1680000)); // ₹16,800.00

        reloadedCurrencyProvider.dispose();
        reloadedSettingsProvider.dispose();
      },
    );

    test(
      '4. No cached rate + Offline handles missing rates gracefully without crash or fabricated conversion',
      () async {
        // Rate between CHF and BRL has never been fetched or cached
        final missingRate = await rateRepo.getRate(
          'CHF',
          'BRL',
          allowBootstrapFallback: false,
        );
        expect(missingRate, isNull);

        final result = await currencyProvider.convert(
          amountMinor: 50000,
          fromCurrency: 'CHF',
          toCurrency: 'BRL',
        );
        // Must return null instead of inventing a rate
        expect(result, isNull);
      },
    );
  });
}
