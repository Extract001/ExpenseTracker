import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/account_entity.dart';
import '../../domain/entities/enums.dart';
import '../database/app_database.dart';

class AccountMapper {
  static AccountEntity fromData(AccountData data) {
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

    return AccountEntity(
      id: data.id,
      userId: data.userId,
      name: data.name,
      type: AccountType.values.firstWhere(
        (t) => t.name == data.accountType,
        orElse: () => AccountType.cash,
      ),
      initialBalance: data.initialBalanceMinor,
      currency: data.currency,
      colorValue: data.colorValue,
      iconCodePoint: data.iconCodePoint,
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

  static AccountsTableCompanion toCompanion(AccountEntity entity) {
    return AccountsTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      name: Value(entity.name),
      accountType: Value(entity.type.name),
      currency: Value(entity.currency),
      initialBalanceMinor: Value(entity.initialBalance),
      colorValue: Value(entity.colorValue),
      iconCodePoint: Value(entity.iconCodePoint),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }

  static String toJsonPayload(AccountEntity entity) {
    return jsonEncode({
      'id': entity.id,
      'userId': entity.userId,
      'name': entity.name,
      'accountType': entity.type.name,
      'currency': entity.currency,
      'initialBalanceMinor': entity.initialBalance,
      'colorValue': entity.colorValue,
      'iconCodePoint': entity.iconCodePoint,
      'createdAtUtc': entity.createdAt.toUtc().toIso8601String(),
      'updatedAtUtc': entity.updatedAt.toUtc().toIso8601String(),
      'deletedAtUtc': entity.deletedAt?.toUtc().toIso8601String(),
      'syncStatus': entity.syncStatus.name,
      'fieldTimestamps': entity.fieldTimestamps,
    });
  }
}
