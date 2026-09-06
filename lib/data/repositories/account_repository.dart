import 'dart:convert';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/account_entity.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/i_account_repository.dart';
import '../database/app_database.dart';
import '../models/account_mapper.dart';
import '../models/transaction_mapper.dart';
import 'sync_queue_helper.dart';

class AccountRepository implements IAccountRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  AccountRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Stream<List<AccountEntity>> watchAllAccounts() {
    return _db.accountDao
        .watchAllAccounts(_userId)
        .map((list) => list.map(AccountMapper.fromData).toList());
  }

  @override
  Future<List<AccountEntity>> getAllAccounts() async {
    final list = await _db.accountDao.getAllAccounts(_userId);
    return list.map(AccountMapper.fromData).toList();
  }

  @override
  Future<AccountEntity?> getAccountById(String id) async {
    final acc = await _db.accountDao.getAccountById(id);
    if (acc == null || acc.userId != _userId || acc.deletedAtUtc != null) {
      return null;
    }
    return AccountMapper.fromData(acc);
  }

  @override
  Future<void> createAccount(AccountEntity account) async {
    if (account.name.trim().isEmpty) {
      throw const ValidationException('Account name cannot be empty');
    }

    final nowUtc = DateTime.now().toUtc();
    final effectiveId = account.id.isEmpty ? IdGenerator.uuid() : account.id;

    final initialTimestamps = Map<String, String>.from(account.fieldTimestamps);
    final isoNow = nowUtc.toIso8601String();
    for (final f in [
      'name',
      'accountType',
      'currency',
      'initialBalanceMinor',
      'colorValue',
      'iconCodePoint',
    ]) {
      initialTimestamps.putIfAbsent(f, () => isoNow);
    }

    final entityToSave = account.copyWith(
      id: effectiveId,
      userId: _userId,
      createdAt: account.createdAt.year == 0
          ? nowUtc
          : account.createdAt.toUtc(),
      updatedAt: nowUtc,
      syncStatus: SyncStatus.pendingCreate,
      fieldTimestamps: initialTimestamps,
    );

    await _db.transaction(() async {
      await _db.accountDao.insertAccount(
        AccountMapper.toCompanion(entityToSave),
      );
      await SyncQueueHelper.enqueueCreate(
        _db,
        userId: _userId,
        entityType: EntityType.account,
        entityId: effectiveId,
        payloadJson: AccountMapper.toJsonPayload(entityToSave),
      );
    });
  }

  @override
  Future<void> updateAccount(AccountEntity account) async {
    final existing = await _db.accountDao.getAccountById(account.id);
    if (existing == null || existing.userId != _userId) {
      throw NotFoundException('Account not found or unauthorized: ');
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
    if (existing.name != account.name) updatedTimestamps['name'] = isoNow;
    if (existing.accountType != account.type.name) {
      updatedTimestamps['accountType'] = isoNow;
    }
    if (existing.currency != account.currency) {
      updatedTimestamps['currency'] = isoNow;
    }
    if (existing.initialBalanceMinor != account.initialBalance) {
      updatedTimestamps['initialBalanceMinor'] = isoNow;
    }
    if (existing.colorValue != account.colorValue) {
      updatedTimestamps['colorValue'] = isoNow;
    }
    if (existing.iconCodePoint != account.iconCodePoint) {
      updatedTimestamps['iconCodePoint'] = isoNow;
    }

    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    final newSyncStatus = currentSyncStatus == SyncStatus.pendingCreate
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    final updatedEntity = account.copyWith(
      userId: _userId,
      updatedAt: nowUtc,
      syncStatus: newSyncStatus,
      fieldTimestamps: updatedTimestamps,
    );

    await _db.transaction(() async {
      await _db.accountDao.updateAccount(
        AccountMapper.toCompanion(updatedEntity),
      );
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.account,
        entityId: account.id,
        payloadJson: AccountMapper.toJsonPayload(updatedEntity),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> softDeleteAccount(String id) async {
    final existing = await _db.accountDao.getAccountById(id);
    if (existing == null || existing.userId != _userId) return;

    final nowUtc = DateTime.now().toUtc();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.accountDao.softDeleteAccount(
        id: id,
        deletedAtUtc: nowUtc,
        syncStatus: currentSyncStatus == SyncStatus.pendingCreate
            ? SyncStatus.pendingCreate.name
            : SyncStatus.pendingDelete.name,
      );
      await SyncQueueHelper.enqueueDelete(
        _db,
        userId: _userId,
        entityType: EntityType.account,
        entityId: id,
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<int> getAccountBalance(String accountId) {
    return _db.accountDao.getAccountBalance(
      userId: _userId,
      accountId: accountId,
    );
  }

  @override
  Future<int> getTotalNetWorth() {
    return _db.accountDao.getTotalNetWorth(_userId);
  }

  @override
  Future<void> transferFunds({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    DateTime? date,
  }) async {
    if (fromAccountId == toAccountId) {
      throw const ValidationException(
        'Source and destination accounts must be different',
      );
    }
    if (amountMinor <= 0) {
      throw const ValidationException('Transfer amount must be positive');
    }

    final fromAcc = await _db.accountDao.getAccountById(fromAccountId);
    final toAcc = await _db.accountDao.getAccountById(toAccountId);
    if (fromAcc == null ||
        fromAcc.userId != _userId ||
        fromAcc.deletedAtUtc != null) {
      throw NotFoundException('Source account not found or unauthorized: ');
    }
    if (toAcc == null ||
        toAcc.userId != _userId ||
        toAcc.deletedAtUtc != null) {
      throw NotFoundException(
        'Destination account not found or unauthorized: ',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final transferTx = TransactionEntity(
      id: IdGenerator.uuid(),
      userId: _userId,
      amount: amountMinor,
      type: TransactionType.transfer,
      categoryId: 'cat_other_expense',
      accountId: fromAccountId,
      toAccountId: toAccountId,
      note: note ?? 'Transfer',
      date: (date ?? nowUtc).toUtc(),
      createdAt: nowUtc,
      updatedAt: nowUtc,
      syncStatus: SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.transactionDao.insertTransaction(
        TransactionMapper.toCompanion(transferTx),
      );
      await SyncQueueHelper.enqueueCreate(
        _db,
        userId: _userId,
        entityType: EntityType.transaction,
        entityId: transferTx.id,
        payloadJson: TransactionMapper.toJsonPayload(transferTx),
      );
    });
  }
}
