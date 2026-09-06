enum ConnectivityStatus {
  online,
  offline,
  unknown;

  bool get isOnline => this == ConnectivityStatus.online;
}
