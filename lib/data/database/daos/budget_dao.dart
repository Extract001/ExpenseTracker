import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/budgets_table.dart';
import '../tables/category_budgets_table.dart';
import '../tables/transactions_table.dart';

part 'budget_dao.g.dart';

@DriftAccessor(tables: [BudgetsTable, CategoryBudgetsTable, TransactionsTable])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Stream<BudgetData?> watchMonthlyBudget({
    required String userId,
    required String monthYear,
  }) {
    return (select(budgetsTable)..where(
          (b) =>
              b.userId.equals(userId) &
              b.monthYear.equals(monthYear) &
              b.deletedAtUtc.isNull(),
        ))
        .watchSingleOrNull();
  }

  Future<BudgetData?> getMonthlyBudget({
    required String userId,
    required String monthYear,
  }) {
    return (select(budgetsTable)..where(
          (b) =>
              b.userId.equals(userId) &
              b.monthYear.equals(monthYear) &
              b.deletedAtUtc.isNull(),
        ))
        .getSingleOrNull();
  }

  Future<int> upsertMonthlyBudget(BudgetsTableCompanion entry) {
    return into(budgetsTable).insertOnConflictUpdate(entry);
  }

  Stream<List<CategoryBudgetData>> watchCategoryBudgets({
    required String userId,
    required String budgetId,
  }) {
    return (select(categoryBudgetsTable)..where(
          (cb) =>
              cb.userId.equals(userId) &
              cb.budgetId.equals(budgetId) &
              cb.deletedAtUtc.isNull(),
        ))
        .watch();
  }

  Future<List<CategoryBudgetData>> getCategoryBudgets({
    required String userId,
    required String budgetId,
  }) {
    return (select(categoryBudgetsTable)..where(
          (cb) =>
              cb.userId.equals(userId) &
              cb.budgetId.equals(budgetId) &
              cb.deletedAtUtc.isNull(),
        ))
        .get();
  }

  Future<int> upsertCategoryBudget(CategoryBudgetsTableCompanion entry) {
    return into(categoryBudgetsTable).insertOnConflictUpdate(entry);
  }

  /// Calculates total expenses for a specific category within a UTC date range.
  Future<int> getSpentAmountForCategory({
    required String userId,
    required String categoryId,
    required DateTime startDateUtc,
    required DateTime endDateUtc,
  }) async {
    final amountSum = transactionsTable.amountMinor.sum();
    final query = selectOnly(transactionsTable)
      ..addColumns([amountSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.categoryId.equals(categoryId) &
            transactionsTable.transactionType.equals('expense') &
            transactionsTable.deletedAtUtc.isNull() &
            transactionsTable.transactionDateUtc.isBiggerOrEqualValue(
              startDateUtc,
            ) &
            transactionsTable.transactionDateUtc.isSmallerOrEqualValue(
              endDateUtc,
            ),
      );

    final result = await query.map((r) => r.read(amountSum)).getSingleOrNull();
    return result ?? 0;
  }
}
