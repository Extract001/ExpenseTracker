import 'enums.dart';

class CategoryEntity {
  final String id;
  final String userId;
  final String name;
  final int iconCodePoint;
  final int colorValue;
  final TransactionType type; // income or expense
  final bool isSystem;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps;

  const CategoryEntity({
    required this.id,
    required this.userId,
    required this.name,
    required this.iconCodePoint,
    required this.colorValue,
    required this.type,
    this.isSystem = false,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  CategoryEntity copyWith({
    String? id,
    String? userId,
    String? name,
    int? iconCodePoint,
    int? colorValue,
    TransactionType? type,
    bool? isSystem,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return CategoryEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
      type: type ?? this.type,
      isSystem: isSystem ?? this.isSystem,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}
