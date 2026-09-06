import 'enums.dart';

class RecurringTransactionEntity {
  final String id;
  final String userId;
  final int amount; // minor units
  final TransactionType type;
  final String categoryId;
  final String accountId;
  final String note;
  final RecurrenceFrequency frequency;
  final DateTime startDate;
  final DateTime nextDate;
  final DateTime? lastExecutedDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps;

  const RecurringTransactionEntity({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.accountId,
    required this.note,
    required this.frequency,
    required this.startDate,
    required this.nextDate,
    this.lastExecutedDate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  RecurringTransactionEntity copyWith({
    String? id,
    String? userId,
    int? amount,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    String? note,
    RecurrenceFrequency? frequency,
    DateTime? startDate,
    DateTime? nextDate,
    DateTime? lastExecutedDate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return RecurringTransactionEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      note: note ?? this.note,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      nextDate: nextDate ?? this.nextDate,
      lastExecutedDate: lastExecutedDate ?? this.lastExecutedDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}
