import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/core/constants/app_constants.dart';
import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/core/utils/id_generator.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/account_repository.dart';
import 'package:expense_tracker/data/repositories/budget_repository.dart';
import 'package:expense_tracker/data/repositories/category_repository.dart';
import 'package:expense_tracker/data/repositories/goal_repository.dart';
import 'package:expense_tracker/data/repositories/recurring_transaction_repository.dart';
import 'package:expense_tracker/data/repositories/settings_repository.dart';
import 'package:expense_tracker/data/repositories/sync_repository.dart';
import 'package:expense_tracker/data/repositories/transaction_repository.dart';
import 'package:expense_tracker/domain/entities/account_entity.dart';
import 'package:expense_tracker/domain/entities/budget_entity.dart';
import 'package:expense_tracker/domain/entities/category_entity.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:expense_tracker/domain/entities/goal_entity.dart';
import 'package:expense_tracker/domain/entities/recurring_transaction_entity.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository transactionRepo;
  late AccountRepository accountRepo;
  late CategoryRepository categoryRepo;
  late BudgetRepository budgetRepo;
  late GoalRepository goalRepo;
  late RecurringTransactionRepository recurringRepo;
  late SettingsRepository settingsRepo;
  late SyncRepository syncRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    transactionRepo = TransactionRepository(db);
    accountRepo = AccountRepository(db);
    categoryRepo = CategoryRepository(db);
    budgetRepo = BudgetRepository(db);
    goalRepo = GoalRepository(db);
    recurringRepo = RecurringTransactionRepository(db);
    settingsRepo = SettingsRepository(db);
    syncRepo = SyncRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Audit 1: Field-Level Conflict Tracking & Metadata Preservation', () {
    test('Detailed field-level timestamp tracking on updates', () async {
      final t1 = DateTime.utc(2026, 9, 1, 10, 0, 0);
      final txId = IdGenerator.uuid();

      // 1. Initial creation at T1
      final tx = TransactionEntity(
        id: txId,
        userId: AppConstants.defaultUserId,
        amount: 15000, // 150.00 INR
        type: TransactionType.expense,
        categoryId: 'cat_food',
        accountId: 'acc_cash_default',
        note: 'Original Note',
        date: t1,
        createdAt: t1,
        updatedAt: t1,
        fieldTimestamps: {
          'amountMinor': t1.toIso8601String(),
          'note': t1.toIso8601String(),
          'categoryId': t1.toIso8601String(),
          'accountId': t1.toIso8601String(),
          'transactionType': t1.toIso8601String(),
          'transactionDateUtc': t1.toIso8601String(),
        },
      );
      await transactionRepo.createTransaction(tx);

      // Verify all initial field timestamps are T1
      final initialRecord = await transactionRepo.getTransactionById(txId);
      expect(
        initialRecord!.fieldTimestamps['amountMinor'],
        t1.toIso8601String(),
      );
      expect(initialRecord.fieldTimestamps['note'], t1.toIso8601String());
      expect(initialRecord.fieldTimestamps['categoryId'], t1.toIso8601String());

      // 2. Update ONLY note at T2
      await Future.delayed(const Duration(milliseconds: 10));
      final updateNoteTx = initialRecord.copyWith(note: 'Updated Note T2');
      await transactionRepo.updateTransaction(updateNoteTx);

      final afterNoteUpdate = await transactionRepo.getTransactionById(txId);
      final t2Note = afterNoteUpdate!.fieldTimestamps['note']!;
      expect(t2Note, isNot(equals(t1.toIso8601String())));
      expect(
        afterNoteUpdate.fieldTimestamps['amountMinor'],
        t1.toIso8601String(),
      );
      expect(
        afterNoteUpdate.fieldTimestamps['categoryId'],
        t1.toIso8601String(),
      );

      // 3. Update multiple fields (amount and categoryId) at T3
      await Future.delayed(const Duration(milliseconds: 10));
      final multiUpdateTx = afterNoteUpdate.copyWith(
        amount: 20000,
        categoryId: 'cat_shopping',
      );
      await transactionRepo.updateTransaction(multiUpdateTx);

      final afterMultiUpdate = await transactionRepo.getTransactionById(txId);
      expect(
        afterMultiUpdate!.fieldTimestamps['note'],
        t2Note,
      ); // Note timestamp unchanged
      expect(
        afterMultiUpdate.fieldTimestamps['amountMinor'],
        isNot(equals(t1.toIso8601String())),
      );
      expect(
        afterMultiUpdate.fieldTimestamps['categoryId'],
        isNot(equals(t1.toIso8601String())),
      );

      // 4. Update field to SAME value -> timestamp must NOT change
      final sameValueTx = afterMultiUpdate.copyWith(note: 'Updated Note T2');
      await transactionRepo.updateTransaction(sameValueTx);

      final afterSameValue = await transactionRepo.getTransactionById(txId);
      expect(afterSameValue!.fieldTimestamps['note'], t2Note); // Remains T2

      // 5. Soft delete does not destroy field timestamps
      await transactionRepo.softDeleteTransaction(txId);
      final dbRow = await db.transactionDao.getTransactionById(txId);
      expect(dbRow!.deletedAtUtc, isNotNull);
      final timestampsMap = jsonDecode(dbRow.fieldTimestampsJson) as Map;
      expect(timestampsMap.containsKey('amountMinor'), isTrue);
      expect(timestampsMap.containsKey('note'), isTrue);
    });
  });

  group('Audit 2: Sync Queue Coalescing State Machine & Atomicity', () {
    test(
      'Scenario A: CREATE -> UPDATE -> UPDATE => exactly 1 CREATE operation with final payload',
      () async {
        final txId = IdGenerator.uuid();
        final tx = TransactionEntity(
          id: txId,
          userId: AppConstants.defaultUserId,
          amount: 1000,
          type: TransactionType.expense,
          categoryId: 'cat_food',
          accountId: 'acc_cash_default',
          note: 'V1 Note',
          date: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await transactionRepo.createTransaction(tx);
        await transactionRepo.updateTransaction(tx.copyWith(note: 'V2 Note'));
        await transactionRepo.updateTransaction(
          tx.copyWith(note: 'V3 Note Final'),
        );

        final ops = await syncRepo.getPendingOperations();
        expect(ops.length, 1);
        expect(ops.first.entityId, txId);
        expect(ops.first.operationType, SyncOperationType.create);
        expect(ops.first.payloadJson.contains('V3 Note Final'), isTrue);
      },
    );

    test(
      'Scenario B: CREATE -> DELETE => 0 sync operations in queue',
      () async {
        final txId = IdGenerator.uuid();
        final tx = TransactionEntity(
          id: txId,
          userId: AppConstants.defaultUserId,
          amount: 5000,
          type: TransactionType.expense,
          categoryId: 'cat_travel',
          accountId: 'acc_cash_default',
          note: 'Taxi',
          date: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await transactionRepo.createTransaction(tx);
        expect(await syncRepo.getPendingCount(), 1);

        await transactionRepo.softDeleteTransaction(txId);
        expect(await syncRepo.getPendingCount(), 0);
      },
    );

    test(
      'Scenario C: SYNCED -> UPDATE -> UPDATE => exactly 1 UPDATE operation',
      () async {
        final txId = IdGenerator.uuid();
        final nowUtc = DateTime.now().toUtc();
        final tx = TransactionEntity(
          id: txId,
          userId: AppConstants.defaultUserId,
          amount: 8000,
          type: TransactionType.expense,
          categoryId: 'cat_bills',
          accountId: 'acc_bank_default',
          note: 'Electricity Bill',
          date: nowUtc,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );

        // Insert directly as SYNCED
        await transactionRepo.createTransaction(tx);
        await syncRepo.markOperationCompleted(
          (await syncRepo.getPendingOperations()).first.id,
        );
        await (db.update(
          db.transactionsTable,
        )..where((t) => t.id.equals(txId))).write(
          const TransactionsTableCompanion(syncStatus: Value('synced')),
        );

        expect(await syncRepo.getPendingCount(), 0);

        // Now perform updates
        await transactionRepo.updateTransaction(
          tx.copyWith(note: 'Electricity Bill Updated 1'),
        );
        await transactionRepo.updateTransaction(
          tx.copyWith(note: 'Electricity Bill Updated 2'),
        );

        final ops = await syncRepo.getPendingOperations();
        expect(ops.length, 1);
        expect(ops.first.entityId, txId);
        expect(ops.first.operationType, SyncOperationType.update);
        expect(
          ops.first.payloadJson.contains('Electricity Bill Updated 2'),
          isTrue,
        );
      },
    );

    test(
      'Scenario D: SYNCED -> UPDATE -> DELETE => exactly 1 DELETE operation',
      () async {
        final txId = IdGenerator.uuid();
        final nowUtc = DateTime.now().toUtc();
        final tx = TransactionEntity(
          id: txId,
          userId: AppConstants.defaultUserId,
          amount: 2000,
          type: TransactionType.expense,
          categoryId: 'cat_food',
          accountId: 'acc_cash_default',
          note: 'Snacks',
          date: nowUtc,
          createdAt: nowUtc,
          updatedAt: nowUtc,
        );

        await transactionRepo.createTransaction(tx);
        await syncRepo.markOperationCompleted(
          (await syncRepo.getPendingOperations()).first.id,
        );
        await (db.update(
          db.transactionsTable,
        )..where((t) => t.id.equals(txId))).write(
          const TransactionsTableCompanion(syncStatus: Value('synced')),
        );

        // Perform update then delete
        await transactionRepo.updateTransaction(
          tx.copyWith(note: 'Snacks Modified'),
        );
        expect(await syncRepo.getPendingCount(), 1);

        await transactionRepo.softDeleteTransaction(txId);
        final ops = await syncRepo.getPendingOperations();
        expect(ops.length, 1);
        expect(ops.first.entityId, txId);
        expect(ops.first.operationType, SyncOperationType.delete);
      },
    );
  });

  group('Audit 3: Recurring Transaction Determinism & Idempotency', () {
    test(
      'processDueRecurringRules uses deterministic ID and concurrent runs produce 0 duplicates',
      () async {
        final ruleStartDate = DateTime.utc(2026, 9, 1, 0, 0, 0);
        final rule = RecurringTransactionEntity(
          id: 'rule_rent_monthly',
          userId: AppConstants.defaultUserId,
          amount: 2500000, // 25,000 INR
          type: TransactionType.expense,
          categoryId: 'cat_rent',
          accountId: 'acc_bank_default',
          note: 'Apartment Monthly Rent',
          frequency: RecurrenceFrequency.monthly,
          startDate: ruleStartDate,
          nextDate: ruleStartDate,
          createdAt: ruleStartDate,
          updatedAt: ruleStartDate,
        );

        await recurringRepo.createRecurring(rule);

        final evalTime = DateTime.utc(2026, 9, 5, 0, 0, 0);

        // Concurrent invocation
        final results = await Future.wait([
          recurringRepo.processDueRecurringRules(evalTime),
          recurringRepo.processDueRecurringRules(evalTime),
        ]);

        // Exactly 1 transaction must be created across both concurrent executions
        final totalCreated = results.reduce((a, b) => a + b);
        expect(totalCreated, 1);

        // Verify transaction in database
        final txs = await transactionRepo.getTransactionsCursor();
        final rentTxs = txs
            .where((t) => t.recurringRuleId == 'rule_rent_monthly')
            .toList();
        expect(rentTxs.length, 1);
        final occurrenceMs = ruleStartDate.millisecondsSinceEpoch;
        expect(rentTxs.first.id, 'tx_rec_rule_rent_monthly_$occurrenceMs');

        // Consecutive run produces 0
        final consecutiveRun = await recurringRepo.processDueRecurringRules(
          evalTime,
        );
        expect(consecutiveRun, 0);
      },
    );
  });

  group('Audit 4: Transfer Integrity & Invariant Net Worth', () {
    test(
      'Cash = 10,000, Bank = 20,000; Transfer Cash -> Bank = 5,000 => Cash = 5,000, Bank = 25,000, Net Worth = 30,000',
      () async {
        // 1. Setup accounts
        final cashAcc = AccountEntity(
          id: 'acc_audit_cash',
          userId: AppConstants.defaultUserId,
          name: 'Physical Cash',
          type: AccountType.cash,
          currency: 'INR',
          initialBalance: 10000, // 10,000 minor units
          colorValue: 0xFF10B981,
          iconCodePoint: 0xe040,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        final bankAcc = AccountEntity(
          id: 'acc_audit_bank',
          userId: AppConstants.defaultUserId,
          name: 'HDFC Bank',
          type: AccountType.bank,
          currency: 'INR',
          initialBalance: 20000, // 20,000 minor units
          colorValue: 0xFF3B82F6,
          iconCodePoint: 0xe040,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await accountRepo.createAccount(cashAcc);
        await accountRepo.createAccount(bankAcc);

        expect(await accountRepo.getAccountBalance('acc_audit_cash'), 10000);
        expect(await accountRepo.getAccountBalance('acc_audit_bank'), 20000);
        final initialNetWorth = await accountRepo.getTotalNetWorth();

        // 2. Perform Transfer of 5,000 minor units
        await accountRepo.transferFunds(
          fromAccountId: 'acc_audit_cash',
          toAccountId: 'acc_audit_bank',
          amountMinor: 5000,
          note: 'Deposit to Bank',
        );

        // 3. Verify Balances and Invariance
        expect(await accountRepo.getAccountBalance('acc_audit_cash'), 5000);
        expect(await accountRepo.getAccountBalance('acc_audit_bank'), 25000);
        expect(await accountRepo.getTotalNetWorth(), initialNetWorth);

        // 4. Verify Income and Expense aggregations remain completely 0
        final nowUtc = DateTime.now().toUtc();
        final income = await transactionRepo.getTotalIncome(
          nowUtc.subtract(const Duration(days: 1)),
          nowUtc.add(const Duration(days: 1)),
        );
        final expense = await transactionRepo.getTotalExpense(
          nowUtc.subtract(const Duration(days: 1)),
          nowUtc.add(const Duration(days: 1)),
        );
        expect(income, 0);
        expect(expense, 0);

        // 5. Test invalid transfer rollback (negative amount & same account)
        expect(
          () => accountRepo.transferFunds(
            fromAccountId: 'acc_audit_cash',
            toAccountId: 'acc_audit_cash',
            amountMinor: 1000,
          ),
          throwsA(isA<ValidationException>()),
        );

        expect(
          () => accountRepo.transferFunds(
            fromAccountId: 'acc_audit_cash',
            toAccountId: 'acc_audit_bank',
            amountMinor: -500,
          ),
          throwsA(isA<ValidationException>()),
        );

        // Balances must remain strictly unchanged after failed transfers
        expect(await accountRepo.getAccountBalance('acc_audit_cash'), 5000);
        expect(await accountRepo.getAccountBalance('acc_audit_bank'), 25000);
      },
    );
  });

  group('Audit 5: Savings Goal Authoritative Source of Truth', () {
    test(
      'currentAmountMinor is authoritative state and progress calculations are consistent',
      () async {
        final goal = GoalEntity(
          id: 'goal_authoritative_test',
          userId: AppConstants.defaultUserId,
          name: 'New Laptop Fund',
          targetAmount: 10000000, // 100,000 INR
          currentAmount: 2500000, // 25,000 INR initial
          targetDate: DateTime.utc(2027, 1, 1),
          iconCodePoint: 0xe3f7,
          colorValue: 0xFF3B82F6,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        await goalRepo.createGoal(goal);

        // Authoritative balance
        final fetched = await goalRepo.getGoalById('goal_authoritative_test');
        expect(fetched!.currentAmount, 2500000);
        expect(fetched.progressPercentage, 0.25);
        expect(fetched.remainingAmount, 7500000);

        // Add progress
        await goalRepo.addProgress('goal_authoritative_test', 2500000);
        final afterAdd = await goalRepo.getGoalById('goal_authoritative_test');
        expect(afterAdd!.currentAmount, 5000000);
        expect(afterAdd.progressPercentage, 0.50);
        expect(afterAdd.remainingAmount, 5000000);

        // Verify field timestamps updated for currentAmountMinor
        expect(
          afterAdd.fieldTimestamps.containsKey('currentAmountMinor'),
          isTrue,
        );
      },
    );
  });

  group('Audit 6 & 8: Category, Budget, and Settings Repositories', () {
    test('CategoryRepository system protection and CRUD', () async {
      final systemCat = await categoryRepo.getCategoryById('cat_food');
      expect(systemCat!.isSystem, isTrue);

      expect(
        () => categoryRepo.softDeleteCategory('cat_food'),
        throwsA(isA<UnsupportedError>()),
      );

      final customCat = CategoryEntity(
        id: 'cat_custom_audit',
        userId: AppConstants.defaultUserId,
        name: 'Custom Category',
        iconCodePoint: 0xe040,
        colorValue: 0xFF10B981,
        type: TransactionType.income,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await categoryRepo.createCategory(customCat);
      await categoryRepo.updateCategory(
        customCat.copyWith(name: 'Renamed Custom Category'),
      );
      final updated = await categoryRepo.getCategoryById('cat_custom_audit');
      expect(updated!.name, 'Renamed Custom Category');

      await categoryRepo.softDeleteCategory('cat_custom_audit');
      expect(await categoryRepo.getCategoryById('cat_custom_audit'), isNull);
    });

    test(
      'BudgetRepository monthly and category budget spent tracking',
      () async {
        const monthKey = '2026-09';
        await budgetRepo.setMonthlyBudget(
          BudgetEntity(
            id: 'b_2026_09',
            userId: AppConstants.defaultUserId,
            monthYear: monthKey,
            amount: 5000000,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        await budgetRepo.setCategoryBudget(
          CategoryBudgetEntity(
            id: 'cb_food_2026_09',
            userId: AppConstants.defaultUserId,
            budgetId: 'b_2026_09',
            categoryId: 'cat_food',
            amount: 1500000,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        await transactionRepo.createTransaction(
          TransactionEntity(
            id: IdGenerator.uuid(),
            userId: AppConstants.defaultUserId,
            amount: 400000,
            type: TransactionType.expense,
            categoryId: 'cat_food',
            accountId: 'acc_bank_default',
            note: 'Restaurant',
            date: DateTime.utc(2026, 9, 12),
            createdAt: DateTime.utc(2026, 9, 12),
            updatedAt: DateTime.utc(2026, 9, 12),
          ),
        );

        expect(await budgetRepo.getSpentAmountForMonth(monthKey), 400000);
        expect(
          await budgetRepo.getSpentAmountForCategory('cat_food', monthKey),
          400000,
        );
      },
    );

    test('SettingsRepository key-value management', () async {
      await settingsRepo.setSetting('app_theme', 'dark');
      expect(await settingsRepo.getSetting('app_theme'), 'dark');
      final all = await settingsRepo.getAllSettings();
      expect(all['app_theme'], 'dark');
      await settingsRepo.clearAllSettings();
      expect(await settingsRepo.getAllSettings(), isEmpty);
    });
  });

  group('Audit 7: Multi-User Data Isolation Across All Repositories', () {
    test(
      'Strict user isolation across queries, streams, aggregations, and sync queue',
      () async {
        const userA = 'user_isolated_a';
        const userB = 'user_isolated_b';

        final txRepoA = TransactionRepository(db, () => userA);
        final txRepoB = TransactionRepository(db, () => userB);
        final accRepoA = AccountRepository(db, () => userA);
        final accRepoB = AccountRepository(db, () => userB);
        final catRepoA = CategoryRepository(db, () => userA);
        final catRepoB = CategoryRepository(db, () => userB);
        final goalRepoA = GoalRepository(db, () => userA);
        final goalRepoB = GoalRepository(db, () => userB);
        final syncRepoA = SyncRepository(db, () => userA);
        final syncRepoB = SyncRepository(db, () => userB);

        // Create data for User A
        await accRepoA.createAccount(
          AccountEntity(
            id: 'acc_user_a',
            userId: userA,
            name: 'Account A',
            type: AccountType.bank,
            currency: 'INR',
            initialBalance: 50000,
            colorValue: 0xFF10B981,
            iconCodePoint: 0xe040,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        await txRepoA.createTransaction(
          TransactionEntity(
            id: 'tx_user_a',
            userId: userA,
            amount: 10000,
            type: TransactionType.expense,
            categoryId: 'cat_food',
            accountId: 'acc_user_a',
            note: 'A Expense',
            date: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        await catRepoA.createCategory(
          CategoryEntity(
            id: 'cat_user_a',
            userId: userA,
            name: 'A Custom Category',
            iconCodePoint: 0xe040,
            colorValue: 0xFF10B981,
            type: TransactionType.expense,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        await goalRepoA.createGoal(
          GoalEntity(
            id: 'goal_user_a',
            userId: userA,
            name: 'Goal A',
            targetAmount: 500000,
            currentAmount: 100000,
            targetDate: DateTime.utc(2027, 1, 1),
            iconCodePoint: 0xe040,
            colorValue: 0xFF3B82F6,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        // User B reads: must see empty lists and 0 counts
        expect(await accRepoB.getAllAccounts(), isEmpty);
        expect(await txRepoB.getTransactionsCursor(), isEmpty);
        expect(await catRepoB.getAllCategories(), isEmpty);
        expect(await goalRepoB.getAllGoals(), isEmpty);
        expect(await syncRepoB.getPendingCount(), 0);

        // User A reads: sees their data
        expect((await accRepoA.getAllAccounts()).length, 1);
        expect((await txRepoA.getTransactionsCursor()).length, 1);
        expect((await catRepoA.getAllCategories()).length, 1);
        expect((await goalRepoA.getAllGoals()).length, 1);
        expect(
          await syncRepoA.getPendingCount(),
          4,
        ); // 1 acc + 1 tx + 1 cat + 1 goal

        // User B cannot access User A\'s entity by ID
        expect(await txRepoB.getTransactionById('tx_user_a'), isNull);
        expect(await accRepoB.getAccountById('acc_user_a'), isNull);
        expect(await catRepoB.getCategoryById('cat_user_a'), isNull);
        expect(await goalRepoB.getGoalById('goal_user_a'), isNull);

        // User B cannot update User A\'s transaction
        expect(
          () => txRepoB.updateTransaction(
            TransactionEntity(
              id: 'tx_user_a',
              userId: userB,
              amount: 20000,
              type: TransactionType.expense,
              categoryId: 'cat_food',
              accountId: 'acc_user_a',
              note: 'Malicious Update',
              date: DateTime.now().toUtc(),
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
          ),
          throwsA(isA<NotFoundException>()),
        );
      },
    );
  });
}
