import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/core/errors/app_exception.dart';
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

import 'package:expense_tracker/presentation/providers/account_provider.dart';
import 'package:expense_tracker/presentation/providers/app_state_provider.dart';
import 'package:expense_tracker/presentation/providers/budget_provider.dart';
import 'package:expense_tracker/presentation/providers/category_provider.dart';
import 'package:expense_tracker/presentation/providers/goal_provider.dart';
import 'package:expense_tracker/presentation/providers/recurring_transaction_provider.dart';
import 'package:expense_tracker/presentation/providers/settings_provider.dart';
import 'package:expense_tracker/presentation/providers/sync_provider.dart';
import 'package:expense_tracker/presentation/providers/transaction_provider.dart';

// ============================================================================
// FAKE REPOSITORIES FOR PROVIDER TESTS
// ============================================================================

class FakeTransactionRepository implements ITransactionRepository {
  final List<TransactionEntity> items = [];
  final StreamController<List<TransactionEntity>> _recentController =
      StreamController<List<TransactionEntity>>.broadcast();
  Duration? simulatedDelay;
  bool shouldThrow = false;
  Future<List<TransactionEntity>> Function({
    DateTime? cursorDate,
    String? cursorId,
    int limit,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? minAmount,
    int? maxAmount,
    String? searchQuery,
  })?
  onGetTransactionsCursor;

  @override
  Stream<List<TransactionEntity>> watchRecentTransactions({int limit = 20}) {
    return _recentController.stream;
  }

  void emitRecent(List<TransactionEntity> recent) {
    _recentController.add(recent);
  }

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
    if (onGetTransactionsCursor != null) {
      return onGetTransactionsCursor!(
        cursorDate: cursorDate,
        cursorId: cursorId,
        limit: limit,
        type: type,
        categoryId: categoryId,
        accountId: accountId,
        startDate: startDate,
        endDate: endDate,
        minAmount: minAmount,
        maxAmount: maxAmount,
        searchQuery: searchQuery,
      );
    }
    if (simulatedDelay != null) {
      await Future.delayed(simulatedDelay!);
    }
    if (shouldThrow) {
      throw const DatabaseException('Database read error');
    }

    var result = items.where((t) => !t.isDeleted).toList();

    if (type != null) {
      result = result.where((t) => t.type == type).toList();
    }
    if (categoryId != null) {
      result = result.where((t) => t.categoryId == categoryId).toList();
    }
    if (accountId != null) {
      result = result.where((t) => t.accountId == accountId).toList();
    }
    if (startDate != null) {
      result = result.where((t) => !t.date.isBefore(startDate)).toList();
    }
    if (endDate != null) {
      result = result.where((t) => !t.date.isAfter(endDate)).toList();
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      result = result
          .where(
            (t) => t.note.toLowerCase().contains(searchQuery.toLowerCase()),
          )
          .toList();
    }

    result.sort((a, b) => b.date.compareTo(a.date));

    if (cursorDate != null) {
      final idx = result.indexWhere(
        (t) =>
            t.date.isBefore(cursorDate) ||
            (t.date == cursorDate && t.id != cursorId),
      );
      if (idx != -1) {
        result = result.sublist(idx);
      } else {
        result = [];
      }
    }

    return result.take(limit).toList();
  }

  @override
  Future<TransactionEntity?> getTransactionById(String id) async {
    try {
      return items.firstWhere((t) => t.id == id && !t.isDeleted);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createTransaction(TransactionEntity transaction) async {
    if (shouldThrow) throw const DatabaseException('Failed to create tx');
    items.add(transaction);
  }

  @override
  Future<void> updateTransaction(TransactionEntity transaction) async {
    if (shouldThrow) throw const DatabaseException('Failed to update tx');
    final idx = items.indexWhere((t) => t.id == transaction.id);
    if (idx != -1) items[idx] = transaction;
  }

  @override
  Future<void> softDeleteTransaction(String id) async {
    if (shouldThrow) throw const DatabaseException('Failed to delete tx');
    final idx = items.indexWhere((t) => t.id == id);
    if (idx != -1) {
      items[idx] = items[idx].copyWith(deletedAt: DateTime.now().toUtc());
    }
  }

  @override
  Future<int> getTotalIncome(DateTime startDateUtc, DateTime endDateUtc) async {
    return items
        .where(
          (t) =>
              !t.isDeleted &&
              t.type == TransactionType.income &&
              !t.date.isBefore(startDateUtc) &&
              !t.date.isAfter(endDateUtc),
        )
        .fold<int>(0, (sum, t) => sum + t.amount);
  }

  @override
  Future<int> getTotalExpense(
    DateTime startDateUtc,
    DateTime endDateUtc,
  ) async {
    return items
        .where(
          (t) =>
              !t.isDeleted &&
              t.type == TransactionType.expense &&
              !t.date.isBefore(startDateUtc) &&
              !t.date.isAfter(endDateUtc),
        )
        .fold<int>(0, (sum, t) => sum + t.amount);
  }
}

class FakeAccountRepository implements IAccountRepository {
  final List<AccountEntity> accounts = [];
  final StreamController<List<AccountEntity>> _controller =
      StreamController<List<AccountEntity>>.broadcast();
  bool shouldThrow = false;
  Future<List<AccountEntity>> Function()? onGetAllAccounts;

  @override
  Stream<List<AccountEntity>> watchAllAccounts() => _controller.stream;

  void emitAccounts(List<AccountEntity> list) {
    _controller.add(list);
  }

  @override
  Future<List<AccountEntity>> getAllAccounts() async {
    if (onGetAllAccounts != null) return onGetAllAccounts!();
    if (shouldThrow) throw const DatabaseException('DB error');
    return accounts.where((a) => !a.isDeleted).toList();
  }

  @override
  Future<AccountEntity?> getAccountById(String id) async {
    try {
      return accounts.firstWhere((a) => a.id == id && !a.isDeleted);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createAccount(AccountEntity account) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    accounts.add(account);
  }

  @override
  Future<void> updateAccount(AccountEntity account) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = accounts.indexWhere((a) => a.id == account.id);
    if (idx != -1) accounts[idx] = account;
  }

  @override
  Future<void> softDeleteAccount(String id) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = accounts.indexWhere((a) => a.id == id);
    if (idx != -1) {
      accounts[idx] = accounts[idx].copyWith(deletedAt: DateTime.now().toUtc());
    }
  }

  @override
  Future<int> getAccountBalance(String accountId) async {
    final acc = await getAccountById(accountId);
    return acc?.initialBalance ?? 0;
  }

  @override
  Future<int> getTotalNetWorth() async {
    return accounts
        .where((a) => !a.isDeleted)
        .fold<int>(0, (sum, a) => sum + a.initialBalance);
  }

  @override
  Future<void> transferFunds({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    DateTime? date,
  }) async {
    if (fromAccountId == toAccountId) {
      throw const ValidationException('Source and dest must differ');
    }
    if (amountMinor <= 0) {
      throw const ValidationException('Amount must be positive');
    }
    final fromIdx = accounts.indexWhere((a) => a.id == fromAccountId);
    final toIdx = accounts.indexWhere((a) => a.id == toAccountId);
    if (fromIdx == -1 || toIdx == -1) {
      throw const NotFoundException('Account not found');
    }

    accounts[fromIdx] = accounts[fromIdx].copyWith(
      initialBalance: accounts[fromIdx].initialBalance - amountMinor,
    );
    accounts[toIdx] = accounts[toIdx].copyWith(
      initialBalance: accounts[toIdx].initialBalance + amountMinor,
    );
  }
}

class FakeCategoryRepository implements ICategoryRepository {
  final List<CategoryEntity> categories = [];
  final StreamController<List<CategoryEntity>> _controller =
      StreamController<List<CategoryEntity>>.broadcast();
  bool shouldThrow = false;

  @override
  Stream<List<CategoryEntity>> watchCategories({TransactionType? type}) =>
      _controller.stream;

  void emitCategories(List<CategoryEntity> list) => _controller.add(list);

  @override
  Future<List<CategoryEntity>> getAllCategories({TransactionType? type}) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    var list = categories.where((c) => !c.isDeleted).toList();
    if (type != null) list = list.where((c) => c.type == type).toList();
    return list;
  }

  @override
  Future<CategoryEntity?> getCategoryById(String id) async {
    try {
      return categories.firstWhere((c) => c.id == id && !c.isDeleted);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createCategory(CategoryEntity category) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    categories.add(category);
  }

  @override
  Future<void> updateCategory(CategoryEntity category) async {
    if (shouldThrow) throw const DatabaseException('DB error');
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
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = categories.indexWhere((c) => c.id == id);
    if (idx != -1) {
      if (categories[idx].isSystem) {
        throw const ValidationException('Cannot delete system category');
      }
      categories[idx] = categories[idx].copyWith(
        deletedAt: DateTime.now().toUtc(),
      );
    }
  }
}

class FakeBudgetRepository implements IBudgetRepository {
  BudgetEntity? monthlyBudget;
  List<CategoryBudgetEntity> categoryBudgets = [];
  int spentMonth = 0;
  final Map<String, int> spentCat = {};
  Duration? delay;
  bool shouldThrow = false;

  final StreamController<BudgetEntity?> _budgetController =
      StreamController<BudgetEntity?>.broadcast();
  final StreamController<List<CategoryBudgetEntity>> _catBudgetsController =
      StreamController<List<CategoryBudgetEntity>>.broadcast();

  @override
  Stream<BudgetEntity?> watchMonthlyBudget(String monthYear) =>
      _budgetController.stream;

  @override
  Stream<List<CategoryBudgetEntity>> watchCategoryBudgets(String budgetId) =>
      _catBudgetsController.stream;

  @override
  Future<BudgetEntity?> getMonthlyBudget(String monthYear) async {
    if (delay != null) await Future.delayed(delay!);
    if (shouldThrow) throw const DatabaseException('DB error');
    if (monthlyBudget?.monthYear == monthYear) return monthlyBudget;
    return null;
  }

  @override
  Future<void> setMonthlyBudget(BudgetEntity budget) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    monthlyBudget = budget;
  }

  @override
  Future<void> setCategoryBudget(CategoryBudgetEntity categoryBudget) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = categoryBudgets.indexWhere((cb) => cb.id == categoryBudget.id);
    if (idx != -1) {
      categoryBudgets[idx] = categoryBudget;
    } else {
      categoryBudgets.add(categoryBudget);
    }
  }

  @override
  Future<int> getSpentAmountForMonth(String monthYear) async {
    return spentMonth;
  }

  @override
  Future<int> getSpentAmountForCategory(
    String categoryId,
    String monthYear,
  ) async {
    return spentCat[categoryId] ?? 0;
  }
}

class FakeGoalRepository implements IGoalRepository {
  final List<GoalEntity> goals = [];
  final StreamController<List<GoalEntity>> _controller =
      StreamController<List<GoalEntity>>.broadcast();
  bool shouldThrow = false;

  @override
  Stream<List<GoalEntity>> watchAllGoals() => _controller.stream;

  void emitGoals(List<GoalEntity> list) => _controller.add(list);

  @override
  Future<List<GoalEntity>> getAllGoals() async {
    if (shouldThrow) throw const DatabaseException('DB error');
    return goals.where((g) => !g.isDeleted).toList();
  }

  @override
  Future<GoalEntity?> getGoalById(String id) async {
    try {
      return goals.firstWhere((g) => g.id == id && !g.isDeleted);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createGoal(GoalEntity goal) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    goals.add(goal);
  }

  @override
  Future<void> updateGoal(GoalEntity goal) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = goals.indexWhere((g) => g.id == goal.id);
    if (idx != -1) goals[idx] = goal;
  }

  @override
  Future<void> addProgress(String id, int amount) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = goals.indexWhere((g) => g.id == id);
    if (idx != -1) {
      goals[idx] = goals[idx].copyWith(
        currentAmount: goals[idx].currentAmount + amount,
      );
    }
  }

  @override
  Future<void> softDeleteGoal(String id) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = goals.indexWhere((g) => g.id == id);
    if (idx != -1) {
      goals[idx] = goals[idx].copyWith(deletedAt: DateTime.now().toUtc());
    }
  }
}

class FakeRecurringTransactionRepository
    implements IRecurringTransactionRepository {
  final List<RecurringTransactionEntity> rules = [];
  final StreamController<List<RecurringTransactionEntity>> _controller =
      StreamController<List<RecurringTransactionEntity>>.broadcast();
  bool shouldThrow = false;

  @override
  Stream<List<RecurringTransactionEntity>> watchAllRecurring() =>
      _controller.stream;

  void emitRules(List<RecurringTransactionEntity> list) =>
      _controller.add(list);

  @override
  Future<List<RecurringTransactionEntity>> getDueRecurringTransactions(
    DateTime nowUtc,
  ) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    return rules.where((r) => !r.isDeleted).toList();
  }

  @override
  Future<void> createRecurring(RecurringTransactionEntity entity) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    rules.add(entity);
  }

  @override
  Future<void> updateRecurring(RecurringTransactionEntity entity) async {
    if (shouldThrow) throw const DatabaseException('DB error');
    final idx = rules.indexWhere((r) => r.id == entity.id);
    if (idx != -1) rules[idx] = entity;
  }

  @override
  Future<void> updateNextExecutionDate(
    String id,
    DateTime nextDate,
    DateTime lastExecutedDate,
  ) async {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx != -1) {
      rules[idx] = rules[idx].copyWith(nextDate: nextDate);
    }
  }

  @override
  Future<void> toggleActive(String id, bool isActive) async {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx != -1) {
      rules[idx] = rules[idx].copyWith(isActive: isActive);
    }
  }

  @override
  Future<void> softDeleteRecurring(String id) async {
    final idx = rules.indexWhere((r) => r.id == id);
    if (idx != -1) {
      rules[idx] = rules[idx].copyWith(deletedAt: DateTime.now().toUtc());
    }
  }

  @override
  Future<int> processDueRecurringRules(DateTime nowUtc) async {
    return rules.where((r) => r.isActive && !r.isDeleted).length;
  }
}

class FakeSettingsRepository implements ISettingsRepository {
  final Map<String, String> settings = {};

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<Map<String, String>> getAllSettings() async => Map.from(settings);

  @override
  Future<void> clearAllSettings() async => settings.clear();
}

class FakeSyncRepository implements ISyncRepository {
  int count = 0;
  List<SyncOperationEntity> ops = [];
  final StreamController<int> _countController =
      StreamController<int>.broadcast();
  final StreamController<List<SyncOperationEntity>> _opsController =
      StreamController<List<SyncOperationEntity>>.broadcast();

  @override
  Future<int> getPendingCount() async => count;

  @override
  Stream<int> watchPendingCount() => _countController.stream;

  @override
  Future<List<SyncOperationEntity>> getPendingOperations({
    int limit = 50,
  }) async => ops.take(limit).toList();

  @override
  Stream<List<SyncOperationEntity>> watchPendingOperations({int limit = 50}) =>
      _opsController.stream;

  @override
  Future<void> enqueueOperation(SyncOperationEntity operation) async {
    ops.add(operation);
    count++;
    _countController.add(count);
    _opsController.add(ops);
  }

  @override
  Future<void> markOperationCompleted(String id) async {
    ops.removeWhere((o) => o.id == id);
    count = ops.length;
    _countController.add(count);
    _opsController.add(ops);
  }

  @override
  Future<void> markOperationFailed(String id, String errorMessage) async {
    final idx = ops.indexWhere((o) => o.id == id);
    if (idx != -1) {
      ops[idx] = ops[idx].copyWith(
        retryCount: ops[idx].retryCount + 1,
        errorMessage: errorMessage,
      );
    }
    _opsController.add(ops);
  }
}

// ============================================================================
// PROVIDER TEST SUITES
// ============================================================================

void main() {
  group('1. TransactionProvider Tests', () {
    late FakeTransactionRepository repo;
    late TransactionProvider provider;

    setUp(() {
      repo = FakeTransactionRepository();
      provider = TransactionProvider(repository: repo, pageSize: 2);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Initial state is clean', () {
      expect(provider.transactions, isEmpty);
      expect(provider.hasMore, true);
      expect(provider.isLoadingInitial, false);
      expect(provider.isLoadingMore, false);
      expect(provider.error, isNull);
      expect(provider.totalIncomeMinor, 0);
      expect(provider.totalExpenseMinor, 0);
    });

    test('Successful loadTransactions fetches and updates state', () async {
      repo.items.addAll([
        TransactionEntity(
          id: 'tx1',
          userId: 'u1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'cat1',
          accountId: 'acc1',
          note: 'Income 1',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        TransactionEntity(
          id: 'tx2',
          userId: 'u1',
          amount: 20000,
          type: TransactionType.expense,
          categoryId: 'cat2',
          accountId: 'acc1',
          note: 'Expense 1',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      ]);

      await provider.loadTransactions();
      expect(provider.transactions.length, 2);
      expect(provider.hasMore, true); // limit was 2 and 2 were returned
      expect(provider.error, isNull);
    });

    test('loadTransactions failure sets user-friendly error', () async {
      repo.shouldThrow = true;
      await provider.loadTransactions();
      expect(provider.transactions, isEmpty);
      expect(provider.error, isNotNull);
      expect(provider.error, 'Database read error');
    });

    test(
      'Keyset pagination loadMore appends items without duplicate fetch',
      () async {
        repo.items.addAll([
          TransactionEntity(
            id: 'tx1',
            userId: 'u1',
            amount: 100,
            type: TransactionType.expense,
            categoryId: 'c1',
            accountId: 'a1',
            note: 'N1',
            date: DateTime.utc(2026, 9, 3),
            createdAt: DateTime.utc(2026, 9, 3),
            updatedAt: DateTime.utc(2026, 9, 3),
          ),
          TransactionEntity(
            id: 'tx2',
            userId: 'u1',
            amount: 200,
            type: TransactionType.expense,
            categoryId: 'c1',
            accountId: 'a1',
            note: 'N2',
            date: DateTime.utc(2026, 9, 2),
            createdAt: DateTime.utc(2026, 9, 2),
            updatedAt: DateTime.utc(2026, 9, 2),
          ),
          TransactionEntity(
            id: 'tx3',
            userId: 'u1',
            amount: 300,
            type: TransactionType.expense,
            categoryId: 'c1',
            accountId: 'a1',
            note: 'N3',
            date: DateTime.utc(2026, 9, 1),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ]);

        await provider.loadTransactions();
        expect(provider.transactions.length, 2);
        expect(provider.hasMore, true);

        await provider.loadMore();
        expect(provider.transactions.length, 3);
        expect(
          provider.hasMore,
          false,
        ); // only 1 was returned on page 2 (< pageSize 2)
      },
    );

    test('Filter update resets pagination and reloads data', () async {
      repo.items.addAll([
        TransactionEntity(
          id: 'tx1',
          userId: 'u1',
          amount: 1000,
          type: TransactionType.income,
          categoryId: 'c_inc',
          accountId: 'a1',
          note: 'Salary',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        TransactionEntity(
          id: 'tx2',
          userId: 'u1',
          amount: 2000,
          type: TransactionType.expense,
          categoryId: 'c_exp',
          accountId: 'a1',
          note: 'Groceries',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      ]);

      await provider.loadTransactions();
      expect(provider.transactions.length, 2);

      provider.updateFilter(type: TransactionType.income);
      // Wait for async load
      await Future.delayed(const Duration(milliseconds: 50));
      expect(provider.filter.type, TransactionType.income);
      expect(provider.transactions.length, 1);
      expect(provider.transactions.first.id, 'tx1');

      provider.resetFilter();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(provider.transactions.length, 2);
    });

    test('Debounced search and stale query token protection', () async {
      repo.items.addAll([
        TransactionEntity(
          id: 'tx_groceries',
          userId: 'u1',
          amount: 500,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Groceries supermarket',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        TransactionEntity(
          id: 'tx_books',
          userId: 'u1',
          amount: 800,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Science books',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      ]);

      // Trigger search with 50ms debounce for test
      provider.setSearchQuery(
        'Groc',
        debounce: const Duration(milliseconds: 50),
      );
      expect(
        provider.transactions,
        isEmpty,
      ); // Not executed yet before debounce

      await Future.delayed(const Duration(milliseconds: 70));
      expect(provider.transactions.length, 1);
      expect(provider.transactions.first.id, 'tx_groceries');
    });

    test('Create, update, delete transaction actions', () async {
      final tx = TransactionEntity(
        id: 'tx_new',
        userId: 'u1',
        amount: 12000,
        type: TransactionType.income,
        categoryId: 'c1',
        accountId: 'a1',
        note: 'New Transaction',
        date: DateTime.utc(2026, 9, 1),
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      await provider.createTransaction(tx);
      expect(provider.transactions.any((t) => t.id == 'tx_new'), isTrue);

      final updatedTx = tx.copyWith(amount: 15000);
      await provider.updateTransaction(updatedTx);
      expect(
        provider.transactions.firstWhere((t) => t.id == 'tx_new').amount,
        15000,
      );

      await provider.deleteTransaction('tx_new');
      expect(provider.transactions.any((t) => t.id == 'tx_new'), isFalse);
    });

    test('Totals aggregation calculates net income & expenses', () async {
      repo.items.addAll([
        TransactionEntity(
          id: 't1',
          userId: 'u1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Salary',
          date: DateTime.utc(2026, 9, 5),
          createdAt: DateTime.utc(2026, 9, 5),
          updatedAt: DateTime.utc(2026, 9, 5),
        ),
        TransactionEntity(
          id: 't2',
          userId: 'u1',
          amount: 15000,
          type: TransactionType.expense,
          categoryId: 'c2',
          accountId: 'a1',
          note: 'Dining',
          date: DateTime.utc(2026, 9, 6),
          createdAt: DateTime.utc(2026, 9, 6),
          updatedAt: DateTime.utc(2026, 9, 6),
        ),
      ]);

      await provider.loadTotals(
        startDateUtc: DateTime.utc(2026, 9, 1),
        endDateUtc: DateTime.utc(2026, 9, 30),
      );
      expect(provider.totalIncomeMinor, 50000);
      expect(provider.totalExpenseMinor, 15000);
      expect(provider.netSavingsMinor, 35000);
    });
  });

  group('2. AccountProvider Tests', () {
    late FakeAccountRepository repo;
    late AccountProvider provider;

    setUp(() {
      repo = FakeAccountRepository();
      provider = AccountProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Load accounts & net worth calculation', () async {
      repo.accounts.addAll([
        AccountEntity(
          id: 'acc1',
          userId: 'u1',
          name: 'Bank',
          type: AccountType.bank,
          initialBalance: 200000,
          currency: 'INR',
          colorValue: 0xFF2196F3,
          iconCodePoint: 0xE84F,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        AccountEntity(
          id: 'acc2',
          userId: 'u1',
          name: 'Cash',
          type: AccountType.cash,
          initialBalance: 50000,
          currency: 'INR',
          colorValue: 0xFF4CAF50,
          iconCodePoint: 0xE84F,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);

      await provider.loadAccounts();
      expect(provider.accounts.length, 2);
      expect(provider.totalNetWorthMinor, 250000);
      expect(provider.state.hasData, isTrue);
    });

    test('Atomic transfer between accounts refreshes net worth', () async {
      repo.accounts.addAll([
        AccountEntity(
          id: 'a1',
          userId: 'u1',
          name: 'Checking',
          type: AccountType.bank,
          initialBalance: 100000,
          currency: 'INR',
          colorValue: 0xFF2196F3,
          iconCodePoint: 0xE84F,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        AccountEntity(
          id: 'a2',
          userId: 'u1',
          name: 'Savings',
          type: AccountType.savings,
          initialBalance: 50000,
          currency: 'INR',
          colorValue: 0xFF4CAF50,
          iconCodePoint: 0xE84F,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);
      await provider.loadAccounts();

      await provider.transferFunds(
        fromAccountId: 'a1',
        toAccountId: 'a2',
        amountMinor: 30000,
      );

      expect(
        repo.accounts.firstWhere((a) => a.id == 'a1').initialBalance,
        70000,
      );
      expect(
        repo.accounts.firstWhere((a) => a.id == 'a2').initialBalance,
        80000,
      );
      expect(
        provider.totalNetWorthMinor,
        150000,
      ); // Net worth invariant preserved
      expect(provider.transferError, isNull);
    });

    test('Transfer validation failure produces user error', () async {
      expect(
        () => provider.transferFunds(
          fromAccountId: 'same',
          toAccountId: 'same',
          amountMinor: 500,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('3. CategoryProvider Tests', () {
    late FakeCategoryRepository repo;
    late CategoryProvider provider;

    setUp(() {
      repo = FakeCategoryRepository();
      provider = CategoryProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Filters system, custom, income, expense categories', () async {
      repo.categories.addAll([
        CategoryEntity(
          id: 'c1',
          userId: 'u1',
          name: 'Salary',
          type: TransactionType.income,
          isSystem: true,
          iconCodePoint: 1,
          colorValue: 1,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        CategoryEntity(
          id: 'c2',
          userId: 'u1',
          name: 'Groceries',
          type: TransactionType.expense,
          isSystem: true,
          iconCodePoint: 2,
          colorValue: 2,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        CategoryEntity(
          id: 'c3',
          userId: 'u1',
          name: 'Custom Freelance',
          type: TransactionType.income,
          isSystem: false,
          iconCodePoint: 3,
          colorValue: 3,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);

      await provider.loadCategories();
      expect(provider.categories.length, 3);
      expect(provider.incomeCategories.length, 2);
      expect(provider.expenseCategories.length, 1);
      expect(provider.systemCategories.length, 2);
      expect(provider.customCategories.length, 1);
    });

    test('Archive and soft delete custom category', () async {
      final cat = CategoryEntity(
        id: 'c_custom',
        userId: 'u1',
        name: 'Gym',
        type: TransactionType.expense,
        isSystem: false,
        iconCodePoint: 4,
        colorValue: 4,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      repo.categories.add(cat);
      await provider.loadCategories();

      await provider.archiveCategory('c_custom');
      expect(
        repo.categories.firstWhere((c) => c.id == 'c_custom').isArchived,
        isTrue,
      );

      await provider.deleteCategory('c_custom');
      expect(provider.categories.any((c) => c.id == 'c_custom'), isFalse);
    });
  });

  group('4. BudgetProvider Tests', () {
    late FakeBudgetRepository repo;
    late BudgetProvider provider;

    setUp(() {
      repo = FakeBudgetRepository();
      provider = BudgetProvider(repository: repo, initialMonthYear: '2026-09');
    });

    tearDown(() {
      provider.dispose();
    });

    test(
      'Loads monthly budget, spent progress, and remaining calculations',
      () async {
        repo.monthlyBudget = BudgetEntity(
          id: 'b1',
          userId: 'u1',
          monthYear: '2026-09',
          amount: 100000,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        repo.spentMonth = 40000;

        await provider.loadBudgetForSelectedMonth();
        expect(provider.totalBudgetLimitMinor, 100000);
        expect(provider.totalSpentMinor, 40000);
        expect(provider.remainingBudgetMinor, 60000);
        expect(provider.budgetProgressPercentage, 40.0);
        expect(provider.isOverBudget, isFalse);
      },
    );

    test('Month change updates selected month and reloads data', () async {
      provider.setSelectedMonth('2026-10');
      expect(provider.selectedMonthYear, '2026-10');
    });

    test('Stale month request protection', () async {
      repo.delay = const Duration(milliseconds: 50);
      repo.monthlyBudget = BudgetEntity(
        id: 'b_sep',
        userId: 'u1',
        monthYear: '2026-09',
        amount: 50000,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      // Start September load
      provider.loadBudgetForSelectedMonth();
      // Immediately switch to October
      provider.setSelectedMonth('2026-10');

      await Future.delayed(const Duration(milliseconds: 100));
      expect(provider.selectedMonthYear, '2026-10');
    });
  });

  group('5. GoalProvider Tests', () {
    late FakeGoalRepository repo;
    late GoalProvider provider;

    setUp(() {
      repo = FakeGoalRepository();
      provider = GoalProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Goal loading and domain progress percentage / remaining', () async {
      repo.goals.add(
        GoalEntity(
          id: 'g1',
          userId: 'u1',
          name: 'Emergency Fund',
          targetAmount: 100000,
          currentAmount: 25000,
          targetDate: DateTime.utc(2026, 12, 31),
          iconCodePoint: 1,
          colorValue: 1,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      await provider.loadGoals();
      expect(provider.goals.length, 1);
      final goal = provider.goals.first;
      expect(goal.progressPercentage, 0.25);
      expect(goal.remainingAmount, 75000);
      expect(goal.isCompleted, isFalse);
      expect(provider.totalSavedMinor, 25000);
      expect(provider.totalTargetMinor, 100000);
    });

    test('Add progress towards goal via repository', () async {
      repo.goals.add(
        GoalEntity(
          id: 'g2',
          userId: 'u1',
          name: 'Laptop',
          targetAmount: 80000,
          currentAmount: 20000,
          targetDate: DateTime.utc(2026, 10, 1),
          iconCodePoint: 2,
          colorValue: 2,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      );

      await provider.addProgress('g2', 60000);
      expect(repo.goals.firstWhere((g) => g.id == 'g2').currentAmount, 80000);
      expect(repo.goals.firstWhere((g) => g.id == 'g2').isCompleted, isTrue);
    });
  });

  group('6. RecurringTransactionProvider Tests', () {
    late FakeRecurringTransactionRepository repo;
    late RecurringTransactionProvider provider;

    setUp(() {
      repo = FakeRecurringTransactionRepository();
      provider = RecurringTransactionProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Loads rules and filters active vs paused', () async {
      repo.rules.addAll([
        RecurringTransactionEntity(
          id: 'r1',
          userId: 'u1',
          amount: 25000,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Rent',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime.utc(2026, 9, 1),
          nextDate: DateTime.utc(2026, 10, 1),
          isActive: true,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
        RecurringTransactionEntity(
          id: 'r2',
          userId: 'u1',
          amount: 10000,
          type: TransactionType.expense,
          categoryId: 'c2',
          accountId: 'a1',
          note: 'Gym',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime.utc(2026, 9, 1),
          nextDate: DateTime.utc(2026, 10, 1),
          isActive: false,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]);

      await provider.loadRules();
      expect(provider.rules.length, 2);
      expect(provider.activeRules.length, 1);
      expect(provider.pausedRules.length, 1);
    });

    test('Processes due rules and updates execution count', () async {
      repo.rules.add(
        RecurringTransactionEntity(
          id: 'r_due',
          userId: 'u1',
          amount: 5000,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Spotify',
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime.utc(2026, 8, 1),
          nextDate: DateTime.utc(2026, 9, 1),
          isActive: true,
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );

      final count = await provider.processDueRecurringRules();
      expect(count, 1);
      expect(provider.lastProcessedCount, 1);
    });
  });

  group('7. SettingsProvider Tests', () {
    late FakeSettingsRepository repo;
    late SettingsProvider provider;

    setUp(() {
      repo = FakeSettingsRepository();
      provider = SettingsProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
    });

    test(
      'Loads default and custom settings, updates theme and currency',
      () async {
        await provider.loadSettings();
        expect(provider.themeMode, ThemeMode.system);
        expect(provider.currency, 'INR');
        expect(provider.isFirstLaunch, isTrue);

        await provider.setThemeMode(ThemeMode.dark);
        expect(provider.themeMode, ThemeMode.dark);
        expect(repo.settings[SettingsProvider.keyThemeMode], 'dark');

        await provider.setCurrency('USD');
        expect(provider.currency, 'USD');
        expect(repo.settings[SettingsProvider.keyCurrency], 'USD');

        await provider.setFirstLaunchCompleted();
        expect(provider.isFirstLaunch, isFalse);
      },
    );

    test('Non-sensitive biometric and PIN flags', () async {
      await provider.setBiometricEnabled(true);
      expect(provider.isBiometricEnabled, isTrue);

      await provider.setPinSet(true);
      expect(provider.isPinSet, isTrue);
    });
  });

  group('8. SyncProvider Tests', () {
    late FakeSyncRepository repo;
    late SyncProvider provider;

    setUp(() {
      repo = FakeSyncRepository();
      provider = SyncProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Loads pending count and operations', () async {
      repo.count = 3;
      repo.ops.addAll([
        SyncOperationEntity(
          id: 'op1',
          entityType: EntityType.transaction,
          entityId: 't1',
          operationType: SyncOperationType.create,
          payloadJson: '{}',
          retryCount: 0,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
        SyncOperationEntity(
          id: 'op2',
          entityType: EntityType.account,
          entityId: 'a1',
          operationType: SyncOperationType.update,
          payloadJson: '{}',
          retryCount: 2,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ]);

      await provider.loadSyncState();
      expect(provider.pendingCount, 3);
      expect(provider.hasPendingOperations, isTrue);
      expect(provider.failedOperationCount, 1);
    });

    test('Toggles syncing state and tracks last sync time', () {
      provider.setSyncingState(true);
      expect(provider.isSyncing, isTrue);

      provider.setSyncingState(false);
      expect(provider.isSyncing, isFalse);
      expect(provider.lastSyncTime, isNotNull);
    });
  });

  group('9. AppStateProvider Tests', () {
    late AppStateProvider provider;

    setUp(() {
      provider = AppStateProvider(initialUserId: 'guest_user');
    });

    tearDown(() {
      provider.dispose();
    });

    test('Initial state and successful initialization lifecycle', () async {
      expect(provider.initStatus, AppInitStatus.uninitialized);
      expect(provider.currentUserId, 'guest_user');
      expect(provider.isInitialized, false);

      await provider.initialize(
        onInitHook: () async {
          // Simulated async setup
        },
      );

      expect(provider.initStatus, AppInitStatus.initialized);
      expect(provider.isInitialized, true);
      expect(provider.hasFatalError, false);
      expect(provider.fatalError, isNull);
    });

    test('Initialization failure sets fatal error state', () async {
      await provider.initialize(
        onInitHook: () async {
          throw Exception('Database decryption failed');
        },
      );

      expect(provider.initStatus, AppInitStatus.error);
      expect(provider.hasFatalError, true);
      expect(provider.fatalError, contains('Database decryption failed'));
    });

    test('Switch active user ID and triggers listener', () {
      String? switchedUser;
      provider.addOnUserChangedListener((newId) {
        switchedUser = newId;
      });

      provider.switchUser('auth_user_123');
      expect(provider.currentUserId, 'auth_user_123');
      expect(switchedUser, 'auth_user_123');
    });
  });

  group('10. Provider User-Switch Integration & Invalidation Tests', () {
    test(
      'Switching user clears old state, cancels streams, and loads new user without leakage',
      () async {
        final txRepo = FakeTransactionRepository();
        final accRepo = FakeAccountRepository();

        // 1. Populate User A data
        txRepo.items.add(
          TransactionEntity(
            id: 'tx_user_a',
            userId: 'user_a',
            amount: 50000,
            type: TransactionType.income,
            categoryId: 'c1',
            accountId: 'a1',
            note: 'User A Income',
            date: DateTime.utc(2026, 9, 1),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        accRepo.accounts.add(
          AccountEntity(
            id: 'acc_user_a',
            userId: 'user_a',
            name: 'User A Bank',
            type: AccountType.bank,
            initialBalance: 100000,
            currency: 'INR',
            colorValue: 0xFF2196F3,
            iconCodePoint: 0xE84F,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

        final txProvider = TransactionProvider(repository: txRepo);
        final accProvider = AccountProvider(repository: accRepo);
        final appState = AppStateProvider(initialUserId: 'user_a');

        // Wire user change listener
        appState.addOnUserChangedListener((newUserId) {
          txProvider.reset(reload: true);
          accProvider.reset(reload: true);
        });

        await txProvider.loadTransactions();
        await accProvider.loadAccounts();

        expect(txProvider.transactions.length, 1);
        expect(txProvider.transactions.first.id, 'tx_user_a');
        expect(accProvider.accounts.length, 1);
        expect(accProvider.accounts.first.id, 'acc_user_a');

        // 2. Clear repo of User A, switch to User B in repository
        txRepo.items.clear();
        accRepo.accounts.clear();

        txRepo.items.add(
          TransactionEntity(
            id: 'tx_user_b',
            userId: 'user_b',
            amount: 25000,
            type: TransactionType.expense,
            categoryId: 'c2',
            accountId: 'a2',
            note: 'User B Expense',
            date: DateTime.utc(2026, 9, 2),
            createdAt: DateTime.utc(2026, 9, 2),
            updatedAt: DateTime.utc(2026, 9, 2),
          ),
        );

        // 3. Switch user in AppState
        appState.switchUser('user_b');
        await Future.delayed(const Duration(milliseconds: 50));

        // Verify User A data is completely gone and User B is loaded
        expect(txProvider.transactions.length, 1);
        expect(txProvider.transactions.first.id, 'tx_user_b');
        expect(accProvider.accounts, isEmpty);

        txProvider.dispose();
        accProvider.dispose();
        appState.dispose();
      },
    );
  });

  group('11. In-Flight Pagination Race Condition & Contamination Guard', () {
    test(
      'Slow loadMore for Filter A cannot contaminate results when filter switches to Filter B',
      () async {
        final repo = FakeTransactionRepository();
        final provider = TransactionProvider(repository: repo, pageSize: 2);

        // Filter A items
        final txA1 = TransactionEntity(
          id: 'tx_a1',
          userId: 'u1',
          amount: 100,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Income 1',
          date: DateTime.utc(2026, 9, 5),
          createdAt: DateTime.utc(2026, 9, 5),
          updatedAt: DateTime.utc(2026, 9, 5),
        );
        final txA2 = TransactionEntity(
          id: 'tx_a2',
          userId: 'u1',
          amount: 200,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Income 2',
          date: DateTime.utc(2026, 9, 4),
          createdAt: DateTime.utc(2026, 9, 4),
          updatedAt: DateTime.utc(2026, 9, 4),
        );
        final txA3 = TransactionEntity(
          id: 'tx_a3',
          userId: 'u1',
          amount: 300,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Income 3 (Page 2)',
          date: DateTime.utc(2026, 9, 3),
          createdAt: DateTime.utc(2026, 9, 3),
          updatedAt: DateTime.utc(2026, 9, 3),
        );

        // Filter B items
        final txB1 = TransactionEntity(
          id: 'tx_b1',
          userId: 'u1',
          amount: 500,
          type: TransactionType.expense,
          categoryId: 'c2',
          accountId: 'a1',
          note: 'Expense 1',
          date: DateTime.utc(2026, 9, 5),
          createdAt: DateTime.utc(2026, 9, 5),
          updatedAt: DateTime.utc(2026, 9, 5),
        );

        repo.items.addAll([txA1, txA2, txA3, txB1]);

        // 1. Set Filter A (Income) and load Page 1
        provider.setFilter(
          const TransactionFilterState(type: TransactionType.income),
        );
        await Future.delayed(const Duration(milliseconds: 50));
        expect(provider.transactions.length, 2);
        expect(provider.transactions.map((t) => t.id).toList(), [
          'tx_a1',
          'tx_a2',
        ]);

        // 2. Introduce artificial delay on repository for loadMore
        repo.simulatedDelay = const Duration(milliseconds: 100);

        // 3. Trigger slow loadMore for Filter A in background
        final loadMoreFuture = provider.loadMore();

        // 4. Immediately switch filter to Filter B (Expense)
        repo.simulatedDelay = null; // Filter B load will be fast
        provider.setFilter(
          const TransactionFilterState(type: TransactionType.expense),
        );
        await Future.delayed(const Duration(milliseconds: 30));

        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_b1');

        // 5. Await completion of the slow loadMore for Filter A
        await loadMoreFuture;

        // 6. Verify Filter A (txA3) was NOT appended to Filter B results!
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_b1');
        expect(provider.transactions.any((t) => t.id == 'tx_a3'), isFalse);

        provider.dispose();
      },
    );
  });

  group('12. Rapid Search Debounce Sequence Audit', () {
    test(
      'Rapid typing "a" -> "ab" -> "abc" only executes final intended query',
      () async {
        final repo = FakeTransactionRepository();
        final provider = TransactionProvider(repository: repo);

        repo.items.addAll([
          TransactionEntity(
            id: 'tx_apple',
            userId: 'u1',
            amount: 100,
            type: TransactionType.expense,
            categoryId: 'c1',
            accountId: 'a1',
            note: 'apple fruit',
            date: DateTime.utc(2026, 9, 1),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
          TransactionEntity(
            id: 'tx_abc',
            userId: 'u1',
            amount: 200,
            type: TransactionType.expense,
            categoryId: 'c1',
            accountId: 'a1',
            note: 'abc company',
            date: DateTime.utc(2026, 9, 2),
            createdAt: DateTime.utc(2026, 9, 2),
            updatedAt: DateTime.utc(2026, 9, 2),
          ),
        ]);

        // Rapid typing within debounce interval
        provider.setSearchQuery(
          'a',
          debounce: const Duration(milliseconds: 60),
        );
        await Future.delayed(const Duration(milliseconds: 20));
        provider.setSearchQuery(
          'ab',
          debounce: const Duration(milliseconds: 60),
        );
        await Future.delayed(const Duration(milliseconds: 20));
        provider.setSearchQuery(
          'abc',
          debounce: const Duration(milliseconds: 60),
        );

        // Wait for debounce timer to fire
        await Future.delayed(const Duration(milliseconds: 80));

        expect(provider.filter.searchQuery, 'abc');
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_abc');

        provider.dispose();
      },
    );
  });

  group('13. Settings Security Boundary Audit', () {
    test(
      'SettingsProvider throws SecurityException when trying to store secrets',
      () async {
        final repo = FakeSettingsRepository();
        final provider = SettingsProvider(repository: repo);

        expect(
          () => provider.setCustomSetting('user_pin', '1234'),
          throwsA(isA<SecurityException>()),
        );
        expect(
          () => provider.setCustomSetting('encryption_key', 'my_db_key'),
          throwsA(isA<SecurityException>()),
        );
        expect(
          () => provider.setCustomSetting('auth_token', 'jwt.secret.token'),
          throwsA(isA<SecurityException>()),
        );

        // Safe non-secret settings succeed
        await provider.setCustomSetting('export_csv_separator', ',');
        expect(provider.customSettings['export_csv_separator'], ',');

        provider.dispose();
      },
    );
  });

  group('14. Old Stream Emission Immunity After User Switch', () {
    test(
      'Old user stream emission after switch cannot corrupt new user state',
      () async {
        final repo = FakeAccountRepository();
        final provider = AccountProvider(repository: repo);

        // 1. User A starts watching
        provider.watchAccounts();
        repo.emitAccounts([
          AccountEntity(
            id: 'acc_a',
            userId: 'user_a',
            name: 'Account A',
            type: AccountType.bank,
            initialBalance: 50000,
            currency: 'INR',
            colorValue: 0xFF2196F3,
            iconCodePoint: 0xE84F,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 30));
        expect(provider.accounts.length, 1);
        expect(provider.accounts.first.id, 'acc_a');

        // 2. Switch user to User B -> resets provider
        await provider.reset(reload: false);
        expect(provider.accounts, isEmpty);

        // 3. Old stream controller emits late User A data
        repo.emitAccounts([
          AccountEntity(
            id: 'acc_a_late',
            userId: 'user_a',
            name: 'Late A Account',
            type: AccountType.bank,
            initialBalance: 99999,
            currency: 'INR',
            colorValue: 0xFF2196F3,
            iconCodePoint: 0xE84F,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 30));

        // Provider was reset (old subscription was cancelled), so late emission is ignored!
        expect(provider.accounts, isEmpty);

        provider.dispose();
      },
    );
  });

  group('15. Deterministic Race Condition Audits', () {
    test(
      'A. Search -> clearSearch -> stale search ignored deterministically',
      () async {
        final repo = FakeTransactionRepository();
        final provider = TransactionProvider(repository: repo);

        final baseTx = TransactionEntity(
          id: 'tx_base',
          userId: 'u1',
          amount: 100,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Base grocery',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        final searchFoodTx = TransactionEntity(
          id: 'tx_food',
          userId: 'u1',
          amount: 200,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Delicious food item',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        );

        repo.items.add(baseTx);

        // Initial load of base transactions
        await provider.loadTransactions();
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_base');

        // Setup controllable completer for the "food" search query
        final searchCompleter = Completer<List<TransactionEntity>>();
        repo.onGetTransactionsCursor =
            ({
              cursorDate,
              cursorId,
              limit = 50,
              type,
              categoryId,
              accountId,
              startDate,
              endDate,
              minAmount,
              maxAmount,
              searchQuery,
            }) {
              if (searchQuery == 'food') {
                return searchCompleter.future;
              }
              return Future.value([baseTx]);
            };

        // 1. User types "food" with immediate debounce
        provider.setSearchQuery('food', debounce: Duration.zero);
        // Microtask pump to let the debounce timer fire and call loadTransactions()
        await Future.delayed(const Duration(milliseconds: 10));

        // 2. User immediately clears search before the "food" search completes
        provider.clearSearch();
        await Future.delayed(const Duration(milliseconds: 10));

        // Base list is present
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_base');

        // 3. Stale "food" search completes afterward
        searchCompleter.complete([searchFoodTx]);
        await Future.delayed(const Duration(milliseconds: 10));

        // 4. Stale search result MUST be ignored!
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_base');
        expect(provider.transactions.any((t) => t.id == 'tx_food'), isFalse);

        provider.dispose();
      },
    );

    test(
      'B. Filter A -> Filter B -> stale Filter A response ignored deterministically',
      () async {
        final repo = FakeTransactionRepository();
        final provider = TransactionProvider(repository: repo);

        final incomeTx = TransactionEntity(
          id: 'tx_income',
          userId: 'u1',
          amount: 500,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Income record',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        final expenseTx = TransactionEntity(
          id: 'tx_expense',
          userId: 'u1',
          amount: 250,
          type: TransactionType.expense,
          categoryId: 'c2',
          accountId: 'a1',
          note: 'Expense record',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        );

        final filterACompleter = Completer<List<TransactionEntity>>();

        repo.onGetTransactionsCursor =
            ({
              cursorDate,
              cursorId,
              limit = 50,
              type,
              categoryId,
              accountId,
              startDate,
              endDate,
              minAmount,
              maxAmount,
              searchQuery,
            }) {
              if (type == TransactionType.income) {
                return filterACompleter.future;
              } else if (type == TransactionType.expense) {
                return Future.value([expenseTx]);
              }
              return Future.value([]);
            };

        // 1. Filter A (income) starts in-flight
        provider.setFilter(
          const TransactionFilterState(type: TransactionType.income),
        );
        await Future.delayed(const Duration(milliseconds: 10));

        // 2. User switches to Filter B (expense), which resolves immediately
        provider.setFilter(
          const TransactionFilterState(type: TransactionType.expense),
        );
        await Future.delayed(const Duration(milliseconds: 10));

        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_expense');

        // 3. Stale Filter A completes
        filterACompleter.complete([incomeTx]);
        await Future.delayed(const Duration(milliseconds: 10));

        // 4. Stale Filter A response is ignored!
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_expense');

        provider.dispose();
      },
    );

    test(
      'C. Filter A page 2 -> Filter B -> stale page 2 ignored deterministically',
      () async {
        final repo = FakeTransactionRepository();
        final provider = TransactionProvider(repository: repo, pageSize: 1);

        final txA1 = TransactionEntity(
          id: 'tx_a1',
          userId: 'u1',
          amount: 100,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'A1',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        );
        final txA2 = TransactionEntity(
          id: 'tx_a2',
          userId: 'u1',
          amount: 200,
          type: TransactionType.income,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'A2 (Page 2)',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        final txB1 = TransactionEntity(
          id: 'tx_b1',
          userId: 'u1',
          amount: 300,
          type: TransactionType.expense,
          categoryId: 'c2',
          accountId: 'a1',
          note: 'B1',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );

        final page2Completer = Completer<List<TransactionEntity>>();

        repo.onGetTransactionsCursor =
            ({
              cursorDate,
              cursorId,
              limit = 50,
              type,
              categoryId,
              accountId,
              startDate,
              endDate,
              minAmount,
              maxAmount,
              searchQuery,
            }) {
              if (type == TransactionType.income && cursorDate == null) {
                return Future.value([txA1]);
              } else if (type == TransactionType.income && cursorDate != null) {
                return page2Completer.future;
              } else if (type == TransactionType.expense) {
                return Future.value([txB1]);
              }
              return Future.value([]);
            };

        // 1. Load Filter A page 1
        provider.setFilter(
          const TransactionFilterState(type: TransactionType.income),
        );
        await Future.delayed(const Duration(milliseconds: 10));
        expect(provider.transactions.map((t) => t.id).toList(), ['tx_a1']);

        // 2. Trigger Filter A page 2 load
        provider.loadMore();
        await Future.delayed(const Duration(milliseconds: 10));

        // 3. User switches to Filter B
        provider.setFilter(
          const TransactionFilterState(type: TransactionType.expense),
        );
        await Future.delayed(const Duration(milliseconds: 10));
        expect(provider.transactions.map((t) => t.id).toList(), ['tx_b1']);

        // 4. Stale Filter A page 2 completes
        page2Completer.complete([txA2]);
        await Future.delayed(const Duration(milliseconds: 10));

        // 5. Stale page 2 is NOT appended
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_b1');

        provider.dispose();
      },
    );

    test(
      'D. User A -> User B -> stale User A async response ignored deterministically',
      () async {
        final repo = FakeAccountRepository();
        final provider = AccountProvider(repository: repo);

        final userAAccounts = [
          AccountEntity(
            id: 'acc_a',
            userId: 'user_a',
            name: 'User A Bank',
            type: AccountType.bank,
            initialBalance: 1000,
            currency: 'INR',
            colorValue: 0xFF000000,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ];

        final userBAccounts = [
          AccountEntity(
            id: 'acc_b',
            userId: 'user_b',
            name: 'User B Bank',
            type: AccountType.bank,
            initialBalance: 5000,
            currency: 'INR',
            colorValue: 0xFF000000,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ];

        final userACompleter = Completer<List<AccountEntity>>();
        repo.onGetAllAccounts = () => userACompleter.future;

        // 1. User A starts loading accounts
        final loadAFuture = provider.loadAccounts();
        await Future.delayed(const Duration(milliseconds: 10));

        // 2. User switches to User B (resets provider and loads User B)
        await provider.reset(reload: false);
        repo.onGetAllAccounts = () => Future.value(userBAccounts);
        await provider.loadAccounts();

        expect(provider.accounts.length, 1);
        expect(provider.accounts.first.id, 'acc_b');

        // 3. Stale User A load completes
        userACompleter.complete(userAAccounts);
        await loadAFuture;
        await Future.delayed(const Duration(milliseconds: 10));

        // 4. State must still belong strictly to User B!
        expect(provider.accounts.length, 1);
        expect(provider.accounts.first.id, 'acc_b');

        provider.dispose();
      },
    );

    test(
      'E. User A stream -> User B -> stale User A stream emission ignored deterministically',
      () async {
        final repo = FakeAccountRepository();
        final provider = AccountProvider(repository: repo);

        // 1. User A watches accounts
        provider.watchAccounts();
        repo.emitAccounts([
          AccountEntity(
            id: 'acc_a',
            userId: 'user_a',
            name: 'User A Live Bank',
            type: AccountType.bank,
            initialBalance: 5000,
            currency: 'INR',
            colorValue: 0xFF000000,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 20));
        expect(provider.accounts.length, 1);
        expect(provider.accounts.first.id, 'acc_a');

        // 2. Switch to User B
        await provider.reset(reload: false);
        expect(provider.accounts, isEmpty);

        // 3. User A stream emits late data
        repo.emitAccounts([
          AccountEntity(
            id: 'acc_a_late',
            userId: 'user_a',
            name: 'Late A Bank',
            type: AccountType.bank,
            initialBalance: 9999,
            currency: 'INR',
            colorValue: 0xFF000000,
            iconCodePoint: 0xE000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 20));

        // 4. Stale stream emission ignored
        expect(provider.accounts, isEmpty);

        provider.dispose();
      },
    );

    test(
      'F. Refresh -> stale previous request ignored deterministically',
      () async {
        final repo = FakeTransactionRepository();
        final provider = TransactionProvider(repository: repo);

        final initialTx = TransactionEntity(
          id: 'tx_old',
          userId: 'u1',
          amount: 100,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Old Request',
          date: DateTime.utc(2026, 9, 1),
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        final refreshedTx = TransactionEntity(
          id: 'tx_fresh',
          userId: 'u1',
          amount: 500,
          type: TransactionType.expense,
          categoryId: 'c1',
          accountId: 'a1',
          note: 'Fresh Refreshed Record',
          date: DateTime.utc(2026, 9, 2),
          createdAt: DateTime.utc(2026, 9, 2),
          updatedAt: DateTime.utc(2026, 9, 2),
        );

        final initialCompleter = Completer<List<TransactionEntity>>();

        repo.onGetTransactionsCursor =
            ({
              cursorDate,
              cursorId,
              limit = 50,
              type,
              categoryId,
              accountId,
              startDate,
              endDate,
              minAmount,
              maxAmount,
              searchQuery,
            }) {
              return initialCompleter.future;
            };

        // 1. Initial load starts in-flight
        final initialFuture = provider.loadTransactions();
        await Future.delayed(const Duration(milliseconds: 10));

        // 2. User triggers refresh(), which resolves with refreshedTx
        repo.onGetTransactionsCursor =
            ({
              cursorDate,
              cursorId,
              limit = 50,
              type,
              categoryId,
              accountId,
              startDate,
              endDate,
              minAmount,
              maxAmount,
              searchQuery,
            }) {
              return Future.value([refreshedTx]);
            };

        await provider.refresh();
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_fresh');

        // 3. Stale initial query completes afterward
        initialCompleter.complete([initialTx]);
        await initialFuture;
        await Future.delayed(const Duration(milliseconds: 10));

        // 4. Refreshed state preserved, old stale response ignored!
        expect(provider.transactions.length, 1);
        expect(provider.transactions.first.id, 'tx_fresh');

        provider.dispose();
      },
    );
  });
}
