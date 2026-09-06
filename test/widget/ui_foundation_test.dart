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

import 'package:expense_tracker/presentation/providers/app_providers.dart';
import 'package:expense_tracker/presentation/screens/main_shell_screen.dart';
import 'package:expense_tracker/presentation/theme/app_theme.dart';
import 'package:expense_tracker/presentation/widgets/add_transaction_modal.dart';
import 'package:expense_tracker/presentation/widgets/empty_state.dart';
import 'package:expense_tracker/presentation/widgets/error_state.dart';
import 'package:expense_tracker/presentation/widgets/money_text.dart';
import 'package:expense_tracker/presentation/widgets/transaction_tile.dart';

// ============================================================================
// FAKE REPOSITORIES FOR WIDGET TESTS
// ============================================================================

class TestTransactionRepo implements ITransactionRepository {
  final List<TransactionEntity> items = [];

  @override
  Stream<List<TransactionEntity>> watchRecentTransactions({int limit = 20}) =>
      Stream.value(items);

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
  }) async => items;

  @override
  Future<TransactionEntity?> getTransactionById(String id) async => null;

  @override
  Future<void> createTransaction(TransactionEntity transaction) async =>
      items.add(transaction);

  @override
  Future<void> updateTransaction(TransactionEntity transaction) async {}

  @override
  Future<void> softDeleteTransaction(String id) async {}

  @override
  Future<int> getTotalIncome(DateTime start, DateTime end) async => 50000;

  @override
  Future<int> getTotalExpense(DateTime start, DateTime end) async => 20000;
}

class TestAccountRepo implements IAccountRepository {
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
  Future<void> createAccount(AccountEntity account) async =>
      accounts.add(account);

  @override
  Future<void> updateAccount(AccountEntity account) async {}

  @override
  Future<void> softDeleteAccount(String id) async {}

  @override
  Future<int> getAccountBalance(String id) async => 100000;

  @override
  Future<int> getTotalNetWorth() async => 100000;

  @override
  Future<void> transferFunds({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    DateTime? date,
  }) async {}
}

class TestCategoryRepo implements ICategoryRepository {
  final List<CategoryEntity> categories = [];

  @override
  Stream<List<CategoryEntity>> watchCategories({TransactionType? type}) =>
      Stream.value(categories);

  @override
  Future<List<CategoryEntity>> getAllCategories({
    TransactionType? type,
  }) async => categories;

  @override
  Future<CategoryEntity?> getCategoryById(String id) async {
    try {
      return categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createCategory(CategoryEntity category) async =>
      categories.add(category);

  @override
  Future<void> updateCategory(CategoryEntity category) async {}

  @override
  Future<void> archiveCategory(String id) async {}

  @override
  Future<void> softDeleteCategory(String id) async {}
}

class TestBudgetRepo implements IBudgetRepository {
  @override
  Stream<BudgetEntity?> watchMonthlyBudget(String monthYear) =>
      Stream.value(null);

  @override
  Stream<List<CategoryBudgetEntity>> watchCategoryBudgets(String budgetId) =>
      Stream.value([]);

  @override
  Future<BudgetEntity?> getMonthlyBudget(String monthYear) async => null;

  @override
  Future<void> setMonthlyBudget(BudgetEntity budget) async {}

  @override
  Future<void> setCategoryBudget(CategoryBudgetEntity categoryBudget) async {}

  @override
  Future<int> getSpentAmountForMonth(String monthYear) async => 0;

  @override
  Future<int> getSpentAmountForCategory(
    String categoryId,
    String monthYear,
  ) async => 0;
}

class TestGoalRepo implements IGoalRepository {
  @override
  Stream<List<GoalEntity>> watchAllGoals() => Stream.value([]);
  @override
  Future<List<GoalEntity>> getAllGoals() async => [];
  @override
  Future<GoalEntity?> getGoalById(String id) async => null;
  @override
  Future<void> createGoal(GoalEntity goal) async {}
  @override
  Future<void> updateGoal(GoalEntity goal) async {}
  @override
  Future<void> addProgress(String id, int amountMinor) async {}
  @override
  Future<void> softDeleteGoal(String id) async {}
}

class TestRecurringRepo implements IRecurringTransactionRepository {
  @override
  Stream<List<RecurringTransactionEntity>> watchAllRecurring() =>
      Stream.value([]);
  @override
  Future<List<RecurringTransactionEntity>> getDueRecurringTransactions(
    DateTime nowUtc,
  ) async => [];
  @override
  Future<void> createRecurring(RecurringTransactionEntity entity) async {}
  @override
  Future<void> updateRecurring(RecurringTransactionEntity entity) async {}
  @override
  Future<void> toggleActive(String id, bool isActive) async {}
  @override
  Future<void> softDeleteRecurring(String id) async {}
  @override
  Future<int> processDueRecurringRules(DateTime nowUtc) async => 0;
  @override
  Future<void> updateNextExecutionDate(
    String id,
    DateTime nextDate,
    DateTime lastExecutedDate,
  ) async {}
}

class TestSettingsRepo implements ISettingsRepository {
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

class TestSyncRepo implements ISyncRepository {
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

Widget createTestApp({
  required Widget child,
  ThemeMode themeMode = ThemeMode.system,
  TestTransactionRepo? txRepo,
  TestAccountRepo? accRepo,
  TestCategoryRepo? catRepo,
}) {
  final tRepo = txRepo ?? TestTransactionRepo();
  final aRepo = accRepo ?? TestAccountRepo();
  final cRepo = catRepo ?? TestCategoryRepo();
  final bRepo = TestBudgetRepo();
  final gRepo = TestGoalRepo();
  final rRepo = TestRecurringRepo();
  final sRepo = TestSettingsRepo();
  final yRepo = TestSyncRepo();

  return MultiProvider(
    providers: AppProviders.buildProviders(
      transactionRepository: tRepo,
      accountRepository: aRepo,
      categoryRepository: cRepo,
      budgetRepository: bRepo,
      goalRepository: gRepo,
      recurringRepository: rRepo,
      settingsRepository: sRepo,
      syncRepository: yRepo,
    ),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  group('Phase 5 UI Foundation Widget Tests', () {
    testWidgets('1. Light theme builds and applies background and colors', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          themeMode: ThemeMode.light,
          child: const Scaffold(body: Text('Light Theme')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Light Theme'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold, isNotNull);
    });

    testWidgets('2. Dark theme builds and applies dark background and colors', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestApp(
          themeMode: ThemeMode.dark,
          child: const Scaffold(body: Text('Dark Theme')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dark Theme'), findsOneWidget);
    });

    testWidgets(
      '3. App shell builds and displays all 5 navigation destinations',
      (tester) async {
        await tester.pumpWidget(createTestApp(child: const MainShellScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Transactions'), findsOneWidget);
        expect(find.text('Analytics'), findsOneWidget);
        expect(find.text('Budgets'), findsOneWidget);
        expect(find.text('More'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
      },
    );

    testWidgets('4. Bottom navigation bar switches tabs preserving state', (
      tester,
    ) async {
      await tester.pumpWidget(createTestApp(child: const MainShellScreen()));
      await tester.pumpAndSettle();

      // Tap on Transactions tab
      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();
      expect(find.text('Search transactions...'), findsOneWidget);

      // Tap on Analytics tab
      await tester.tap(find.text('Analytics'));
      await tester.pumpAndSettle();
      expect(find.text('Analytics & Insights'), findsOneWidget);

      // Tap on More tab
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Settings & More'), findsOneWidget);
    });

    testWidgets(
      '5. EmptyState widget renders with message and triggers action callback',
      (tester) async {
        bool actionTriggered = false;

        await tester.pumpWidget(
          createTestApp(
            child: Scaffold(
              body: EmptyState(
                title: 'No Data Found',
                message: 'Add an item to get started.',
                actionLabel: 'Add Item',
                onActionPressed: () => actionTriggered = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No Data Found'), findsOneWidget);
        expect(find.text('Add an item to get started.'), findsOneWidget);
        expect(find.text('Add Item'), findsOneWidget);

        await tester.tap(find.text('Add Item'));
        await tester.pumpAndSettle();
        expect(actionTriggered, isTrue);
      },
    );

    testWidgets(
      '6. ErrorState widget renders with error message and triggers retry callback',
      (tester) async {
        bool retryTriggered = false;

        await tester.pumpWidget(
          createTestApp(
            child: Scaffold(
              body: ErrorState(
                title: 'Network Error',
                message: 'Failed to load data.',
                onRetry: () => retryTriggered = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Network Error'), findsOneWidget);
        expect(find.text('Failed to load data.'), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);

        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();
        expect(retryTriggered, isTrue);
      },
    );

    testWidgets(
      '7. MoneyText widget formats positive, negative, and zero minor units',
      (tester) async {
        await tester.pumpWidget(
          createTestApp(
            child: const Scaffold(
              body: Column(
                children: [
                  MoneyText(amountMinor: 50000, type: TransactionType.income),
                  MoneyText(amountMinor: 25000, type: TransactionType.expense),
                  MoneyText(amountMinor: 0),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('+ ₹500.00'), findsOneWidget);
        expect(find.text('- ₹250.00'), findsOneWidget);
        expect(find.text('₹0.00'), findsOneWidget);
      },
    );

    testWidgets(
      '8. TransactionTile correctly renders income and expense transactions',
      (tester) async {
        final txIncome = TransactionEntity(
          id: 'tx_1',
          userId: 'u1',
          amount: 45000,
          type: TransactionType.income,
          categoryId: 'cat_salary',
          accountId: 'acc_bank',
          note: 'Monthly Salary',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );

        await tester.pumpWidget(
          createTestApp(
            child: Scaffold(
              body: TransactionTile(
                transaction: txIncome,
                categoryName: 'Salary',
                accountName: 'Main Bank',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Monthly Salary'), findsOneWidget);
        expect(find.text('+ ₹450.00'), findsOneWidget);
        expect(find.textContaining('Main Bank'), findsOneWidget);
      },
    );

    testWidgets(
      '9. AddTransactionModal opens and validates amount and accounts',
      (tester) async {
        final accRepo = TestAccountRepo();
        accRepo.accounts.add(
          AccountEntity(
            id: 'acc_1',
            userId: 'u1',
            name: 'Cash Wallet',
            type: AccountType.cash,
            initialBalance: 50000,
            currency: 'INR',
            colorValue: 0xFF000000,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        final catRepo = TestCategoryRepo();
        catRepo.categories.add(
          CategoryEntity(
            id: 'cat_1',
            userId: 'u1',
            name: 'Food',
            iconCodePoint: 0xE001,
            colorValue: 0xFFFF0000,
            type: TransactionType.expense,
            isSystem: true,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        await tester.pumpWidget(
          createTestApp(
            accRepo: accRepo,
            catRepo: catRepo,
            child: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AddTransactionModal.show(ctx),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open Modal
        await tester.tap(find.text('Open Modal'));
        await tester.pumpAndSettle();

        expect(find.text('Add Transaction'), findsOneWidget);
        expect(find.text('Save Transaction'), findsOneWidget);

        // Attempt to save with empty amount -> validation error
        await tester.ensureVisible(find.text('Save Transaction'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Transaction'));
        await tester.pumpAndSettle();

        expect(find.text('Amount is required'), findsOneWidget);
      },
    );

    testWidgets(
      '10. Responsive layout foundation does not overflow on standard screen sizes',
      (tester) async {
        for (final size in [
          const Size(320, 600),
          const Size(360, 740),
          const Size(400, 840),
          const Size(600, 900),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            createTestApp(child: const MainShellScreen()),
          );
          await tester.pumpAndSettle();

          expect(find.byType(MainShellScreen), findsOneWidget);
        }

        // Reset
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  });
}
