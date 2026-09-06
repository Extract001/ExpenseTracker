import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'connectivity_status.dart';
import 'i_connectivity_service.dart';

class ConnectivityService implements IConnectivityService {
  final Connectivity _connectivity;
  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  ConnectivityStatus _currentStatus = ConnectivityStatus.unknown;

  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityResult,
      onError: (err) {
        _currentStatus = ConnectivityStatus.unknown;
        _statusController.add(ConnectivityStatus.unknown);
      },
    );
  }

  void _handleConnectivityResult(List<ConnectivityResult> results) {
    final status = _mapResultsToStatus(results);
    _currentStatus = status;
    _statusController.add(status);
  }

  ConnectivityStatus _mapResultsToStatus(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return ConnectivityStatus.offline;
    }
    return ConnectivityStatus.online;
  }

  @override
  Stream<ConnectivityStatus> get onConnectivityChanged =>
      _statusController.stream;

  @override
  Future<bool> get isConnected async {
    try {
      final results = await _connectivity.checkConnectivity();
      final status = _mapResultsToStatus(results);
      _currentStatus = status;
      return status.isOnline;
    } catch (_) {
      return false;
    }
  }

  @override
  ConnectivityStatus get currentStatus => _currentStatus;

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _statusController.close();
  }
}
