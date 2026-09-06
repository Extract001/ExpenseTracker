import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/date_time_utils.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/i_transaction_repository.dart';

@immutable
class TransactionFilterState {
  final TransactionType? type;
  final String? categoryId;
  final String? accountId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? minAmount;
  final int? maxAmount;
  final String? searchQuery;

  const TransactionFilterState({
    this.type,
    this.categoryId,
    this.accountId,
    this.startDate,
    this.endDate,
    this.minAmount,
    this.maxAmount,
    this.searchQuery,
  });

  bool get hasActiveFilters =>
      type != null ||
      categoryId != null ||
      accountId != null ||
      startDate != null ||
      endDate != null ||
      minAmount != null ||
      maxAmount != null ||
      (searchQuery != null && searchQuery!.trim().isNotEmpty);

  TransactionFilterState copyWith({
    TransactionType? type,
    bool clearType = false,
    String? categoryId,
    bool clearCategory = false,
    String? accountId,
    bool clearAccount = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
    int? minAmount,
    bool clearMinAmount = false,
    int? maxAmount,
    bool clearMaxAmount = false,
    String? searchQuery,
    bool clearSearchQuery = false,
  }) {
    return TransactionFilterState(
      type: clearType ? null : (type ?? this.type),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      accountId: clearAccount ? null : (accountId ?? this.accountId),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      minAmount: clearMinAmount ? null : (minAmount ?? this.minAmount),
      maxAmount: clearMaxAmount ? null : (maxAmount ?? this.maxAmount),
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
    );
  }

  TransactionFilterState clear() => const TransactionFilterState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionFilterState &&
          other.type == type &&
          other.categoryId == categoryId &&
          other.accountId == accountId &&
          other.startDate == startDate &&
          other.endDate == endDate &&
          other.minAmount == minAmount &&
          other.maxAmount == maxAmount &&
          other.searchQuery == searchQuery;

  @override
  int get hashCode => Object.hash(
    type,
    categoryId,
    accountId,
    startDate,
    endDate,
    minAmount,
    maxAmount,
    searchQuery,
  );
}

class TransactionProvider extends ChangeNotifier {
  final ITransactionRepository _repository;

  // Pagination & List State
  List<TransactionEntity> _transactions = [];
  DateTime? _cursorDate;
  String? _cursorId;
  bool _hasMore = true;
  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;
  String? _error;

  // Recent stream state
  List<TransactionEntity> _recentTransactions = [];
  StreamSubscription<List<TransactionEntity>>? _recentTxSubscription;

  // Aggregates
  int _totalIncomeMinor = 0;
  int _totalExpenseMinor = 0;
  bool _isLoadingTotals = false;

  // Filter & Search
  TransactionFilterState _filter = const TransactionFilterState();
  Timer? _searchDebounce;
  int _queryGeneration = 0;
  int _totalsGeneration = 0;
  int _streamGeneration = 0;
  final int _pageSize;

  bool _isDisposed = false;

  TransactionProvider({
    required ITransactionRepository repository,
    int pageSize = 50,
  }) : _repository = repository,
       _pageSize = pageSize;

  // Getters
  List<TransactionEntity> get transactions => List.unmodifiable(_transactions);
  List<TransactionEntity> get recentTransactions =>
      List.unmodifiable(_recentTransactions);
  TransactionFilterState get filter => _filter;
  bool get hasMore => _hasMore;
  bool get isLoadingInitial => _isLoadingInitial;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoading => _isLoadingInitial || _isLoadingMore;
  String? get error => _error;
  int get totalIncomeMinor => _totalIncomeMinor;
  int get totalExpenseMinor => _totalExpenseMinor;
  int get netSavingsMinor => _totalIncomeMinor - _totalExpenseMinor;
  bool get isLoadingTotals => _isLoadingTotals;

  /// Subscribes to the live stream of recent transactions with generation guard.
  void watchRecentTransactions({int limit = 20}) {
    _streamGeneration++;
    final currentGen = _streamGeneration;

    _recentTxSubscription?.cancel();
    _recentTxSubscription = _repository
        .watchRecentTransactions(limit: limit)
        .listen(
          (recent) {
            if (currentGen != _streamGeneration || _isDisposed) return;
            _recentTransactions = recent;
            _safeNotifyListeners();
          },
          onError: (err) {
            if (currentGen != _streamGeneration || _isDisposed) return;
            AppLogger.error('TRANSACTION_WATCH_RECENT_ERROR', error: err);
          },
        );
  }

  /// Initial load or reload of transactions under current filter state.
  Future<void> loadTransactions() async {
    _queryGeneration++;
    final currentGen = _queryGeneration;

    _isLoadingInitial = true;
    _isLoadingMore = false;
    _error = null;
    _cursorDate = null;
    _cursorId = null;
    _hasMore = true;
    _safeNotifyListeners();

    try {
      final items = await _repository.getTransactionsCursor(
        limit: _pageSize,
        type: _filter.type,
        categoryId: _filter.categoryId,
        accountId: _filter.accountId,
        startDate: _filter.startDate,
        endDate: _filter.endDate,
        minAmount: _filter.minAmount,
        maxAmount: _filter.maxAmount,
        searchQuery: _filter.searchQuery,
      );

      // Stale response guard
      if (currentGen != _queryGeneration || _isDisposed) return;

      _transactions = items;
      if (items.isNotEmpty) {
        _cursorDate = items.last.date;
        _cursorId = items.last.id;
        _hasMore = items.length >= _pageSize;
      } else {
        _hasMore = false;
      }
      _error = null;
    } on AppException catch (e) {
      if (currentGen != _queryGeneration || _isDisposed) return;
      _error = e.message;
    } catch (e) {
      if (currentGen != _queryGeneration || _isDisposed) return;
      _error = 'Failed to load transactions. Please try again.';
    } finally {
      if (currentGen == _queryGeneration && !_isDisposed) {
        _isLoadingInitial = false;
        _safeNotifyListeners();
      }
    }
  }

  /// Keyset pagination: Loads next page of transactions without duplicate concurrent fetches.
  Future<void> loadMore() async {
    if (_isLoadingMore || _isLoadingInitial || !_hasMore) return;

    final currentGen = _queryGeneration;
    _isLoadingMore = true;
    _safeNotifyListeners();

    try {
      final items = await _repository.getTransactionsCursor(
        cursorDate: _cursorDate,
        cursorId: _cursorId,
        limit: _pageSize,
        type: _filter.type,
        categoryId: _filter.categoryId,
        accountId: _filter.accountId,
        startDate: _filter.startDate,
        endDate: _filter.endDate,
        minAmount: _filter.minAmount,
        maxAmount: _filter.maxAmount,
        searchQuery: _filter.searchQuery,
      );

      // Stale request guard
      if (currentGen != _queryGeneration || _isDisposed) return;

      if (items.isNotEmpty) {
        _transactions = [..._transactions, ...items];
        _cursorDate = items.last.date;
        _cursorId = items.last.id;
        _hasMore = items.length >= _pageSize;
      } else {
        _hasMore = false;
      }
    } on AppException catch (e) {
      if (currentGen != _queryGeneration || _isDisposed) return;
      _error = e.message;
    } catch (e) {
      if (currentGen != _queryGeneration || _isDisposed) return;
      _error = 'Failed to load more transactions.';
    } finally {
      if (currentGen == _queryGeneration && !_isDisposed) {
        _isLoadingMore = false;
        _safeNotifyListeners();
      }
    }
  }

  /// Refreshes the transactions list from scratch.
  Future<void> refresh() => loadTransactions();

  /// Resets provider state, invalidates all in-flight queries, cancels active streams, and optionally reloads for a new user context.
  Future<void> reset({bool reload = false}) async {
    _queryGeneration++;
    _totalsGeneration++;
    _streamGeneration++;
    _searchDebounce?.cancel();
    _recentTxSubscription?.cancel();
    _recentTxSubscription = null;

    _transactions = [];
    _recentTransactions = [];
    _cursorDate = null;
    _cursorId = null;
    _hasMore = true;
    _isLoadingInitial = false;
    _isLoadingMore = false;
    _isLoadingTotals = false;
    _error = null;
    _totalIncomeMinor = 0;
    _totalExpenseMinor = 0;
    _filter = const TransactionFilterState();

    _safeNotifyListeners();

    if (reload) {
      await loadTransactions();
      await loadTotals();
    }
  }

  /// Updates the full filter state and reloads results database-side.
  void setFilter(TransactionFilterState newFilter) {
    if (_filter == newFilter) return;
    _filter = newFilter;
    loadTransactions();
  }

  /// Partially updates filter parameters.
  void updateFilter({
    TransactionType? type,
    bool clearType = false,
    String? categoryId,
    bool clearCategory = false,
    String? accountId,
    bool clearAccount = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
    int? minAmount,
    bool clearMinAmount = false,
    int? maxAmount,
    bool clearMaxAmount = false,
    String? searchQuery,
    bool clearSearchQuery = false,
  }) {
    final updated = _filter.copyWith(
      type: type,
      clearType: clearType,
      categoryId: categoryId,
      clearCategory: clearCategory,
      accountId: accountId,
      clearAccount: clearAccount,
      startDate: startDate,
      clearStartDate: clearStartDate,
      endDate: endDate,
      clearEndDate: clearEndDate,
      minAmount: minAmount,
      clearMinAmount: clearMinAmount,
      maxAmount: maxAmount,
      clearMaxAmount: clearMaxAmount,
      searchQuery: searchQuery,
      clearSearchQuery: clearSearchQuery,
    );
    setFilter(updated);
  }

  /// Resets filter to default empty state and reloads.
  void resetFilter() {
    if (!_filter.hasActiveFilters) return;
    _filter = const TransactionFilterState();
    loadTransactions();
  }

  /// Clears active search immediately, cancels pending debounce timers, invalidates in-flight search queries, and reloads base transactions.
  void clearSearch() {
    _searchDebounce?.cancel();
    if (_filter.searchQuery != null) {
      _filter = _filter.copyWith(clearSearchQuery: true);
      loadTransactions();
    }
  }

  /// Debounced search query update with stale request token protection.
  void setSearchQuery(
    String query, {
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    _searchDebounce?.cancel();
    final trimmed = query.trim().isEmpty ? null : query.trim();
    if (trimmed == null) {
      clearSearch();
      return;
    }
    _searchDebounce = Timer(debounce, () {
      if (_filter.searchQuery != trimmed) {
        _filter = _filter.copyWith(searchQuery: trimmed);
        loadTransactions();
      }
    });
  }

  /// Loads aggregated totals (income and expenses) for a date period with generation guard.
  Future<void> loadTotals({
    DateTime? startDateUtc,
    DateTime? endDateUtc,
  }) async {
    _totalsGeneration++;
    final currentGen = _totalsGeneration;

    final start =
        startDateUtc ??
        _filter.startDate ??
        DateTimeUtils.startOfMonthUtc(DateTime.now().toUtc());
    final end =
        endDateUtc ??
        _filter.endDate ??
        DateTimeUtils.endOfMonthUtc(DateTime.now().toUtc());

    _isLoadingTotals = true;
    _safeNotifyListeners();

    try {
      final income = await _repository.getTotalIncome(start, end);
      final expense = await _repository.getTotalExpense(start, end);
      if (currentGen != _totalsGeneration || _isDisposed) return;
      _totalIncomeMinor = income;
      _totalExpenseMinor = expense;
    } catch (e) {
      if (currentGen != _totalsGeneration || _isDisposed) return;
      AppLogger.error('TRANSACTION_LOAD_TOTALS_ERROR', error: e);
    } finally {
      if (currentGen == _totalsGeneration && !_isDisposed) {
        _isLoadingTotals = false;
        _safeNotifyListeners();
      }
    }
  }

  /// Creates a new transaction via repository.
  Future<void> createTransaction(TransactionEntity transaction) async {
    try {
      await _repository.createTransaction(transaction);
      await refresh();
      await loadTotals();
    } on AppException catch (e) {
      _error = e.message;
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _error = 'Failed to create transaction.';
      _safeNotifyListeners();
      throw DatabaseException(_error!);
    }
  }

  /// Updates an existing transaction via repository.
  Future<void> updateTransaction(TransactionEntity transaction) async {
    try {
      await _repository.updateTransaction(transaction);
      await refresh();
      await loadTotals();
    } on AppException catch (e) {
      _error = e.message;
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _error = 'Failed to update transaction.';
      _safeNotifyListeners();
      throw DatabaseException(_error!);
    }
  }

  /// Soft deletes a transaction via repository.
  Future<void> deleteTransaction(String id) async {
    try {
      await _repository.softDeleteTransaction(id);
      _transactions = _transactions.where((t) => t.id != id).toList();
      _recentTransactions = _recentTransactions
          .where((t) => t.id != id)
          .toList();
      _safeNotifyListeners();
      await loadTotals();
    } on AppException catch (e) {
      _error = e.message;
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _error = 'Failed to delete transaction.';
      _safeNotifyListeners();
      throw DatabaseException(_error!);
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
    _searchDebounce?.cancel();
    _recentTxSubscription?.cancel();
    super.dispose();
  }
}
