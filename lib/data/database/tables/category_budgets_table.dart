import 'package:drift/drift.dart';
import 'budgets_table.dart';
import 'categories_table.dart';

@DataClassName('CategoryBudgetData')
@TableIndex(
  name: 'idx_cat_budgets_user',
  columns: {#userId, #budgetId, #categoryId, #deletedAtUtc},
)
class CategoryBudgetsTable extends Table {
  @override
  String get tableName => 'category_budgets';

  TextColumn get id => text()(); // UUID
  TextColumn get userId => text()();
  TextColumn get budgetId =>
      text().references(BudgetsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId => text().references(CategoriesTable, #id)();
  IntColumn get amountMinor => integer()(); // minor units
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();
  DateTimeColumn get deletedAtUtc => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pendingCreate'))();
  TextColumn get fieldTimestampsJson =>
      text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
