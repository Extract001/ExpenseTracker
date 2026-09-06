import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/transaction_entity.dart';
import '../database/app_database.dart';

class TransactionMapper {
  static TransactionEntity fromData(TransactionData data) {
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

    return TransactionEntity(
      id: data.id,
      userId: data.userId,
      amount: data.amountMinor,
      type: TransactionType.values.firstWhere(
        (t) => t.name == data.transactionType,
        orElse: () => TransactionType.expense,
      ),
      categoryId: data.categoryId,
      accountId: data.accountId,
      toAccountId: data.toAccountId,
      note: data.note,
      date: data.transactionDateUtc.toUtc(),
      attachmentPath: data.attachmentPath,
      isRecurring: data.isRecurring,
      recurringRuleId: data.recurringRuleId,
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

  static TransactionsTableCompanion toCompanion(TransactionEntity entity) {
    return TransactionsTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      amountMinor: Value(entity.amount),
      transactionType: Value(entity.type.name),
      categoryId: Value(entity.categoryId),
      accountId: Value(entity.accountId),
      toAccountId: Value(entity.toAccountId),
      note: Value(entity.note),
      transactionDateUtc: Value(entity.date.toUtc()),
      attachmentPath: Value(entity.attachmentPath),
      isRecurring: Value(entity.isRecurring),
      recurringRuleId: Value(entity.recurringRuleId),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }

  static String toJsonPayload(TransactionEntity entity) {
    return jsonEncode({
      'id': entity.id,
      'userId': entity.userId,
      'amountMinor': entity.amount,
      'transactionType': entity.type.name,
      'categoryId': entity.categoryId,
      'accountId': entity.accountId,
      'toAccountId': entity.toAccountId,
      'note': entity.note,
      'transactionDateUtc': entity.date.toUtc().toIso8601String(),
      'attachmentPath': entity.attachmentPath,
      'isRecurring': entity.isRecurring,
      'recurringRuleId': entity.recurringRuleId,
      'createdAtUtc': entity.createdAt.toUtc().toIso8601String(),
      'updatedAtUtc': entity.updatedAt.toUtc().toIso8601String(),
      'deletedAtUtc': entity.deletedAt?.toUtc().toIso8601String(),
      'syncStatus': entity.syncStatus.name,
      'fieldTimestamps': entity.fieldTimestamps,
    });
  }
}
