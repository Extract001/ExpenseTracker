import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/goal_entity.dart';
import '../database/app_database.dart';

class GoalMapper {
  static GoalEntity fromData(SavingsGoalData data) {
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

    return GoalEntity(
      id: data.id,
      userId: data.userId,
      name: data.name,
      targetAmount: data.targetAmountMinor,
      currentAmount: data.currentAmountMinor,
      targetDate: data.targetDateUtc.toUtc(),
      iconCodePoint: data.iconCodePoint,
      colorValue: data.colorValue,
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

  static SavingsGoalsTableCompanion toCompanion(GoalEntity entity) {
    return SavingsGoalsTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      name: Value(entity.name),
      targetAmountMinor: Value(entity.targetAmount),
      currentAmountMinor: Value(entity.currentAmount),
      targetDateUtc: Value(entity.targetDate.toUtc()),
      iconCodePoint: Value(entity.iconCodePoint),
      colorValue: Value(entity.colorValue),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }
}
