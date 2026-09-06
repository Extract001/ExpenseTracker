import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/sync/i_sync_coordinator.dart';
import '../../core/sync/sync_types.dart';
import '../../domain/entities/sync_operation_entity.dart';
import '../../domain/repositories/i_sync_repository.dart';
import '../core/async_value.dart';

class SyncProvider extends ChangeNotifier {
  final ISyncRepository _repository;
  final ISyncCoordinator? _syncCoordinator;

  int _pendingCount = 0;
  List<SyncOperationEntity> _pendingOperations = [];
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _lastError;
  SyncEngineState _engineState = SyncEngineState.idle;
  SyncProgress _syncProgress = const SyncProgress();
  SyncResult? _lastSyncResult;

  AsyncValue<int> _state = const AsyncValue.initial();
  StreamSubscription<int>? _pendingCountSub;
  StreamSubscription<List<SyncOperationEntity>>? _pendingOpsSub;
  StreamSubscription<SyncEngineState>? _engineStateSub;
  StreamSubscription<SyncProgress>? _progressSub;

  int _generation = 0;
  int _streamGeneration = 0;
  bool _isDisposed = false;

  SyncProvider({
    required ISyncRepository repository,
    ISyncCoordinator? syncCoordinator,
  }) : _repository = repository,
       _syncCoordinator = syncCoordinator {
    _initCoordinatorSubscriptions();
  }

  void _initCoordinatorSubscriptions() {
    if (_syncCoordinator == null) return;

    _engineState = _syncCoordinator.currentState;
    _engineStateSub = _syncCoordinator.syncStateStream.listen((state) {
      if (_isDisposed) return;
      _engineState = state;
      _isSyncing = state == SyncEngineState.syncing;
      _safeNotifyListeners();
    });

    _progressSub = _syncCoordinator.progressStream.listen((progress) {
      if (_isDisposed) return;
      _syncProgress = progress;
      _safeNotifyListeners();
    });
  }

  // Getters
  int get pendingCount => _pendingCount;
  List<SyncOperationEntity> get pendingOperations =>
      List.unmodifiable(_pendingOperations);
  bool get hasPendingOperations => _pendingCount > 0;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime =>
      _lastSyncTime ?? _syncCoordinator?.lastSyncTimeUtc;
  String? get lastError => _lastError;
  AsyncValue<int> get state => _state;
  bool get isLoading => _state.isLoading;
  SyncEngineState get engineState => _engineState;
  SyncProgress get syncProgress => _syncProgress;
  SyncResult? get lastSyncResult =>
      _lastSyncResult ?? _syncCoordinator?.lastSyncResult;

  int get failedOperationCount =>
      _pendingOperations.where((op) => op.retryCount > 0).length;

  /// Triggers a manual cloud synchronization cycle via the coordinator.
  Future<SyncResult?> triggerSync({bool force = false}) async {
    if (_syncCoordinator == null) return null;
    _isSyncing = true;
    _safeNotifyListeners();

    try {
      final result = await _syncCoordinator.synchronize(force: force);
      _lastSyncResult = result;
      if (result.success) {
        _lastSyncTime = result.timestampUtc;
        _lastError = null;
      } else {
        _lastError = result.errorMessage;
      }
      return result;
    } catch (e) {
      _lastError = e.toString();
      return SyncResult.failure(e.toString());
    } finally {
      _isSyncing = _syncCoordinator.currentState == SyncEngineState.syncing;
      _safeNotifyListeners();
    }
  }

  /// Subscribes to the live stream of pending sync operations with generation guard.
  void watchSyncState() {
    _streamGeneration++;
    final streamGen = _streamGeneration;

    _pendingCountSub?.cancel();
    _pendingOpsSub?.cancel();

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    _pendingCountSub = _repository.watchPendingCount().listen(
      (count) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        _pendingCount = count;
        _state = AsyncValue.data(count);
        _safeNotifyListeners();
      },
      onError: (err, st) {
        if (streamGen != _streamGeneration || _isDisposed) return;
        AppLogger.error('SYNC_WATCH_PENDING_ERROR', error: err);
        _state = AsyncValue.error(
          err is AppException ? err.message : 'Failed to watch sync queue.',
          err,
          st,
        );
        _safeNotifyListeners();
      },
    );

    _pendingOpsSub = _repository.watchPendingOperations().listen((ops) {
      if (streamGen != _streamGeneration || _isDisposed) return;
      _pendingOperations = ops;
      _safeNotifyListeners();
    });
  }

  /// One-time load of local sync state with generation guard.
  Future<void> loadSyncState() async {
    _generation++;
    final currentGen = _generation;

    _state = const AsyncValue.loading();
    _safeNotifyListeners();

    try {
      final count = await _repository.getPendingCount();
      final ops = await _repository.getPendingOperations();
      if (currentGen != _generation || _isDisposed) return;

      _pendingCount = count;
      _pendingOperations = ops;
      _state = AsyncValue.data(count);
      _lastError = null;
    } on AppException catch (e) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error(e.message, e);
    } catch (e, st) {
      if (currentGen != _generation || _isDisposed) return;
      _state = AsyncValue.error('Failed to load sync queue state.', e, st);
    } finally {
      if (currentGen == _generation && !_isDisposed) {
        _safeNotifyListeners();
      }
    }
  }

  /// Resets provider state, cancels streams, and clears cached sync operations on user switch.
  Future<void> reset({bool reload = false}) async {
    _generation++;
    _streamGeneration++;
    _pendingCountSub?.cancel();
    _pendingCountSub = null;
    _pendingOpsSub?.cancel();
    _pendingOpsSub = null;

    _syncCoordinator?.abortActiveSync();

    _pendingCount = 0;
    _pendingOperations = [];
    _isSyncing = false;
    _lastError = null;
    _lastSyncTime = null;
    _lastSyncResult = null;
    _state = const AsyncValue.initial();
    _safeNotifyListeners();

    if (reload) {
      await loadSyncState();
    }
  }

  /// Manually records a local sync attempt start/finish (for local orchestrators).
  void setSyncingState(bool isSyncing, {String? error}) {
    _isSyncing = isSyncing;
    if (!isSyncing) {
      _lastSyncTime = DateTime.now().toUtc();
    }
    _lastError = error;
    _safeNotifyListeners();
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pendingCountSub?.cancel();
    _pendingOpsSub?.cancel();
    _engineStateSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }
}
