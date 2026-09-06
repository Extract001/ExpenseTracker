import 'enums.dart';

class TransactionEntity {
  final String id;
  final String userId;
  final int amount; // minor units (e.g. cents/paise)
  final TransactionType type;
  final String categoryId;
  final String accountId;
  final String? toAccountId; // only for transfer
  final String note;
  final DateTime date; // UTC
  final String? attachmentPath;
  final bool isRecurring;
  final String? recurringRuleId;
  final DateTime createdAt; // UTC
  final DateTime updatedAt; // UTC
  final DateTime? deletedAt; // UTC
  final SyncStatus syncStatus;
  final Map<String, String> fieldTimestamps; // field -> ISO UTC timestamp

  const TransactionEntity({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.accountId,
    this.toAccountId,
    required this.note,
    required this.date,
    this.attachmentPath,
    this.isRecurring = false,
    this.recurringRuleId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
    this.fieldTimestamps = const {},
  });

  bool get isDeleted => deletedAt != null;

  TransactionEntity copyWith({
    String? id,
    String? userId,
    int? amount,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    String? toAccountId,
    String? note,
    DateTime? date,
    String? attachmentPath,
    bool? isRecurring,
    String? recurringRuleId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    SyncStatus? syncStatus,
    Map<String, String>? fieldTimestamps,
  }) {
    return TransactionEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      toAccountId: toAccountId ?? this.toAccountId,
      note: note ?? this.note,
      date: date ?? this.date,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringRuleId: recurringRuleId ?? this.recurringRuleId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      fieldTimestamps: fieldTimestamps ?? this.fieldTimestamps,
    );
  }
}
