import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/recurring_transaction_entity.dart';
import '../database/app_database.dart';

class RecurringTransactionMapper {
  static RecurringTransactionEntity fromData(RecurringTransactionData data) {
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

    return RecurringTransactionEntity(
      id: data.id,
      userId: data.userId,
      amount: data.amountMinor,
      type: TransactionType.values.firstWhere(
        (t) => t.name == data.transactionType,
        orElse: () => TransactionType.expense,
      ),
      categoryId: data.categoryId,
      accountId: data.accountId,
      note: data.note,
      frequency: RecurrenceFrequency.values.firstWhere(
        (f) => f.name == data.frequency,
        orElse: () => RecurrenceFrequency.monthly,
      ),
      startDate: data.startDateUtc.toUtc(),
      nextDate: data.nextOccurrenceUtc.toUtc(),
      lastExecutedDate: data.lastExecutedDateUtc?.toUtc(),
      isActive: data.isActive,
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

  static RecurringTransactionsTableCompanion toCompanion(
    RecurringTransactionEntity entity,
  ) {
    return RecurringTransactionsTableCompanion(
      id: Value(entity.id),
      userId: Value(entity.userId),
      amountMinor: Value(entity.amount),
      transactionType: Value(entity.type.name),
      categoryId: Value(entity.categoryId),
      accountId: Value(entity.accountId),
      note: Value(entity.note),
      frequency: Value(entity.frequency.name),
      startDateUtc: Value(entity.startDate.toUtc()),
      nextOccurrenceUtc: Value(entity.nextDate.toUtc()),
      lastExecutedDateUtc: Value(entity.lastExecutedDate?.toUtc()),
      isActive: Value(entity.isActive),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      updatedAtUtc: Value(entity.updatedAt.toUtc()),
      deletedAtUtc: Value(entity.deletedAt?.toUtc()),
      syncStatus: Value(entity.syncStatus.name),
      fieldTimestampsJson: Value(jsonEncode(entity.fieldTimestamps)),
    );
  }
}
