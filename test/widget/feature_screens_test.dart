import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:expense_tracker/domain/entities/account_entity.dart';
import 'package:expense_tracker/domain/entities/budget_entity.dart';
import 'package:expense_tracker/domain/entities/category_entity.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:expense_tracker/domain/entities/goal_entity.dart';
import 'package:expense_tracker/domain/entities/recurring_transaction_entity.dart';
import 'package:expense_tracker/domain/entities/sync_operation_entity.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/domain/repositories/i_account_repository.dart';
import 'package:expense_tracker/domain/repositories/i_budget_repository.dart';
import 'package:expense_tracker/domain/repositories/i_category_repository.dart';
import 'package:expense_tracker/domain/repositories/i_goal_repository.dart';
import 'package:expense_tracker/domain/repositories/i_recurring_transaction_repository.dart';
import 'package:expense_tracker/domain/repositories/i_settings_repository.dart';
import 'package:expense_tracker/domain/repositories/i_sync_repository.dart';
import 'package:expense_tracker/domain/repositories/i_transaction_repository.dart';

import 'package:expense_tracker/presentation/navigation/app_router.dart';
import 'package:expense_tracker/presentation/providers/app_providers.dart';
import 'package:expense_tracker/presentation/screens/accounts/account_details_screen.dart';
import 'package:expense_tracker/presentation/screens/accounts/accounts_screen.dart';
import 'package:expense_tracker/presentation/screens/analytics/analytics_tab_screen.dart';
import 'package:expense_tracker/presentation/screens/budgets/budgets_tab_screen.dart';
import 'package:expense_tracker/presentation/screens/categories/categories_screen.dart';
import 'package:expense_tracker/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:expense_tracker/presentation/screens/goals/goals_screen.dart';
import 'package:expense_tracker/presentation/screens/more/more_tab_screen.dart';
import 'package:expense_tracker/presentation/screens/recurring/recurring_transactions_screen.dart';
import 'package:expense_tracker/presentation/screens/transactions/transactions_tab_screen.dart';
import 'package:expense_tracker/presentation/theme/app_theme.dart';

// ============================================================================
// COMPREHENSIVE FAKE REPOSITORIES FOR FEATURE SCREEN TESTS
// ============================================================================

class MockTransactionRepo implements ITransactionRepository {
  final List<TransactionEntity> items = [];

  @override
  Stream<List<TransactionEntity>> watchRecentTransactions({int limit = 20}) =>
      Stream.value(items.take(limit).toList());

  @override
  Future<List<TransactionEntity>> getTransactionsCursor({
    DateTime? cursorDate,
    String? cursorId,
    int limit = 50,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? minAmount,
    int? maxAmount,
    String? searchQuery,
  }) async {
    return items
        .where((tx) {
          if (type != null && tx.type != type) return false;
          if (categoryId != null && tx.categoryId != categoryId) return false;
          if (accountId != null && tx.accountId != accountId) return false;
          if (startDate != null && tx.date.isBefore(startDate)) return false;
          if (endDate != null && tx.date.isAfter(endDate)) return false;
          if (minAmount != null && tx.amount < minAmount) return false;
          if (maxAmount != null && tx.amount > maxAmount) return false;
          if (searchQuery != null &&
              searchQuery.isNotEmpty &&
              !tx.note.toLowerCase().contains(searchQuery.toLowerCase())) {
            return false;
          }
          return true;
        })
        .take(limit)
        .toList();
  }

  @override
  Future<TransactionEntity?> getTransactionById(String id) async {
    try {
      return items.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createTransaction(TransactionEntity transaction) async {
    items.add(transaction);
  }

  @override
  Future<void> updateTransaction(TransactionEntity transaction) async {
    final idx = items.indexWhere((t) => t.id == transaction.id);
    if (idx != -1) items[idx] = transaction;
  }

  @override
  Future<void> softDeleteTransaction(String id) async {
    items.removeWhere((t) => t.id == id);
  }

  @override
  Future<int> getTotalIncome(DateTime start, DateTime end) async {
    return items
        .where((t) => t.type == TransactionType.income)
        .fold<int>(0, (sum, t) => sum + t.amount);
  }

  @override
  Future<int> getTotalExpense(DateTime start, DateTime end) async {
    return items
        .where((t) => t.type == TransactionType.expense)
        .fold<int>(0, (sum, t) => sum + t.amount);
  }
}

class MockAccountRepo implements IAccountRepository {
  final List<AccountEntity> accounts = [];

  @override
  Stream<List<AccountEntity>> watchAllAccounts() => Stream.value(accounts);

  @override
  Future<List<AccountEntity>> getAllAccounts() async => accounts;

  @override
  Future<AccountEntity?> getAccountById(String id) async {
    try {
      return accounts.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createAccount(AccountEntity account) async {
    accounts.add(account);
  }

  @override
  Future<void> updateAccount(AccountEntity account) async {
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx != -1) accounts[idx] = account;
  }

  @override
  Future<void> softDeleteAccount(String id) async {
    accounts.removeWhere((a) => a.id == id);
  }

  @override
  Future<int> getAccountBalance(String id) async {
    final acc = await getAccountById(id);
    return acc?.initialBalance ?? 0;
  }

  @override
  Future<int> getTotalNetWorth() async {
    return accounts.fold<int>(0, (sum, a) => sum + a.initialBalance);
  }

  @override
  Future<void> transferFunds({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    DateTime? date,
  }) async {
    final fromIdx = accounts.indexWhere((a) => a.id == fromAccountId);
    final toIdx = accounts.indexWhere((a) => a.id == toAccountId);
    if (fromIdx != -1 && toIdx != -1) {
      accounts[fromIdx] = accounts[fromIdx].copyWith(
        initialBalance: accounts[fromIdx].initialBalance - amountMinor,
      );
      accounts[toIdx] = accounts[toIdx].copyWith(
        initialBalance: accounts[toIdx].initialBalance + amountMinor,
      );
    }
  }
}

class MockCategoryRepo implements ICategoryRepository {
  final List<CategoryEntity> categories = [];

  @override
  Stream<List<CategoryEntity>> watchCategories({TransactionType? type}) =>
      Stream.value(
        type == null
            ? categories
            : categories.where((c) => c.type == type).toList(),
      );

  @override
  Future<List<CategoryEntity>> getAllCategories({TransactionType? type}) async {
    return type == null
        ? categories
        : categories.where((c) => c.type == type).toList();
  }

  @override
  Future<CategoryEntity?> getCategoryById(String id) async {
    try {
      return categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createCategory(CategoryEntity category) async {
    categories.add(category);
  }

  @override
  Future<void> updateCategory(CategoryEntity category) async {
    final idx = categories.indexWhere((c) => c.id == category.id);
    if (idx != -1) categories[idx] = category;
  }

  @override
  Future<void> archiveCategory(String id) async {
    final idx = categories.indexWhere((c) => c.id == id);
    if (idx != -1) {
      categories[idx] = categories[idx].copyWith(isArchived: true);
    }
  }

  @override
  Future<void> softDeleteCategory(String id) async {
    categories.removeWhere((c) => c.id == id);
  }
}

class MockBudgetRepo implements IBudgetRepository {
  BudgetEntity? monthlyBudget;
  final List<CategoryBudgetEntity> categoryBudgets = [];
  int spentAmount = 0;

  @override
  Stream<BudgetEntity?> watchMonthlyBudget(String monthYear) =>
      Stream.value(monthlyBudget);

  @override
  Stream<List<CategoryBudgetEntity>> watchCategoryBudgets(String budgetId) =>
      Stream.value(categoryBudgets);

  @override
  Future<BudgetEntity?> getMonthlyBudget(String monthYear) async =>
      monthlyBudget;

  @override
  Future<void> setMonthlyBudget(BudgetEntity budget) async {
    monthlyBudget = budget;
  }

  @override
  Future<void> setCategoryBudget(CategoryBudgetEntity categoryBudget) async {
    final idx = categoryBudgets.indexWhere(
      (cb) => cb.categoryId == categoryBudget.categoryId,
    );
    if (idx != -1) {
      categoryBudgets[idx] = categoryBudget;
    } else {
      categoryBudgets.add(categoryBudget);
    }
  }

  @override
  Future<int> getSpentAmountForMonth(String monthYear) async => spentAmount;

  @override
  Future<int> getSpentAmountForCategory(
    String categoryId,
    String monthYear,
  ) async => spentAmount;
}

class MockGoalRepo implements IGoalRepository {
  final List<GoalEntity> goals = [];

  @override
  Stream<List<GoalEntity>> watchAllGoals() => Stream.value(goals);
  @override
  Future<List<GoalEntity>> getAllGoals() async => goals;
  @override
  Future<GoalEntity?> getGoalById(String id) async {
    try {
      return goals.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createGoal(GoalEntity goal) async => goals.add(goal);
  @override
  Future<void> updateGoal(GoalEntity goal) async {
    final idx = goals.indexWhere((g) => g.id == goal.id);
    if (idx != -1) goals[idx] = goal;
  }

  @override
  Future<void> addProgress(String id, int amountMinor) async {
    final idx = goals.indexWhere((g) => g.id == id);
    if (idx != -1) {
      goals[idx] = goals[idx].copyWith(
        currentAmount: goals[idx].currentAmount + amountMinor,
      );
    }
  }

  @override
  Future<void> softDeleteGoal(String id) async =>
      goals.removeWhere((g) => g.id == id);
}

class MockRecurringRepo implements IRecurringTransactionRepository {
  final List<RecurringTransactionEntity> rules = [];

  @override
  Stream<List<RecurringTransactionEntity>> watchAllRecurring() =>
      Stream.value(rules);
  @override
  Future<List<RecurringTransactionEntity>> getDueRecurringTransactions(
    DateTime nowUtc,
  ) async => rules;
  @override
  Future<void> createRecurring(RecurringTransactionEntity entity) async =>
      rules.add(entity);
  @override
  Future<void> updateRecurring(RecurringTransactionEntity entity) async {
    final idx = rules.indexWhere((r) => r.id == entity.id);
    if (idx != -1) rules[idx] = entity;
  }

  @override
  Future<void> toggleActive(String id, bool isActive) async {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx != -1) {
      rules[idx] = rules[idx].copyWith(isActive: isActive);
    }
  }

  @override
  Future<void> softDeleteRecurring(String id) async =>
      rules.removeWhere((r) => r.id == id);
  @override
  Future<int> processDueRecurringRules(DateTime nowUtc) async => rules.length;
  @override
  Future<void> updateNextExecutionDate(
    String id,
    DateTime nextDate,
    DateTime lastExecutedDate,
  ) async {}
}

class MockSettingsRepo implements ISettingsRepository {
  final Map<String, String> settings = {};
  @override
  Future<String?> getSetting(String key) async => settings[key];
  @override
  Future<void> setSetting(String key, String value) async =>
      settings[key] = value;
  @override
  Future<Map<String, String>> getAllSettings() async => settings;
  @override
  Future<void> clearAllSettings() async => settings.clear();
}

class MockSyncRepo implements ISyncRepository {
  @override
  Stream<int> watchPendingCount() => Stream.value(0);
  @override
  Stream<List<SyncOperationEntity>> watchPendingOperations({int limit = 50}) =>
      Stream.value([]);
  @override
  Future<int> getPendingCount() async => 0;
  @override
  Future<List<SyncOperationEntity>> getPendingOperations({
    int limit = 50,
  }) async => [];
  @override
  Future<void> enqueueOperation(SyncOperationEntity operation) async {}
  @override
  Future<void> markOperationCompleted(String id) async {}
  @override
  Future<void> markOperationFailed(String id, String errorMessage) async {}
}

Widget buildTestApp({
  required Widget child,
  MockTransactionRepo? txRepo,
  MockAccountRepo? accRepo,
  MockCategoryRepo? catRepo,
  MockBudgetRepo? budgetRepo,
  MockGoalRepo? goalRepo,
  MockRecurringRepo? recurringRepo,
  MockSettingsRepo? settingsRepo,
}) {
  return MultiProvider(
    providers: AppProviders.buildProviders(
      transactionRepository: txRepo ?? MockTransactionRepo(),
      accountRepository: accRepo ?? MockAccountRepo(),
      categoryRepository: catRepo ?? MockCategoryRepo(),
      budgetRepository: budgetRepo ?? MockBudgetRepo(),
      goalRepository: goalRepo ?? MockGoalRepo(),
      recurringRepository: recurringRepo ?? MockRecurringRepo(),
      settingsRepository: settingsRepo ?? MockSettingsRepo(),
      syncRepository: MockSyncRepo(),
    ),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: child,
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
}

void main() {
  group('Phase 5 Step 2 Feature Screen Widget Tests', () {
    // ------------------------------------------------------------------------
    // GROUP 1: ACCOUNTS
    // ------------------------------------------------------------------------
    testWidgets(
      '1. Accounts: List, Balances, Add Account, and Delete Confirmation',
      (tester) async {
        final accRepo = MockAccountRepo();
        accRepo.accounts.add(
          AccountEntity(
            id: 'acc_1',
            userId: 'user_1',
            name: 'Main Bank',
            type: AccountType.bank,
            initialBalance: 750000,
            currency: 'INR',
            colorValue: 0xFF1A56DB,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        await tester.pumpWidget(
          buildTestApp(accRepo: accRepo, child: const AccountsScreen()),
        );
        await tester.pumpAndSettle();

        // Check account rendered
        expect(find.text('Main Bank'), findsOneWidget);
        expect(find.text('Bank Account'), findsOneWidget);
        expect(find.text('₹7,500.00'), findsWidgets);

        // Open Add Account modal
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(find.text('Add Account'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Cash Pocket');
        await tester.ensureVisible(find.text('Create Account'));
        await tester.tap(find.text('Create Account'));
        await tester.pumpAndSettle();

        // Verify created in repo
        expect(accRepo.accounts.length, 2);
      },
    );

    testWidgets('2. Account Details: Renders metadata and handles delete', (
      tester,
    ) async {
      final accRepo = MockAccountRepo();
      final acc = AccountEntity(
        id: 'acc_test',
        userId: 'user_1',
        name: 'Savings Vault',
        type: AccountType.savings,
        initialBalance: 500000,
        currency: 'INR',
        colorValue: 0xFF16A34A,
        iconCodePoint: 0xE000,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      accRepo.accounts.add(acc);

      await tester.pumpWidget(
        buildTestApp(
          accRepo: accRepo,
          child: AccountDetailsScreen(accountId: acc.id),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Savings Vault'), findsWidgets);
      expect(find.text('Savings Account'), findsWidgets);
      expect(find.text('Initial Balance'), findsOneWidget);

      // Tap delete
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(accRepo.accounts.isEmpty, isTrue);
    });

    // ------------------------------------------------------------------------
    // GROUP 2: CATEGORIES
    // ------------------------------------------------------------------------
    testWidgets(
      '3. Categories: Tab Switch, System Category Protection, Add Category',
      (tester) async {
        final catRepo = MockCategoryRepo();
        catRepo.categories.addAll([
          CategoryEntity(
            id: 'cat_sys',
            userId: 'user_1',
            name: 'Food & Dining',
            iconCodePoint: 0xE001,
            colorValue: 0xFFDC2626,
            type: TransactionType.expense,
            isSystem: true,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
          CategoryEntity(
            id: 'cat_inc',
            userId: 'user_1',
            name: 'Salary',
            iconCodePoint: 0xE002,
            colorValue: 0xFF16A34A,
            type: TransactionType.income,
            isSystem: false,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ]);

        await tester.pumpWidget(
          buildTestApp(catRepo: catRepo, child: const CategoriesScreen()),
        );
        await tester.pumpAndSettle();

        // Verify system category badge
        expect(find.text('Food & Dining'), findsOneWidget);
        expect(find.text('System'), findsOneWidget);

        // Switch to Income tab
        await tester.tap(find.textContaining('Income'));
        await tester.pumpAndSettle();

        expect(find.text('Salary'), findsOneWidget);
      },
    );

    // ------------------------------------------------------------------------
    // GROUP 3: TRANSACTIONS & FILTERS
    // ------------------------------------------------------------------------
    testWidgets('4. Transactions: Filter modal, transfer details, search', (
      tester,
    ) async {
      final txRepo = MockTransactionRepo();
      final accRepo = MockAccountRepo();
      final catRepo = MockCategoryRepo();

      final acc1 = AccountEntity(
        id: 'acc_from',
        userId: 'u1',
        name: 'Checking',
        type: AccountType.bank,
        currency: 'INR',
        colorValue: 0xFF1A56DB,
        iconCodePoint: 0xE000,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final acc2 = AccountEntity(
        id: 'acc_to',
        userId: 'u1',
        name: 'Savings',
        type: AccountType.savings,
        currency: 'INR',
        colorValue: 0xFF16A34A,
        iconCodePoint: 0xE000,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      accRepo.accounts.addAll([acc1, acc2]);

      final transferTx = TransactionEntity(
        id: 'tx_xfer',
        userId: 'u1',
        amount: 30000,
        type: TransactionType.transfer,
        categoryId: 'cat_none',
        accountId: acc1.id,
        toAccountId: acc2.id,
        note: 'Emergency Savings Transfer',
        date: DateTime.utc(2026, 9, 2),
        createdAt: DateTime.utc(2026, 9, 2),
        updatedAt: DateTime.utc(2026, 9, 2),
      );
      txRepo.items.add(transferTx);

      await tester.pumpWidget(
        buildTestApp(
          txRepo: txRepo,
          accRepo: accRepo,
          catRepo: catRepo,
          child: const TransactionsTabScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Emergency Savings Transfer'), findsOneWidget);
      expect(find.textContaining('Checking → Savings'), findsOneWidget);

      // Open detail
      await tester.tap(find.text('Emergency Savings Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('From Account'), findsOneWidget);
      expect(find.text('To Account'), findsOneWidget);
    });

    // ------------------------------------------------------------------------
    // GROUP 4: DASHBOARD
    // ------------------------------------------------------------------------
    testWidgets(
      '5. Dashboard: Renders live net worth, quick actions, and recent tx',
      (tester) async {
        final txRepo = MockTransactionRepo();
        final accRepo = MockAccountRepo();
        final catRepo = MockCategoryRepo();

        accRepo.accounts.add(
          AccountEntity(
            id: 'acc_1',
            userId: 'u1',
            name: 'Wallet',
            type: AccountType.cash,
            initialBalance: 25000,
            currency: 'INR',
            colorValue: 0xFF1A56DB,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            txRepo: txRepo,
            accRepo: accRepo,
            catRepo: catRepo,
            child: const DashboardScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Total Net Worth'), findsOneWidget);
        expect(find.text('₹250.00'), findsWidgets);
        expect(find.text('Expense'), findsWidgets);
        expect(find.text('Income'), findsWidgets);
        expect(find.text('Transfer'), findsWidgets);
      },
    );

    // ------------------------------------------------------------------------
    // GROUP 5: ANALYTICS
    // ------------------------------------------------------------------------
    testWidgets(
      '6. Analytics: Period chips, Net Cash Flow, and Category charts',
      (tester) async {
        final txRepo = MockTransactionRepo();
        final catRepo = MockCategoryRepo();

        final foodCat = CategoryEntity(
          id: 'cat_food',
          userId: 'u1',
          name: 'Dining Out',
          iconCodePoint: 0xE000,
          colorValue: 0xFFDC2626,
          type: TransactionType.expense,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        catRepo.categories.add(foodCat);

        txRepo.items.add(
          TransactionEntity(
            id: 'tx_food',
            userId: 'u1',
            amount: 8000,
            type: TransactionType.expense,
            categoryId: foodCat.id,
            accountId: 'acc_1',
            note: 'Pizza dinner',
            date: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

        await tester.pumpWidget(
          buildTestApp(
            txRepo: txRepo,
            catRepo: catRepo,
            child: const AnalyticsTabScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Net Cash Flow'), findsOneWidget);
        expect(find.text('This Month'), findsOneWidget);
        expect(find.text('Last Month'), findsOneWidget);
        expect(find.text('This Year'), findsOneWidget);
      },
    );

    // ------------------------------------------------------------------------
    // GROUP 6: BUDGETS
    // ------------------------------------------------------------------------
    testWidgets('7. Budgets: Monthly limit, Progress, Overspending state', (
      tester,
    ) async {
      final budgetRepo = MockBudgetRepo();
      budgetRepo.monthlyBudget = BudgetEntity(
        id: 'b_1',
        userId: 'u1',
        monthYear: '2026-09',
        amount: 200000, // 2,000 INR
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      budgetRepo.spentAmount = 250000; // 2,500 INR (Over budget)

      await tester.pumpWidget(
        buildTestApp(budgetRepo: budgetRepo, child: const BudgetsTabScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overall Monthly Budget'), findsOneWidget);
      expect(find.text('₹2,000.00'), findsWidgets);
      expect(find.text('Over Budget By'), findsOneWidget);
      expect(find.text('₹500.00'), findsWidgets);
    });

    // ------------------------------------------------------------------------
    // GROUP 7: SAVINGS GOALS
    // ------------------------------------------------------------------------
    testWidgets(
      '8. Goals: Target amount, add progress, and completion status',
      (tester) async {
        final goalRepo = MockGoalRepo();
        final g = GoalEntity(
          id: 'g_1',
          userId: 'u1',
          name: 'New Laptop',
          targetAmount: 10000000, // 100,000 INR
          currentAmount: 4000000, // 40,000 INR
          targetDate: DateTime.utc(2026, 12, 31),
          iconCodePoint: 0xE000,
          colorValue: 0xFF16A34A,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        goalRepo.goals.add(g);

        await tester.pumpWidget(
          buildTestApp(goalRepo: goalRepo, child: const GoalsScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.text('New Laptop'), findsOneWidget);
        expect(find.text('40%'), findsOneWidget);
        expect(find.text('Add Funds to Goal'), findsOneWidget);

        // Open progress modal
        await tester.tap(find.text('Add Funds to Goal'));
        await tester.pumpAndSettle();

        expect(find.text('Add to "New Laptop"'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '10000');
        await tester.tap(find.text('Save Progress'));
        await tester.pumpAndSettle();

        expect(goalRepo.goals.first.currentAmount, 5000000);
      },
    );

    // ------------------------------------------------------------------------
    // GROUP 8: RECURRING TRANSACTIONS
    // ------------------------------------------------------------------------
    testWidgets('9. Recurring: Active toggle, process due rules, and list', (
      tester,
    ) async {
      final recRepo = MockRecurringRepo();
      final catRepo = MockCategoryRepo();
      final accRepo = MockAccountRepo();

      recRepo.rules.add(
        RecurringTransactionEntity(
          id: 'r_1',
          userId: 'u1',
          amount: 60000,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Internet Bill',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime.utc(2026, 9, 1),
          nextDate: DateTime.utc(2026, 10, 1),
          isActive: true,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          recurringRepo: recRepo,
          catRepo: catRepo,
          accRepo: accRepo,
          child: const RecurringTransactionsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Internet Bill'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);

      // Toggle active
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(recRepo.rules.first.isActive, isFalse);
    });

    // ------------------------------------------------------------------------
    // GROUP 9 & 10: SETTINGS & MORE
    // ------------------------------------------------------------------------
    testWidgets(
      '10. More/Settings: Theme switching and sub-screen navigation',
      (tester) async {
        final settingsRepo = MockSettingsRepo();

        await tester.pumpWidget(
          buildTestApp(
            settingsRepo: settingsRepo,
            child: const MoreTabScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Settings & More'), findsOneWidget);
        expect(find.text('Accounts & Wallets'), findsOneWidget);
        expect(find.text('Categories'), findsOneWidget);
        expect(find.text('Savings Goals'), findsOneWidget);
        expect(find.text('Recurring Rules'), findsOneWidget);
        expect(find.text('Appearance'), findsOneWidget);
        expect(find.text('Base Currency'), findsOneWidget);
      },
    );
  });
}
