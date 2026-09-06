import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/recurring_transaction_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/i_recurring_transaction_repository.dart';
import '../database/app_database.dart';
import '../models/recurring_transaction_mapper.dart';
import '../models/transaction_mapper.dart';
import 'sync_queue_helper.dart';

class RecurringTransactionRepository
    implements IRecurringTransactionRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  RecurringTransactionRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Stream<List<RecurringTransactionEntity>> watchAllRecurring() {
    return _db.recurringTransactionDao
        .watchAllRecurring(_userId)
        .map((list) => list.map(RecurringTransactionMapper.fromData).toList());
  }

  @override
  Future<List<RecurringTransactionEntity>> getDueRecurringTransactions(
    DateTime nowUtc,
  ) async {
    final list = await _db.recurringTransactionDao.getDueRecurringTransactions(
      userId: _userId,
      nowUtc: nowUtc.toUtc(),
    );
    return list.map(RecurringTransactionMapper.fromData).toList();
  }

  @override
  Future<void> createRecurring(RecurringTransactionEntity entity) async {
    final nowUtc = DateTime.now().toUtc();
    final effectiveId = entity.id.isEmpty ? IdGenerator.uuid() : entity.id;

    final initialTimestamps = Map<String, String>.from(entity.fieldTimestamps);
    final isoNow = nowUtc.toIso8601String();
    for (final f in [
      'amountMinor',
      'transactionType',
      'categoryId',
      'accountId',
      'note',
      'frequency',
      'startDateUtc',
      'nextOccurrenceUtc',
      'isActive',
    ]) {
      initialTimestamps.putIfAbsent(f, () => isoNow);
    }

    final entityToSave = entity.copyWith(
      id: effectiveId,
      userId: _userId,
      createdAt: entity.createdAt.year == 0 ? nowUtc : entity.createdAt.toUtc(),
      updatedAt: nowUtc,
      syncStatus: SyncStatus.pendingCreate,
      fieldTimestamps: initialTimestamps,
    );

    await _db.transaction(() async {
      await _db.recurringTransactionDao.insertRecurring(
        RecurringTransactionMapper.toCompanion(entityToSave),
      );
      await SyncQueueHelper.enqueueCreate(
        _db,
        userId: _userId,
        entityType: EntityType.recurringRule,
        entityId: effectiveId,
        payloadJson: jsonEncode({
          'id': entityToSave.id,
          'userId': entityToSave.userId,
          'amountMinor': entityToSave.amount,
          'transactionType': entityToSave.type.name,
          'categoryId': entityToSave.categoryId,
          'accountId': entityToSave.accountId,
          'note': entityToSave.note,
          'frequency': entityToSave.frequency.name,
          'startDateUtc': entityToSave.startDate.toUtc().toIso8601String(),
          'nextOccurrenceUtc': entityToSave.nextDate.toUtc().toIso8601String(),
          'isActive': entityToSave.isActive,
          'createdAtUtc': entityToSave.createdAt.toUtc().toIso8601String(),
          'updatedAtUtc': entityToSave.updatedAt.toUtc().toIso8601String(),
          'syncStatus': entityToSave.syncStatus.name,
          'fieldTimestamps': entityToSave.fieldTimestamps,
        }),
      );
    });
  }

  @override
  Future<void> updateRecurring(RecurringTransactionEntity entity) async {
    final existing =
        await (_db.select(_db.recurringTransactionsTable)
              ..where((r) => r.id.equals(entity.id) & r.userId.equals(_userId)))
            .getSingleOrNull();
    if (existing == null) {
      throw NotFoundException('Recurring rule not found or unauthorized: ');
    }

    final nowUtc = DateTime.now().toUtc();
    final isoNow = nowUtc.toIso8601String();

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
    if (existing.amountMinor != entity.amount) {
      updatedTimestamps['amountMinor'] = isoNow;
    }
    if (existing.transactionType != entity.type.name) {
      updatedTimestamps['transactionType'] = isoNow;
    }
    if (existing.categoryId != entity.categoryId) {
      updatedTimestamps['categoryId'] = isoNow;
    }
    if (existing.accountId != entity.accountId) {
      updatedTimestamps['accountId'] = isoNow;
    }
    if (existing.note != entity.note) updatedTimestamps['note'] = isoNow;
    if (existing.frequency != entity.frequency.name) {
      updatedTimestamps['frequency'] = isoNow;
    }
    if (existing.isActive != entity.isActive) {
      updatedTimestamps['isActive'] = isoNow;
    }

    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    final newSyncStatus = currentSyncStatus == SyncStatus.pendingCreate
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    final updatedEntity = entity.copyWith(
      userId: _userId,
      updatedAt: nowUtc,
      syncStatus: newSyncStatus,
      fieldTimestamps: updatedTimestamps,
    );

    await _db.transaction(() async {
      await _db.recurringTransactionDao.updateRecurring(
        RecurringTransactionMapper.toCompanion(updatedEntity),
      );
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.recurringRule,
        entityId: entity.id,
        payloadJson: jsonEncode({
          'id': updatedEntity.id,
          'userId': updatedEntity.userId,
          'amountMinor': updatedEntity.amount,
          'transactionType': updatedEntity.type.name,
          'categoryId': updatedEntity.categoryId,
          'accountId': updatedEntity.accountId,
          'note': updatedEntity.note,
          'frequency': updatedEntity.frequency.name,
          'startDateUtc': updatedEntity.startDate.toUtc().toIso8601String(),
          'nextOccurrenceUtc': updatedEntity.nextDate.toUtc().toIso8601String(),
          'isActive': updatedEntity.isActive,
          'createdAtUtc': updatedEntity.createdAt.toUtc().toIso8601String(),
          'updatedAtUtc': updatedEntity.updatedAt.toUtc().toIso8601String(),
          'syncStatus': updatedEntity.syncStatus.name,
          'fieldTimestamps': updatedEntity.fieldTimestamps,
        }),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> updateNextExecutionDate(
    String id,
    DateTime nextDate,
    DateTime lastExecutedDate,
  ) async {
    final existing =
        await (_db.select(_db.recurringTransactionsTable)
              ..where((r) => r.id.equals(id) & r.userId.equals(_userId)))
            .getSingleOrNull();
    if (existing == null) return;

    final nowUtc = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _db.recurringTransactionDao.updateNextExecutionDate(
        id: id,
        nextOccurrenceUtc: nextDate.toUtc(),
        lastExecutedDateUtc: lastExecutedDate.toUtc(),
        updatedAtUtc: nowUtc,
      );
    });
  }

  @override
  Future<void> toggleActive(String id, bool isActive) async {
    final existing =
        await (_db.select(_db.recurringTransactionsTable)
              ..where((r) => r.id.equals(id) & r.userId.equals(_userId)))
            .getSingleOrNull();
    if (existing == null) return;

    final nowUtc = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.recurringTransactionDao.toggleActive(
        id: id,
        isActive: isActive,
        updatedAtUtc: nowUtc,
      );
    });
  }

  @override
  Future<void> softDeleteRecurring(String id) async {
    final existing =
        await (_db.select(_db.recurringTransactionsTable)
              ..where((r) => r.id.equals(id) & r.userId.equals(_userId)))
            .getSingleOrNull();
    if (existing == null) return;

    final nowUtc = DateTime.now().toUtc();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.recurringTransactionDao.softDeleteRecurring(
        id: id,
        deletedAtUtc: nowUtc,
      );
      await SyncQueueHelper.enqueueDelete(
        _db,
        userId: _userId,
        entityType: EntityType.recurringRule,
        entityId: id,
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<int> processDueRecurringRules(DateTime nowUtc) async {
    final dueRules = await getDueRecurringTransactions(nowUtc);
    int generatedCount = 0;

    for (final rule in dueRules) {
      if (!rule.isActive) continue;

      var occurrence = rule.nextDate.toUtc();
      final targetNow = nowUtc.toUtc();

      while (!occurrence.isAfter(targetNow)) {
        final occurrenceMs = occurrence.millisecondsSinceEpoch;
        final txId = 'tx_rec_${rule.id}_$occurrenceMs';

        DateTime nextOcc;
        switch (rule.frequency) {
          case RecurrenceFrequency.daily:
            nextOcc = occurrence.add(const Duration(days: 1));
            break;
          case RecurrenceFrequency.weekly:
            nextOcc = occurrence.add(const Duration(days: 7));
            break;
          case RecurrenceFrequency.monthly:
            nextOcc = DateTime.utc(
              occurrence.year,
              occurrence.month + 1,
              occurrence.day,
              occurrence.hour,
              occurrence.minute,
              occurrence.second,
            );
            break;
          case RecurrenceFrequency.yearly:
            nextOcc = DateTime.utc(
              occurrence.year + 1,
              occurrence.month,
              occurrence.day,
              occurrence.hour,
              occurrence.minute,
              occurrence.second,
            );
            break;
        }

        final txNowUtc = DateTime.now().toUtc();
        final generatedTx = TransactionEntity(
          id: txId,
          userId: _userId,
          amount: rule.amount,
          type: rule.type,
          categoryId: rule.categoryId,
          accountId: rule.accountId,
          note: rule.note,
          date: occurrence,
          isRecurring: true,
          recurringRuleId: rule.id,
          createdAt: txNowUtc,
          updatedAt: txNowUtc,
          syncStatus: SyncStatus.pendingCreate,
        );

        // Atomic block: Check + Insert TX + Advance Rule + Enqueue Sync
        final created = await _db.transaction(() async {
          final existingTx =
              await (_db.select(_db.transactionsTable)..where(
                    (t) =>
                        t.id.equals(txId) |
                        (t.recurringRuleId.equals(rule.id) &
                            t.transactionDateUtc.equals(occurrence) &
                            t.deletedAtUtc.isNull()),
                  ))
                  .getSingleOrNull();

          if (existingTx != null) {
            await _db.recurringTransactionDao.updateNextExecutionDate(
              id: rule.id,
              nextOccurrenceUtc: nextOcc,
              lastExecutedDateUtc: occurrence,
              updatedAtUtc: txNowUtc,
            );
            return false;
          }

          await _db.transactionDao.insertTransaction(
            TransactionMapper.toCompanion(generatedTx),
          );

          await SyncQueueHelper.enqueueCreate(
            _db,
            userId: _userId,
            entityType: EntityType.transaction,
            entityId: txId,
            payloadJson: TransactionMapper.toJsonPayload(generatedTx),
          );

          await _db.recurringTransactionDao.updateNextExecutionDate(
            id: rule.id,
            nextOccurrenceUtc: nextOcc,
            lastExecutedDateUtc: occurrence,
            updatedAtUtc: txNowUtc,
          );

          return true;
        });

        if (created) {
          generatedCount++;
        }

        occurrence = nextOcc;
      }
    }

    return generatedCount;
  }
}
