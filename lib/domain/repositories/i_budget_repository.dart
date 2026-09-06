import '../entities/budget_entity.dart';

abstract class IBudgetRepository {
  Stream<BudgetEntity?> watchMonthlyBudget(String monthYear);
  Stream<List<CategoryBudgetEntity>> watchCategoryBudgets(String budgetId);
  Future<BudgetEntity?> getMonthlyBudget(String monthYear);
  Future<void> setMonthlyBudget(BudgetEntity budget);
  Future<void> setCategoryBudget(CategoryBudgetEntity categoryBudget);
  Future<int> getSpentAmountForMonth(String monthYear);
  Future<int> getSpentAmountForCategory(String categoryId, String monthYear);
}
