import 'connectivity_status.dart';

abstract class IConnectivityService {
  /// Stream emitting connectivity status updates.
  Stream<ConnectivityStatus> get onConnectivityChanged;

  /// Returns whether device currently has active network connectivity.
  Future<bool> get isConnected;

  /// Returns the current known connectivity status.
  ConnectivityStatus get currentStatus;

  /// Disposes active listeners and subscriptions.
  void dispose();
}
