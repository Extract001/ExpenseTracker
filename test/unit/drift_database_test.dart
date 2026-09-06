import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/constants/app_constants.dart';
import 'package:expense_tracker/core/database/encrypted_database_connection.dart';
import 'package:expense_tracker/data/database/app_database.dart';

void main() {
  group('Phase 2 ? Drift Encrypted Database & DAO Comprehensive Tests', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(EncryptedDatabaseConnection.createInMemoryConnection());
    });

    tearDown(() async {
      await db.close();
    });

    test('1. Database Initialization & Seed Verification', () async {
      // 1. Verify default user is seeded
      final users = await db.select(db.usersTable).get();
      expect(users.length, equals(1));
      expect(users.first.id, equals(AppConstants.defaultUserId));

      // 2. Verify default categories are seeded (10 expenses + 6 incomes = 16)
      final categories = await db.categoryDao.getAllCategories(
        userId: AppConstants.defaultUserId,
      );
      expect(categories.length, equals(16));
      final expenseCats = await db.categoryDao.getAllCategories(
        userId: AppConstants.defaultUserId,
        type: 'expense',
      );
      expect(expenseCats.length, equals(10));
      final incomeCats = await db.categoryDao.getAllCategories(
        userId: AppConstants.defaultUserId,
        type: 'income',
      );
      expect(incomeCats.length, equals(6));

      // 3. Verify default accounts are seeded (Cash and Bank)
      final accounts = await db.accountDao.getAllAccounts(
        AppConstants.defaultUserId,
      );
      expect(accounts.length, equals(2));
      expect(accounts.any((a) => a.accountType == 'cash'), isTrue);
      expect(accounts.any((a) => a.accountType == 'bank'), isTrue);
    });

    test('2. Transaction CRUD & Soft-Deletion Lifecycle', () async {
      final nowUtc = DateTime.now().toUtc();
      const txId = 'tx_test_001';

      // Insert transaction
      await db.transactionDao.insertTransaction(
        TransactionsTableCompanion.insert(
          id: txId,
          userId: AppConstants.defaultUserId,
          amountMinor: 25000, // ?250.00
          transactionType: 'expense',
          categoryId: 'cat_food',
          accountId: 'acc_cash_default',
          note: const Value('Lunch at cafe'),
          transactionDateUtc: nowUtc,
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
          syncStatus: const Value('pendingCreate'),
        ),
      );

      // Read transaction
      var tx = await db.transactionDao.getTransactionById(txId);
      expect(tx, isNotNull);
      expect(tx!.amountMinor, equals(25000));
      expect(tx.note, equals('Lunch at cafe'));
      expect(tx.syncStatus, equals('pendingCreate'));
      expect(tx.deletedAtUtc, isNull);

      // Update transaction
      await db.transactionDao.updateTransaction(
        tx
            .toCompanion(false)
            .copyWith(
              amountMinor: const Value(30000), // Updated to ?300.00
              note: const Value('Lunch with dessert'),
              updatedAtUtc: Value(nowUtc.add(const Duration(minutes: 5))),
              syncStatus: const Value('pendingUpdate'),
            ),
      );

      tx = await db.transactionDao.getTransactionById(txId);
      expect(tx!.amountMinor, equals(30000));
      expect(tx.note, equals('Lunch with dessert'));
      expect(tx.syncStatus, equals('pendingUpdate'));

      // Soft delete transaction
      final deleteTimeUtc = nowUtc.add(const Duration(minutes: 10));
      await db.transactionDao.softDeleteTransaction(
        id: txId,
        deletedAtUtc: deleteTimeUtc,
      );

      // Verify transaction is excluded from standard active queries
      final activeList = await db.transactionDao.getTransactionsCursor(
        userId: AppConstants.defaultUserId,
      );
      expect(activeList.any((t) => t.id == txId), isFalse);

      // Verify tombstone is preserved in DB for sync queue
      final tombstone = await db.transactionDao.getTransactionById(txId);
      expect(tombstone, isNotNull);
      expect(
        tombstone!.deletedAtUtc!.millisecondsSinceEpoch ~/ 1000,
        equals(deleteTimeUtc.millisecondsSinceEpoch ~/ 1000),
      );
      expect(tombstone.syncStatus, equals('pendingDelete'));
    });

    test('3. Account Balances & Transfers Net Worth Isolation', () async {
      final nowUtc = DateTime.now().toUtc();

      // Initial balances are 0
      var netWorth = await db.accountDao.getTotalNetWorth(
        AppConstants.defaultUserId,
      );
      expect(netWorth, equals(0));

      // 1. Add Salary Income to Bank: ?50,000 (5000000 minor units)
      await db.transactionDao.insertTransaction(
        TransactionsTableCompanion.insert(
          id: 'tx_salary_1',
          userId: AppConstants.defaultUserId,
          amountMinor: 5000000,
          transactionType: 'income',
          categoryId: 'cat_salary',
          accountId: 'acc_bank_default',
          note: const Value('Monthly Salary'),
          transactionDateUtc: nowUtc,
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
        ),
      );

      // 2. Transfer from Bank -> Cash: ?10,000 (1000000 minor units)
      await db.transactionDao.insertTransaction(
        TransactionsTableCompanion.insert(
          id: 'tx_transfer_1',
          userId: AppConstants.defaultUserId,
          amountMinor: 1000000,
          transactionType: 'transfer',
          categoryId: 'cat_other_income',
          accountId: 'acc_bank_default',
          toAccountId: const Value('acc_cash_default'),
          note: const Value('ATM Cash Withdrawal'),
          transactionDateUtc: nowUtc,
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
        ),
      );

      // 3. Cash Expense: ?2,500 (250000 minor units)
      await db.transactionDao.insertTransaction(
        TransactionsTableCompanion.insert(
          id: 'tx_food_1',
          userId: AppConstants.defaultUserId,
          amountMinor: 250000,
          transactionType: 'expense',
          categoryId: 'cat_food',
          accountId: 'acc_cash_default',
          note: const Value('Groceries'),
          transactionDateUtc: nowUtc,
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
        ),
      );

      // Check balances
      final bankBalance = await db.accountDao.getAccountBalance(
        userId: AppConstants.defaultUserId,
        accountId: 'acc_bank_default',
      );
      final cashBalance = await db.accountDao.getAccountBalance(
        userId: AppConstants.defaultUserId,
        accountId: 'acc_cash_default',
      );
      netWorth = await db.accountDao.getTotalNetWorth(
        AppConstants.defaultUserId,
      );

      expect(bankBalance, equals(4000000)); // ?40,000 (50,000 - 10,000)
      expect(cashBalance, equals(750000)); // ?7,500 (10,000 - 2,500)
      expect(netWorth, equals(4750000)); // ?47,500 total

      // Check total income and total expense exclusions
      final startUtc = nowUtc.subtract(const Duration(days: 1));
      final endUtc = nowUtc.add(const Duration(days: 1));
      final totalIncome = await db.transactionDao.getTotalIncome(
        userId: AppConstants.defaultUserId,
        startDateUtc: startUtc,
        endDateUtc: endUtc,
      );
      final totalExpense = await db.transactionDao.getTotalExpense(
        userId: AppConstants.defaultUserId,
        startDateUtc: startUtc,
        endDateUtc: endUtc,
      );

      expect(totalIncome, equals(5000000)); // ?50,000 (transfers not counted)
      expect(totalExpense, equals(250000)); // ?2,500 (transfers not counted)
    });

    test('4. Multi-User Data Isolation Verification', () async {
      const userA = 'user_alpha_123';
      const userB = 'user_beta_456';
      final nowUtc = DateTime.now().toUtc();

      // Seed Users
      await db
          .into(db.usersTable)
          .insert(
            UsersTableCompanion.insert(
              id: userA,
              createdAtUtc: nowUtc,
              lastActiveAtUtc: nowUtc,
            ),
          );
      await db
          .into(db.usersTable)
          .insert(
            UsersTableCompanion.insert(
              id: userB,
              createdAtUtc: nowUtc,
              lastActiveAtUtc: nowUtc,
            ),
          );

      // User A creates transaction
      await db.transactionDao.insertTransaction(
        TransactionsTableCompanion.insert(
          id: 'tx_userA_secret',
          userId: userA,
          amountMinor: 99900,
          transactionType: 'expense',
          categoryId: 'cat_food',
          accountId: 'acc_cash_default',
          note: const Value('User A Secret Purchase'),
          transactionDateUtc: nowUtc,
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
        ),
      );

      // User B creates transaction
      await db.transactionDao.insertTransaction(
        TransactionsTableCompanion.insert(
          id: 'tx_userB_secret',
          userId: userB,
          amountMinor: 44400,
          transactionType: 'expense',
          categoryId: 'cat_travel',
          accountId: 'acc_cash_default',
          note: const Value('User B Secret Trip'),
          transactionDateUtc: nowUtc,
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
        ),
      );

      // Query User A transactions
      final userARecords = await db.transactionDao.getTransactionsCursor(
        userId: userA,
      );
      expect(userARecords.length, equals(1));
      expect(userARecords.first.id, equals('tx_userA_secret'));
      expect(userARecords.any((t) => t.userId == userB), isFalse);

      // Query User B transactions
      final userBRecords = await db.transactionDao.getTransactionsCursor(
        userId: userB,
      );
      expect(userBRecords.length, equals(1));
      expect(userBRecords.first.id, equals('tx_userB_secret'));
      expect(userBRecords.any((t) => t.userId == userA), isFalse);
    });

    test(
      '5. Sync Queue Enqueue, Retry, and Persistence Verification',
      () async {
        final nowUtc = DateTime.now().toUtc();
        const opId = 'op_sync_001';

        // 1. Enqueue operation
        await db.syncQueueDao.enqueueOperation(
          SyncOperationsTableCompanion.insert(
            id: opId,
            userId: AppConstants.defaultUserId,
            entityType: 'transaction',
            entityId: 'tx_101',
            operationType: 'create',
            payloadJson: '{"amountMinor": 12550, "note": "Lunch"}',
            createdAtUtc: nowUtc,
          ),
        );

        var pendingCount = await db.syncQueueDao.getPendingCount(
          AppConstants.defaultUserId,
        );
        expect(pendingCount, equals(1));

        var ops = await db.syncQueueDao.getPendingOperations(
          userId: AppConstants.defaultUserId,
        );
        expect(ops.length, equals(1));
        expect(ops.first.retryCount, equals(0));
        expect(ops.first.errorMessage, isNull);

        // 2. Simulate failed sync attempt
        final attemptTime = nowUtc.add(const Duration(seconds: 30));
        await db.syncQueueDao.recordOperationFailure(
          id: opId,
          errorMessage: 'Network timeout (504 Gateway Timeout)',
          attemptTimeUtc: attemptTime,
        );

        ops = await db.syncQueueDao.getPendingOperations(
          userId: AppConstants.defaultUserId,
        );
        expect(ops.first.retryCount, equals(1));
        expect(
          ops.first.lastAttemptAtUtc!.millisecondsSinceEpoch ~/ 1000,
          equals(attemptTime.millisecondsSinceEpoch ~/ 1000),
        );
        expect(ops.first.errorMessage, contains('504'));

        // 3. Mark operation complete / delete from queue
        await db.syncQueueDao.deleteOperation(opId);
        pendingCount = await db.syncQueueDao.getPendingCount(
          AppConstants.defaultUserId,
        );
        expect(pendingCount, equals(0));
      },
    );

    test(
      '6. Foreign Key Cascading Verification (Budgets & Category Budgets)',
      () async {
        final nowUtc = DateTime.now().toUtc();
        const budgetId = 'budget_2026_09';

        // Insert monthly budget
        await db.budgetDao.upsertMonthlyBudget(
          BudgetsTableCompanion.insert(
            id: budgetId,
            userId: AppConstants.defaultUserId,
            monthYear: '2026-09',
            amountMinor: 5000000, // ?50,000
            createdAtUtc: nowUtc,
            updatedAtUtc: nowUtc,
          ),
        );

        // Insert category budget linked to budget
        await db.budgetDao.upsertCategoryBudget(
          CategoryBudgetsTableCompanion.insert(
            id: 'cat_budget_food_09',
            userId: AppConstants.defaultUserId,
            budgetId: budgetId,
            categoryId: 'cat_food',
            amountMinor: 1500000, // ?15,000 for food
            createdAtUtc: nowUtc,
            updatedAtUtc: nowUtc,
          ),
        );

        var catBudgets = await db.budgetDao.getCategoryBudgets(
          userId: AppConstants.defaultUserId,
          budgetId: budgetId,
        );
        expect(catBudgets.length, equals(1));

        // Delete parent budget
        await (db.delete(
          db.budgetsTable,
        )..where((b) => b.id.equals(budgetId))).go();

        // Category budget should cascade delete
        catBudgets = await db.budgetDao.getCategoryBudgets(
          userId: AppConstants.defaultUserId,
          budgetId: budgetId,
        );
        expect(catBudgets, isEmpty);
      },
    );
  });
}
