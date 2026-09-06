import '../entities/category_entity.dart';
import '../entities/enums.dart';

abstract class ICategoryRepository {
  Stream<List<CategoryEntity>> watchCategories({TransactionType? type});
  Future<List<CategoryEntity>> getAllCategories({TransactionType? type});
  Future<CategoryEntity?> getCategoryById(String id);
  Future<void> createCategory(CategoryEntity category);
  Future<void> updateCategory(CategoryEntity category);
  Future<void> archiveCategory(String id);
  Future<void> softDeleteCategory(String id);
}
