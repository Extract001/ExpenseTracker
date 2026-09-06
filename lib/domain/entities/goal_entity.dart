import 'enums.dart';

class GoalEntity {
  final String id;
  final String userId;
  final String name;
  final int targetAmount; // minor units
  final int currentAmount; // minor units
  final DateTime targetDate;
  final int iconCodePoint;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps;

  const GoalEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    this.currentAmount = 0,
    required this.targetDate,
    required this.iconCodePoint,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  double get progressPercentage {
    if (targetAmount <= 0) return 0.0;
    final pct = currentAmount / targetAmount;
    return pct > 1.0 ? 1.0 : pct;
  }

  bool get isCompleted => currentAmount >= targetAmount;

  int get remainingAmount =>
      targetAmount > currentAmount ? targetAmount - currentAmount : 0;

  GoalEntity copyWith({
    String? id,
    String? userId,
    String? name,
    int? targetAmount,
    int? currentAmount,
    DateTime? targetDate,
    int? iconCodePoint,
    int? colorValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return GoalEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: targetDate ?? this.targetDate,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}
