import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/enums.dart';
import '../database/app_database.dart';

class CategoryMapper {
  static CategoryEntity fromData(CategoryData data) {
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

    return CategoryEntity(
      id: data.id,
      userId: data.userId,
      name: data.name,
      iconCodePoint: data.iconCodePoint,
      colorValue: data.colorValue,
      type: data.type == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      isSystem: data.isSystem,
      isArchived: data.isArchived,
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

  static CategoriesTableCompanion toCompanion(CategoryEntity entity) {
    return CategoriesTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      name: Value(entity.name),
      type: Value(entity.type.name),
      iconCodePoint: Value(entity.iconCodePoint),
      colorValue: Value(entity.colorValue),
      isSystem: Value(entity.isSystem),
      isArchived: Value(entity.isArchived),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }

  static String toJsonPayload(CategoryEntity entity) {
    return jsonEncode({
      'id': entity.id,
      'userId': entity.userId,
      'name': entity.name,
      'type': entity.type.name,
      'iconCodePoint': entity.iconCodePoint,
      'colorValue': entity.colorValue,
      'isSystem': entity.isSystem,
      'isArchived': entity.isArchived,
      'createdAtUtc': entity.createdAt.toUtc().toIso8601String(),
      'updatedAtUtc': entity.updatedAt.toUtc().toIso8601String(),
      'deletedAtUtc': entity.deletedAt?.toUtc().toIso8601String(),
      'syncStatus': entity.syncStatus.name,
      'fieldTimestamps': entity.fieldTimestamps,
    });
  }
}
