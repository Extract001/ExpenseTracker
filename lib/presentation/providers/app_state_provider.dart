import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/app_logger.dart';
import '../core/async_value.dart';

enum AppInitStatus { uninitialized, initializing, initialized, error }

class AppStateProvider extends ChangeNotifier {
  AppInitStatus _initStatus = AppInitStatus.uninitialized;
  String _currentUserId = AppConstants.defaultUserId;
  String? _fatalError;
  bool _isDisposed = false;

  AppStateProvider({String? initialUserId}) {
    if (initialUserId != null && initialUserId.isNotEmpty) {
      _currentUserId = initialUserId;
    }
  }

  AppInitStatus get initStatus => _initStatus;
  bool get isInitialized => _initStatus == AppInitStatus.initialized;
  bool get isInitializing => _initStatus == AppInitStatus.initializing;
  bool get hasFatalError => _initStatus == AppInitStatus.error;
  String get currentUserId => _currentUserId;
  String? get fatalError => _fatalError;

  AsyncValue<String> get initializationState {
    switch (_initStatus) {
      case AppInitStatus.uninitialized:
        return const AsyncValue.initial();
      case AppInitStatus.initializing:
        return const AsyncValue.loading();
      case AppInitStatus.initialized:
        return AsyncValue.data(_currentUserId);
      case AppInitStatus.error:
        return AsyncValue.error(_fatalError ?? 'App initialization failed');
    }
  }

  final List<void Function(String newUserId)> _userChangeListeners = [];

  /// Registers a callback to be invoked when the active user ID switches.
  void addOnUserChangedListener(void Function(String newUserId) listener) {
    _userChangeListeners.add(listener);
  }

  /// Removes a user change callback.
  void removeOnUserChangedListener(void Function(String newUserId) listener) {
    _userChangeListeners.remove(listener);
  }

  /// Sets the active local user ID for the application session and notifies registered listeners.
  void setCurrentUserId(String userId) {
    if (userId.isEmpty) return;
    if (_currentUserId != userId) {
      _currentUserId = userId;
      for (final listener in List.of(_userChangeListeners)) {
        listener(userId);
      }
      _safeNotifyListeners();
    }
  }

  /// Switches active user and triggers session reset across dependent providers.
  void switchUser(String newUserId) => setCurrentUserId(newUserId);

  /// Initializes the app and marks the system as ready.
  Future<void> initialize({
    Future<void> Function()? onInitHook,
    String? userId,
  }) async {
    if (_initStatus == AppInitStatus.initializing) return;

    _initStatus = AppInitStatus.initializing;
    _fatalError = null;
    if (userId != null && userId.isNotEmpty) {
      _currentUserId = userId;
    }
    _safeNotifyListeners();

    try {
      if (onInitHook != null) {
        await onInitHook();
      }
      _initStatus = AppInitStatus.initialized;
      _fatalError = null;
    } catch (e, st) {
      AppLogger.error('APP_INIT_ERROR', error: e, stackTrace: st);
      _initStatus = AppInitStatus.error;
      _fatalError = e.toString();
    } finally {
      _safeNotifyListeners();
    }
  }

  /// Reset or re-initialize state if necessary.
  void reset() {
    _initStatus = AppInitStatus.uninitialized;
    _fatalError = null;
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
    super.dispose();
  }
}
