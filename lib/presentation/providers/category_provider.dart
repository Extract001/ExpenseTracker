import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/enums.dart';
import '../../domain/repositories/i_category_repository.dart';
import '../core/async_value.dart';

class CategoryProvider extends ChangeNotifier {
  final ICategoryRepository _repository;

  List<CategoryEntity> _categories = [];
  AsyncValue<List<CategoryEntity>> _state = const AsyncValue.initial();
  StreamSubscription<List<CategoryEntity>>? _categoriesSubscription;

  int _generation = 0;
  int _streamGeneration = 0;
  bool _isDisposed = false;

  CategoryProvider({required ICategoryRepository repository})
    : _repository = repository;

  // Getters
  List<CategoryEntity> get categories => List.unmodifiable(_categories);
  AsyncValue<List<CategoryEntity>> get state => _state;
  bool get isLoading => _state.isLoading;
  String? get error => _state.errorOrNull;

  List<CategoryEntity> get activeCategories =>
      List.unmodifiable(_categories.where((c) => !c.isArchived));

  List<CategoryEntity> get archivedCategories =>
      List.unmodifiable(_categories.where((c) => c.isArchived));

  List<CategoryEntity> get incomeCategories => List.unmodifiable(
    _categories.where((c) => c.type == TransactionType.income && !c.isArchived),
  );

  List<CategoryEntity> get expenseCategories => List.unmodifiable(
    _categories.where(
      (c) => c.type == TransactionType.expense && !c.isArchived,
    ),
  );

  List<CategoryEntity> get systemCategories =>
      List.unmodifiable(_categories.where((c) => c.isSystem));

  List<CategoryEntity> get customCategories =>
      List.unmodifiable(_categories.where((c) => !c.isSystem));

  CategoryEntity? getCategoryById(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Subscribes to the live category stream from the repository with generation guard.
  void watchCategories({TransactionType? type}) {
    _streamGeneration++;
    final streamGen = _streamGeneration;

    _categoriesSubscription?.cancel();
    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    _categoriesSubscription = _repository
        .watchCategories(type: type)
        .listen(
          (list) {
            if (streamGen != _streamGeneration || _isDisposed) return;
            _categories = list;
            _state = AsyncValue.data(list);
            _safeNotifyListeners();
          },
          onError: (err, st) {
            if (streamGen != _streamGeneration || _isDisposed) return;
            AppLogger.error('CATEGORY_WATCH_ERROR', error: err);
            _state = AsyncValue.error(
              err is AppException ? err.message : 'Failed to watch categories.',
              err,
              st,
            );
            _safeNotifyListeners();
          },
        );
  }

  /// One-time fetch of categories with generation guard.
  Future<void> loadCategories({TransactionType? type}) async {
    _generation++;
    final currentGen = _generation;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final list = await _repository.getAllCategories(type: type);
      if (currentGen != _generation || _isDisposed) return;

      _categories = list;
      _state = AsyncValue.data(list);
    } on AppException catch (e) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error(e.message, e);
    } catch (e, st) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error('Failed to load categories.', e, st);
    } finally {
      if (currentGen == _generation && !_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Resets provider state and clears cached categories on user switch.
  Future<void> reset({bool reload = false}) async {
    _generation++;
    _streamGeneration++;
    _categoriesSubscription?.cancel();
    _categoriesSubscription = null;
    _categories = [];
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadCategories();
    }
  }

  /// Creates a new custom category.
  Future<void> createCategory(CategoryEntity category) async {
    try {
      await _repository.createCategory(category);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to create category.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to create category: $e');
    }
  }

  /// Updates a category.
  Future<void> updateCategory(CategoryEntity category) async {
    try {
      await _repository.updateCategory(category);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to update category.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to update category: $e');
    }
  }

  /// Archives a category.
  Future<void> archiveCategory(String id) async {
    try {
      await _repository.archiveCategory(id);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to archive category.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to archive category: $e');
    }
  }

  /// Soft deletes a custom category.
  Future<void> deleteCategory(String id) async {
    try {
      await _repository.softDeleteCategory(id);
      _categories = _categories.where((c) => c.id != id).toList();
      _safeNotifyListeners();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to delete category.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to delete category: $e');
    }
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _categoriesSubscription?.cancel();
    super.dispose();
  }
}
