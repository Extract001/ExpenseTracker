import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/recurring_transaction_entity.dart';
import '../../domain/repositories/i_recurring_transaction_repository.dart';
import '../core/async_value.dart';

class RecurringTransactionProvider extends ChangeNotifier {
  final IRecurringTransactionRepository _repository;

  List<RecurringTransactionEntity> _rules = [];
  AsyncValue<List<RecurringTransactionEntity>> _state =
      const AsyncValue.initial();
  StreamSubscription<List<RecurringTransactionEntity>>? _rulesSubscription;

  int _generation = 0;
  int _streamGeneration = 0;
  bool _isProcessingDue = false;
  int _lastProcessedCount = 0;
  bool _isDisposed = false;

  RecurringTransactionProvider({
    required IRecurringTransactionRepository repository,
  }) : _repository = repository;

  // Getters
  List<RecurringTransactionEntity> get rules => List.unmodifiable(_rules);
  AsyncValue<List<RecurringTransactionEntity>> get state => _state;
  bool get isLoading => _state.isLoading;
  bool get isProcessingDue => _isProcessingDue;
  int get lastProcessedCount => _lastProcessedCount;
  String? get error => _state.errorOrNull;

  List<RecurringTransactionEntity> get activeRules =>
      List.unmodifiable(_rules.where((r) => r.isActive));

  List<RecurringTransactionEntity> get pausedRules =>
      List.unmodifiable(_rules.where((r) => !r.isActive));

  RecurringTransactionEntity? getRuleById(String id) {
    try {
      return _rules.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Subscribes to the live stream of recurring rules with generation guard.
  void watchRules() {
    _streamGeneration++;
    final streamGen = _streamGeneration;

    _rulesSubscription?.cancel();
    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    _rulesSubscription = _repository.watchAllRecurring().listen(
      (list) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        _rules = list;
        _state = AsyncValue.data(list);
        _safeNotifyListeners();
      },
      onError: (err, st) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        AppLogger.error('RECURRING_WATCH_ERROR', error: err);
        _state = AsyncValue.error(
          err is AppException
              ? err.message
              : 'Failed to watch recurring rules.',
          err,
          st,
        );
        _safeNotifyListeners();
      },
    );
  }

  /// One-time fetch of all recurring rules with generation guard.
  Future<void> loadRules() async {
    _generation++;
    final currentGen = _generation;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final list = await _repository.getDueRecurringTransactions(
        DateTime.now().toUtc().add(const Duration(days: 3650)),
      );
      if (currentGen != _generation || _isDisposed) return;

      _rules = list;
      _state = AsyncValue.data(list);
    } on AppException catch (e) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error(e.message, e);
    } catch (e, st) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error('Failed to load recurring rules.', e, st);
    } finally {
      if (currentGen == _generation && !_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Resets provider state, cancels streams, and clears cached rules on user switch.
  Future<void> reset({bool reload = false}) async {
    _generation++;
    _streamGeneration++;
    _rulesSubscription?.cancel();
    _rulesSubscription = null;
    _rules = [];
    _isProcessingDue = false;
    _lastProcessedCount = 0;
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadRules();
    }
  }

  /// Creates a recurring rule.
  Future<void> createRule(RecurringTransactionEntity rule) async {
    try {
      await _repository.createRecurring(rule);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to create recurring rule.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to create recurring rule: $e');
    }
  }

  /// Updates a recurring rule.
  Future<void> updateRule(RecurringTransactionEntity rule) async {
    try {
      await _repository.updateRecurring(rule);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to update recurring rule.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to update recurring rule: $e');
    }
  }

  /// Toggles the active state of a recurring rule.
  Future<void> toggleActive(String id, bool isActive) async {
    try {
      await _repository.toggleActive(id, isActive);
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to toggle recurring rule.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to toggle recurring rule: $e');
    }
  }

  /// Soft deletes a recurring rule.
  Future<void> deleteRule(String id) async {
    try {
      await _repository.softDeleteRecurring(id);
      _rules = _rules.where((r) => r.id != id).toList();
      _safeNotifyListeners();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to delete recurring rule.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to delete recurring rule: $e');
    }
  }

  /// Evaluates and processes all due recurring rules idempotently.
  Future<int> processDueRecurringRules([DateTime? evaluationDateUtc]) async {
    if (_isProcessingDue) return 0;

    _isProcessingDue = true;
    _safeNotifyListeners();

    try {
      final nowUtc = evaluationDateUtc ?? DateTime.now().toUtc();
      final count = await _repository.processDueRecurringRules(nowUtc);
      _lastProcessedCount = count;
      return count;
    } catch (e) {
      AppLogger.error('RECURRING_PROCESS_DUE_ERROR', error: e);
      return 0;
    } finally {
      _isProcessingDue = false;
      _safeNotifyListeners();
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
    _rulesSubscription?.cancel();
    super.dispose();
  }
}
