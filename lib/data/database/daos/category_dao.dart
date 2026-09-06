import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/categories_table.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [CategoriesTable])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Stream<List<CategoryData>> watchCategories({
    required String userId,
    String? type,
    bool includeArchived = false,
  }) {
    final query = select(categoriesTable)
      ..where((c) => c.userId.equals(userId) & c.deletedAtUtc.isNull());

    if (!includeArchived) {
      query.where((c) => c.isArchived.equals(false));
    }

    if (type != null) {
      query.where((c) => c.type.equals(type));
    }

    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch();
  }

  Future<List<CategoryData>> getAllCategories({
    required String userId,
    String? type,
    bool includeArchived = false,
  }) {
    final query = select(categoriesTable)
      ..where((c) => c.userId.equals(userId) & c.deletedAtUtc.isNull());

    if (!includeArchived) {
      query.where((c) => c.isArchived.equals(false));
    }

    if (type != null) {
      query.where((c) => c.type.equals(type));
    }

    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.get();
  }

  Future<CategoryData?> getCategoryById(String id) {
    return (select(
      categoriesTable,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertCategory(CategoriesTableCompanion entry) {
    return into(categoriesTable).insert(entry);
  }

  Future<bool> updateCategory(CategoriesTableCompanion entry) {
    return update(categoriesTable).replace(entry);
  }

  Future<int> archiveCategory({
    required String id,
    required bool isArchived,
    required DateTime updatedAtUtc,
    String syncStatus = 'pendingUpdate',
  }) {
    return (update(categoriesTable)..where((c) => c.id.equals(id))).write(
      CategoriesTableCompanion(
        isArchived: Value(isArchived),
        updatedAtUtc: Value(updatedAtUtc),
        syncStatus: Value(syncStatus),
      ),
    );
  }

  Future<int> softDeleteCategory({
    required String id,
    required DateTime deletedAtUtc,
    String syncStatus = 'pendingDelete',
  }) {
    return (update(categoriesTable)..where((c) => c.id.equals(id))).write(
      CategoriesTableCompanion(
        deletedAtUtc: Value(deletedAtUtc),
        updatedAtUtc: Value(deletedAtUtc),
        syncStatus: Value(syncStatus),
      ),
    );
  }
}
