import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/enums.dart';
import '../database/app_database.dart';

class BudgetMapper {
  static BudgetEntity fromData(BudgetData data) {
    Map<String, String> timestamps = {};
    try {
      if (data.fieldTimestampsJson.isNotEmpty) {
        final decoded = jsonDecode(data.fieldTimestampsJson);
        if (decoded is Map) {
          timestamps = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      }
    } catch (_) {}

    return BudgetEntity(
      id: data.id,
      userId: data.userId,
      monthYear: data.monthYear,
      amount: data.amountMinor,
      createdAt: data.createdAtUtc.toUtc(),
      updatedAt: data.updatedAtUtc.toUtc(),
      deletedAt: data.deletedAtUtc?.toUtc(),
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == data.syncStatus,
        orElse: () => SyncStatus.pendingCreate,
      ),
      fieldTimestamps: timestamps,
    );
  }

  static BudgetsTableCompanion toCompanion(BudgetEntity entity) {
    return BudgetsTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      monthYear: Value(entity.monthYear),
      amountMinor: Value(entity.amount),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }

  static CategoryBudgetEntity fromCategoryData(CategoryBudgetData data) {
    Map<String, String> timestamps = {};
    try {
      if (data.fieldTimestampsJson.isNotEmpty) {
        final decoded = jsonDecode(data.fieldTimestampsJson);
        if (decoded is Map) {
          timestamps = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      }
    } catch (_) {}

    return CategoryBudgetEntity(
      id: data.id,
      userId: data.userId,
      budgetId: data.budgetId,
      categoryId: data.categoryId,
      amount: data.amountMinor,
      createdAt: data.createdAtUtc.toUtc(),
      updatedAt: data.updatedAtUtc.toUtc(),
      deletedAt: data.deletedAtUtc?.toUtc(),
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == data.syncStatus,
        orElse: () => SyncStatus.pendingCreate,
      ),
      fieldTimestamps: timestamps,
    );
  }

  static CategoryBudgetsTableCompanion toCategoryCompanion(
    CategoryBudgetEntity entity,
  ) {
    return CategoryBudgetsTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      budgetId: Value(entity.budgetId),
      categoryId: Value(entity.categoryId),
      amountMinor: Value(entity.amount),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }
}
