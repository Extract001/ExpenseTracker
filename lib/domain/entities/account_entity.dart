import 'enums.dart';

class AccountEntity {
  final String id;
  final String userId;
  final String name;
  final AccountType type;
  final int initialBalance; // minor units
  final String currency;
  final int colorValue;
  final int iconCodePoint;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps;

  const AccountEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.initialBalance = 0,
    required this.currency,
    required this.colorValue,
    required this.iconCodePoint,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  AccountEntity copyWith({
    String? id,
    String? userId,
    String? name,
    AccountType? type,
    int? initialBalance,
    String? currency,
    int? colorValue,
    int? iconCodePoint,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return AccountEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      currency: currency ?? this.currency,
      colorValue: colorValue ?? this.colorValue,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}
