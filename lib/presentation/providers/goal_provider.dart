import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/goal_entity.dart';
import '../../domain/repositories/i_goal_repository.dart';
import '../core/async_value.dart';

class GoalProvider extends ChangeNotifier {
  final IGoalRepository _repository;

  List<GoalEntity> _goals = [];
  GoalEntity? _selectedGoal;
  AsyncValue<List<GoalEntity>> _state = const AsyncValue.initial();
  StreamSubscription<List<GoalEntity>>? _goalsSubscription;

  int _generation = 0;
  int _streamGeneration = 0;
  bool _isDisposed = false;

  GoalProvider({required IGoalRepository repository})
    : _repository = repository;

  // Getters
  List<GoalEntity> get goals => List.unmodifiable(_goals);
  GoalEntity? get selectedGoal => _selectedGoal;
  AsyncValue<List<GoalEntity>> get state => _state;
  bool get isLoading => _state.isLoading;
  String? get error => _state.errorOrNull;

  List<GoalEntity> get activeGoals =>
      List.unmodifiable(_goals.where((g) => !g.isCompleted));

  List<GoalEntity> get completedGoals =>
      List.unmodifiable(_goals.where((g) => g.isCompleted));

  int get totalSavedMinor =>
      _goals.fold<int>(0, (sum, g) => sum + g.currentAmount);

  int get totalTargetMinor =>
      _goals.fold<int>(0, (sum, g) => sum + g.targetAmount);

  void selectGoal(String? id) {
    if (id == null) {
      _selectedGoal = null;
    } else {
      try {
        _selectedGoal = _goals.firstWhere((g) => g.id == id);
      } catch (_) {
        _selectedGoal = null;
      }
    }
    _safeNotifyListeners();
  }

  /// Subscribes to the live goal stream from repository with generation guard.
  void watchGoals() {
    _streamGeneration++;
    final streamGen = _streamGeneration;

    _goalsSubscription?.cancel();
    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    _goalsSubscription = _repository.watchAllGoals().listen(
      (list) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        _goals = list;
        _state = AsyncValue.data(list);
        if (_selectedGoal != null) {
          try {
            _selectedGoal = list.firstWhere((g) => g.id == _selectedGoal!.id);
          } catch (_) {
            _selectedGoal = null;
          }
        }
        _safeNotifyListeners();
      },
      onError: (err, st) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        AppLogger.error('GOAL_WATCH_ERROR', error: err);
        _state = AsyncValue.error(
          err is AppException ? err.message : 'Failed to watch savings goals.',
          err,
          st,
        );
        _safeNotifyListeners();
      },
    );
  }

  /// One-time fetch of all savings goals with generation guard.
  Future<void> loadGoals() async {
    _generation++;
    final currentGen = _generation;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final list = await _repository.getAllGoals();
      if (currentGen != _generation || _isDisposed) return;

      _goals = list;
      _state = AsyncValue.data(list);
    } on AppException catch (e) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error(e.message, e);
    } catch (e, st) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error('Failed to load savings goals.', e, st);
    } finally {
      if (currentGen == _generation && !_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Resets provider state, cancels streams, and clears cached goals on user switch.
  Future<void> reset({bool reload = false}) async {
    _generation++;
    _streamGeneration++;
    _goalsSubscription?.cancel();
    _goalsSubscription = null;
    _goals = [];
    _selectedGoal = null;
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadGoals();
    }
  }

  /// Creates a new savings goal.
  Future<void> createGoal(GoalEntity goal) async {
    try {
      await _repository.createGoal(goal);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to create goal.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to create goal: $e');
    }
  }

  /// Updates an existing savings goal.
  Future<void> updateGoal(GoalEntity goal) async {
    try {
      await _repository.updateGoal(goal);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to update goal.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to update goal: $e');
    }
  }

  /// Adds progress towards a goal via repository.
  Future<void> addProgress(String id, int amountMinor) async {
    try {
      await _repository.addProgress(id, amountMinor);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to add goal progress.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to add goal progress: $e');
    }
  }

  /// Soft deletes a savings goal.
  Future<void> deleteGoal(String id) async {
    try {
      await _repository.softDeleteGoal(id);
      _goals = _goals.where((g) => g.id != id).toList();
      if (_selectedGoal?.id == id) {
        _selectedGoal = null;
      }
      _safeNotifyListeners();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to delete goal.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to delete goal: $e');
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
    _goalsSubscription?.cancel();
    super.dispose();
  }
}
