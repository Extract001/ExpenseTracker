import 'enums.dart';

class BudgetEntity {
  final String id;
  final String userId;
  final String monthYear; // e.g. "2026-09"
  final int amount; // overall monthly limit in minor units
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps;

  const BudgetEntity({
    required this.id,
    required this.userId,
    required this.monthYear,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  BudgetEntity copyWith({
    String? id,
    String? userId,
    String? monthYear,
    int? amount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return BudgetEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      monthYear: monthYear ?? this.monthYear,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}

class CategoryBudgetEntity {
  final String id;
  final String userId;
  final String budgetId;
  final String categoryId;
  final int amount; // category budget in minor units
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps;

  const CategoryBudgetEntity({
    required this.id,
    required this.userId,
    required this.budgetId,
    required this.categoryId,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  CategoryBudgetEntity copyWith({
    String? id,
    String? userId,
    String? budgetId,
    String? categoryId,
    int? amount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return CategoryBudgetEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      budgetId: budgetId ?? this.budgetId,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}
