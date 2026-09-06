import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/i_budget_repository.dart';
import '../core/async_value.dart';

class BudgetProvider extends ChangeNotifier {
  final IBudgetRepository _repository;

  String _selectedMonthYear;
  BudgetEntity? _monthlyBudget;
  List<CategoryBudgetEntity> _categoryBudgets = [];
  int _totalSpentMinor = 0;
  final Map<String, int> _categorySpentMap = {};

  AsyncValue<BudgetEntity?> _state = const AsyncValue.initial();
  StreamSubscription<BudgetEntity?>? _monthlyBudgetSub;
  StreamSubscription<List<CategoryBudgetEntity>>? _categoryBudgetsSub;

  int _monthGeneration = 0;
  bool _isDisposed = false;

  BudgetProvider({
    required IBudgetRepository repository,
    String? initialMonthYear,
  }) : _repository = repository,
       _selectedMonthYear =
           initialMonthYear ?? DateTimeUtils.toMonthKey(DateTime.now().toUtc());

  // Getters
  String get selectedMonthYear => _selectedMonthYear;
  BudgetEntity? get monthlyBudget => _monthlyBudget;
  List<CategoryBudgetEntity> get categoryBudgets =>
      List.unmodifiable(_categoryBudgets);
  int get totalBudgetLimitMinor => _monthlyBudget?.amount ?? 0;
  int get totalSpentMinor => _totalSpentMinor;
  int get remainingBudgetMinor => (totalBudgetLimitMinor - _totalSpentMinor)
      .clamp(0, totalBudgetLimitMinor);
  double get budgetProgressPercentage {
    if (totalBudgetLimitMinor <= 0) return 0.0;
    final pct = (_totalSpentMinor / totalBudgetLimitMinor) * 100.0;
    return pct.clamp(0.0, 100.0);
  }

  bool get isOverBudget =>
      totalBudgetLimitMinor > 0 && _totalSpentMinor > totalBudgetLimitMinor;

  Map<String, int> get categorySpentMap => Map.unmodifiable(_categorySpentMap);
  AsyncValue<BudgetEntity?> get state => _state;
  bool get isLoading => _state.isLoading;
  String? get error => _state.errorOrNull;

  int getSpentForCategory(String categoryId) =>
      _categorySpentMap[categoryId] ?? 0;

  /// Changes the active month and reloads all budget data with concurrency / stale protection.
  void setSelectedMonth(String monthYear) {
    if (_selectedMonthYear == monthYear) return;
    _selectedMonthYear = monthYear;
    loadBudgetForSelectedMonth();
  }

  /// Subscribes to live budget updates for the selected month.
  void watchBudgetForSelectedMonth() {
    _monthGeneration++;
    final currentGen = _monthGeneration;

    _monthlyBudgetSub?.cancel();
    _categoryBudgetsSub?.cancel();
    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    _monthlyBudgetSub = _repository
        .watchMonthlyBudget(_selectedMonthYear)
        .listen(
          (budget) async {
            if (currentGen != _monthGeneration) return;
            _monthlyBudget = budget;
            _state = AsyncValue.data(budget);

            if (budget != null) {
              _watchCategoryBudgets(budget.id, currentGen);
            } else {
              _categoryBudgets = [];
              _categorySpentMap.clear();
            }

            await _refreshSpentData(currentGen);
            _safeNotifyListeners();
          },
          onError: (err, st) {
            if (currentGen != _monthGeneration) return;
            AppLogger.error('BUDGET_WATCH_ERROR', error: err);
            _state = AsyncValue.error(
              err is AppException ? err.message : 'Failed to watch budget.',
              err,
              st,
            );
            _safeNotifyListeners();
          },
        );
  }

  void _watchCategoryBudgets(String budgetId, int generation) {
    _categoryBudgetsSub?.cancel();
    _categoryBudgetsSub = _repository.watchCategoryBudgets(budgetId).listen((
      categoryBudgets,
    ) {
      if (generation != _monthGeneration) return;
      _categoryBudgets = categoryBudgets;
      _safeNotifyListeners();
    });
  }

  /// One-time fetch of budget details and aggregated spending.
  Future<void> loadBudgetForSelectedMonth() async {
    _monthGeneration++;
    final currentGen = _monthGeneration;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final budget = await _repository.getMonthlyBudget(_selectedMonthYear);
      if (currentGen != _monthGeneration) return;

      _monthlyBudget = budget;
      _state = AsyncValue.data(budget);
      await _refreshSpentData(currentGen);
    } on AppException catch (e) {
      if (currentGen != _monthGeneration) return;
      _state = AsyncValue.error(e.message, e);
    } catch (e, st) {
      if (currentGen != _monthGeneration) return;
      _state = AsyncValue.error('Failed to load budget.', e, st);
    } finally {
      if (currentGen == _monthGeneration) {
        _safeNotifyListeners();
      }
    }
  }

  Future<void> _refreshSpentData(int generation) async {
    try {
      final spent = await _repository.getSpentAmountForMonth(
        _selectedMonthYear,
      );
      if (generation != _monthGeneration) return;
      _totalSpentMinor = spent;

      // Refresh category spent amounts for configured category budgets
      for (final cb in _categoryBudgets) {
        final catSpent = await _repository.getSpentAmountForCategory(
          cb.categoryId,
          _selectedMonthYear,
        );
        if (generation != _monthGeneration) return;
        _categorySpentMap[cb.categoryId] = catSpent;
      }
    } catch (e) {
      AppLogger.error('BUDGET_REFRESH_SPENT_ERROR', error: e);
    }
  }

  /// Resets provider state, cancels streams, and clears cached budgets on user switch.
  Future<void> reset({bool reload = false}) async {
    _monthGeneration++;
    _monthlyBudgetSub?.cancel();
    _monthlyBudgetSub = null;
    _categoryBudgetsSub?.cancel();
    _categoryBudgetsSub = null;

    _monthlyBudget = null;
    _categoryBudgets = [];
    _totalSpentMinor = 0;
    _categorySpentMap.clear();
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadBudgetForSelectedMonth();
    }
  }

  /// Sets or updates monthly budget limit for the selected month.
  Future<void> setMonthlyBudget({
    required int amountMinor,
    String? currency,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final existingId = _monthlyBudget?.id ?? IdGenerator.uuid();

    final entity = BudgetEntity(
      id: existingId,
      userId: _monthlyBudget?.userId ?? '',
      monthYear: _selectedMonthYear,
      amount: amountMinor,
      createdAt: _monthlyBudget?.createdAt ?? nowUtc,
      updatedAt: nowUtc,
    );

    try {
      await _repository.setMonthlyBudget(entity);
      await loadBudgetForSelectedMonth();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to set monthly budget.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to set monthly budget: $e');
    }
  }

  /// Sets or updates a specific category budget limit.
  Future<void> setCategoryBudget({
    required String categoryId,
    required int limitAmountMinor,
  }) async {
    if (_monthlyBudget == null) {
      throw const ValidationException('Monthly budget must be created first');
    }

    final nowUtc = DateTime.now().toUtc();
    final cb = CategoryBudgetEntity(
      id: IdGenerator.uuid(),
      userId: _monthlyBudget!.userId,
      budgetId: _monthlyBudget!.id,
      categoryId: categoryId,
      amount: limitAmountMinor,
      createdAt: nowUtc,
      updatedAt: nowUtc,
    );

    try {
      await _repository.setCategoryBudget(cb);
      await loadBudgetForSelectedMonth();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to set category budget.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to set category budget: $e');
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
    _monthlyBudgetSub?.cancel();
    _categoryBudgetsSub?.cancel();
    super.dispose();
  }
}
