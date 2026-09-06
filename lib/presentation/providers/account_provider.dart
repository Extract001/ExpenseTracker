import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/account_entity.dart';
import '../../domain/repositories/i_account_repository.dart';
import '../core/async_value.dart';

class AccountProvider extends ChangeNotifier {
  final IAccountRepository _repository;

  List<AccountEntity> _accounts = [];
  int _totalNetWorthMinor = 0;
  AsyncValue<List<AccountEntity>> _state = const AsyncValue.initial();
  StreamSubscription<List<AccountEntity>>? _accountsSubscription;

  int _generation = 0;
  int _streamGeneration = 0;
  bool _isTransferring = false;
  String? _transferError;
  bool _isDisposed = false;

  AccountProvider({required IAccountRepository repository})
    : _repository = repository;

  // Getters
  List<AccountEntity> get accounts => List.unmodifiable(_accounts);
  int get totalNetWorthMinor => _totalNetWorthMinor;
  AsyncValue<List<AccountEntity>> get state => _state;
  bool get isLoading => _state.isLoading;
  bool get isTransferring => _isTransferring;
  String? get transferError => _transferError;
  String? get error => _state.errorOrNull;

  AccountEntity? getAccountById(String id) {
    try {
      return _accounts.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Subscribes to the reactive stream of accounts with generation guard.
  void watchAccounts() {
    _streamGeneration++;
    final streamGen = _streamGeneration;

    _accountsSubscription?.cancel();
    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    _accountsSubscription = _repository.watchAllAccounts().listen(
      (list) async {
        if (streamGen != _streamGeneration || _isDisposed) return;
        _accounts = list;
        _state = AsyncValue.data(list);
        await _refreshNetWorth(streamGen);
        _safeNotifyListeners();
      },
      onError: (err, st) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        AppLogger.error('ACCOUNT_WATCH_ERROR', error: err);
        _state = AsyncValue.error(
          err is AppException ? err.message : 'Failed to watch accounts.',
          err,
          st,
        );
        _safeNotifyListeners();
      },
    );
  }

  /// One-time load of all accounts and total net worth with generation guard.
  Future<void> loadAccounts() async {
    _generation++;
    final currentGen = _generation;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final list = await _repository.getAllAccounts();
      if (currentGen != _generation || _isDisposed) return;

      _accounts = list;
      _state = AsyncValue.data(list);
      await _refreshNetWorth(currentGen);
    } on AppException catch (e) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error(e.message, e);
    } catch (e, st) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error('Failed to load accounts.', e, st);
    } finally {
      if (currentGen == _generation && !_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Resets provider state, cancels streams, and clears cached data on user switch.
  Future<void> reset({bool reload = false}) async {
    _generation++;
    _streamGeneration++;
    _accountsSubscription?.cancel();
    _accountsSubscription = null;
    _accounts = [];
    _totalNetWorthMinor = 0;
    _isTransferring = false;
    _transferError = null;
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadAccounts();
    }
  }

  Future<void> _refreshNetWorth([int? generation]) async {
    try {
      final nw = await _repository.getTotalNetWorth();
      if (generation != null &&
          generation != _generation &&
          generation != _streamGeneration) {
        return;
      }
      if (_isDisposed) return;
      _totalNetWorthMinor = nw;
    } catch (e) {
      AppLogger.error('ACCOUNT_NET_WORTH_ERROR', error: e);
    }
  }

  /// Creates a new account via repository.
  Future<void> createAccount(AccountEntity account) async {
    try {
      await _repository.createAccount(account);
      await _refreshNetWorth();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to create account.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to create account: $e');
    }
  }

  /// Updates an account via repository.
  Future<void> updateAccount(AccountEntity account) async {
    try {
      await _repository.updateAccount(account);
      await _refreshNetWorth();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to update account.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to update account: $e');
    }
  }

  /// Soft deletes an account via repository.
  Future<void> deleteAccount(String id) async {
    try {
      await _repository.softDeleteAccount(id);
      _accounts = _accounts.where((a) => a.id != id).toList();
      await _refreshNetWorth();
      _safeNotifyListeners();
    } on AppException catch (e) {
      _state = AsyncValue.error(e.message, e);
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _state = const AsyncValue.error('Failed to delete account.');
      _safeNotifyListeners();
      throw DatabaseException('Failed to delete account: $e');
    }
  }

  /// Performs atomic fund transfer between two accounts via repository.
  Future<void> transferFunds({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    DateTime? date,
  }) async {
    if (_isTransferring) return;

    _isTransferring = true;
    _transferError = null;
    _safeNotifyListeners();

    try {
      await _repository.transferFunds(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amountMinor: amountMinor,
        note: note,
        date: date,
      );
      await _refreshNetWorth();
    } on AppException catch (e) {
      _transferError = e.message;
      _safeNotifyListeners();
      rethrow;
    } catch (e) {
      _transferError = 'Transfer failed. Please check account details.';
      _safeNotifyListeners();
      throw DatabaseException(_transferError!);
    } finally {
      _isTransferring = false;
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
    _accountsSubscription?.cancel();
    super.dispose();
  }
}
