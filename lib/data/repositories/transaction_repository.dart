import 'dart:convert';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/i_transaction_repository.dart';
import '../database/app_database.dart';
import '../models/transaction_mapper.dart';
import 'sync_queue_helper.dart';

class TransactionRepository implements ITransactionRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  TransactionRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Stream<List<TransactionEntity>> watchRecentTransactions({int limit = 20}) {
    return _db.transactionDao
        .watchRecentTransactions(userId: _userId, limit: limit)
        .map((list) => list.map(TransactionMapper.fromData).toList());
  }

  @override
  Future<List<TransactionEntity>> getTransactionsCursor({
    DateTime? cursorDate,
    String? cursorId,
    int limit = 50,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? minAmount,
    int? maxAmount,
    String? searchQuery,
  }) async {
    final rows = await _db.transactionDao.getTransactionsCursor(
      userId: _userId,
      cursorDate: cursorDate?.toUtc(),
      cursorId: cursorId,
      limit: limit,
      type: type?.name,
      categoryId: categoryId,
      accountId: accountId,
      startDate: startDate?.toUtc(),
      endDate: endDate?.toUtc(),
      minAmountMinor: minAmount,
      maxAmountMinor: maxAmount,
      searchQuery: searchQuery,
    );
    return rows.map(TransactionMapper.fromData).toList();
  }

  @override
  Future<TransactionEntity?> getTransactionById(String id) async {
    final row = await _db.transactionDao.getTransactionById(id);
    if (row == null || row.userId != _userId || row.deletedAtUtc != null) {
      return null;
    }
    return TransactionMapper.fromData(row);
  }

  @override
  Future<void> createTransaction(TransactionEntity transaction) async {
    final nowUtc = DateTime.now().toUtc();
    final effectiveId = transaction.id.isEmpty
        ? IdGenerator.uuid()
        : transaction.id;

    final initialTimestamps = Map<String, String>.from(
      transaction.fieldTimestamps,
    );
    final isoNow = nowUtc.toIso8601String();
    for (final field in [
      'amountMinor',
      'transactionType',
      'categoryId',
      'accountId',
      'toAccountId',
      'note',
      'transactionDateUtc',
      'attachmentPath',
      'isRecurring',
      'recurringRuleId',
    ]) {
      initialTimestamps.putIfAbsent(field, () => isoNow);
    }

    final entityToSave = transaction.copyWith(
      id: effectiveId,
      userId: _userId,
      createdAt: transaction.createdAt.year == 0
          ? nowUtc
          : transaction.createdAt.toUtc(),
      updatedAt: nowUtc,
      syncStatus: SyncStatus.pendingCreate,
      fieldTimestamps: initialTimestamps,
    );

    await _db.transaction(() async {
      await _db.transactionDao.insertTransaction(
        TransactionMapper.toCompanion(entityToSave),
      );
      await SyncQueueHelper.enqueueCreate(
        _db,
        userId: _userId,
        entityType: EntityType.transaction,
        entityId: effectiveId,
        payloadJson: TransactionMapper.toJsonPayload(entityToSave),
      );
    });
  }

  @override
  Future<void> updateTransaction(TransactionEntity transaction) async {
    final existing = await _db.transactionDao.getTransactionById(
      transaction.id,
    );
    if (existing == null || existing.userId != _userId) {
      throw NotFoundException('Transaction not found or unauthorized: ');
    }

    final nowUtc = DateTime.now().toUtc();
    final isoNow = nowUtc.toIso8601String();

    // Field-level conflict resolution: track changed fields individually
    Map<String, String> existingTimestamps = {};
    try {
      if (existing.fieldTimestampsJson.isNotEmpty) {
        final decoded = jsonDecode(existing.fieldTimestampsJson);
        if (decoded is Map) {
          existingTimestamps = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      }
    } catch (_) {}

    final updatedTimestamps = Map<String, String>.from(existingTimestamps);
    if (existing.amountMinor != transaction.amount) {
      updatedTimestamps['amountMinor'] = isoNow;
    }
    if (existing.transactionType != transaction.type.name) {
      updatedTimestamps['transactionType'] = isoNow;
    }
    if (existing.categoryId != transaction.categoryId) {
      updatedTimestamps['categoryId'] = isoNow;
    }
    if (existing.accountId != transaction.accountId) {
      updatedTimestamps['accountId'] = isoNow;
    }
    if (existing.toAccountId != transaction.toAccountId) {
      updatedTimestamps['toAccountId'] = isoNow;
    }
    if (existing.note != transaction.note) {
      updatedTimestamps['note'] = isoNow;
    }
    if (existing.transactionDateUtc.toUtc() != transaction.date.toUtc()) {
      updatedTimestamps['transactionDateUtc'] = isoNow;
    }
    if (existing.attachmentPath != transaction.attachmentPath) {
      updatedTimestamps['attachmentPath'] = isoNow;
    }
    if (existing.isRecurring != transaction.isRecurring) {
      updatedTimestamps['isRecurring'] = isoNow;
    }
    if (existing.recurringRuleId != transaction.recurringRuleId) {
      updatedTimestamps['recurringRuleId'] = isoNow;
    }

    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    final newSyncStatus = currentSyncStatus == SyncStatus.pendingCreate
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    final updatedEntity = transaction.copyWith(
      userId: _userId,
      updatedAt: nowUtc,
      syncStatus: newSyncStatus,
      fieldTimestamps: updatedTimestamps,
    );

    await _db.transaction(() async {
      await _db.transactionDao.updateTransaction(
        TransactionMapper.toCompanion(updatedEntity),
      );
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.transaction,
        entityId: transaction.id,
        payloadJson: TransactionMapper.toJsonPayload(updatedEntity),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> softDeleteTransaction(String id) async {
    final existing = await _db.transactionDao.getTransactionById(id);
    if (existing == null || existing.userId != _userId) return;

    final nowUtc = DateTime.now().toUtc();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.transactionDao.softDeleteTransaction(
        id: id,
        deletedAtUtc: nowUtc,
        syncStatus: currentSyncStatus == SyncStatus.pendingCreate
            ? SyncStatus.pendingCreate.name
            : SyncStatus.pendingDelete.name,
      );
      await SyncQueueHelper.enqueueDelete(
        _db,
        userId: _userId,
        entityType: EntityType.transaction,
        entityId: id,
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<int> getTotalIncome(DateTime startDateUtc, DateTime endDateUtc) {
    return _db.transactionDao.getTotalIncome(
      userId: _userId,
      startDateUtc: startDateUtc.toUtc(),
      endDateUtc: endDateUtc.toUtc(),
    );
  }

  @override
  Future<int> getTotalExpense(DateTime startDateUtc, DateTime endDateUtc) {
    return _db.transactionDao.getTotalExpense(
      userId: _userId,
      startDateUtc: startDateUtc.toUtc(),
      endDateUtc: endDateUtc.toUtc(),
    );
  }
}
