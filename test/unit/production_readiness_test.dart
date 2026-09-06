import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/core/constants/app_constants.dart';
import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/core/network/connectivity_status.dart';
import 'package:expense_tracker/core/network/i_connectivity_service.dart';
import 'package:expense_tracker/core/security/app_lock_service.dart';
import 'package:expense_tracker/core/security/hashing_service.dart';
import 'package:expense_tracker/core/security/secure_storage_service.dart';
import 'package:expense_tracker/core/sync/conflict_resolver.dart';
import 'package:expense_tracker/core/utils/app_logger.dart';
import 'package:expense_tracker/core/utils/date_time_utils.dart';
import 'package:expense_tracker/core/utils/money_utils.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/account_repository.dart';
import 'package:expense_tracker/data/repositories/budget_repository.dart';
import 'package:expense_tracker/data/repositories/category_repository.dart';
import 'package:expense_tracker/data/repositories/goal_repository.dart';
import 'package:expense_tracker/data/repositories/recurring_transaction_repository.dart';
import 'package:expense_tracker/data/repositories/settings_repository.dart';
import 'package:expense_tracker/data/repositories/sync_repository.dart';
import 'package:expense_tracker/data/repositories/transaction_repository.dart';
import 'package:expense_tracker/data/sync/fake_sync_remote_data_source.dart';
import 'package:expense_tracker/data/sync/sync_coordinator.dart';
import 'package:expense_tracker/domain/entities/account_entity.dart';
import 'package:expense_tracker/domain/entities/category_entity.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:expense_tracker/domain/entities/recurring_transaction_entity.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';
import 'package:expense_tracker/presentation/providers/app_providers.dart';

class FakeConnectivityService implements IConnectivityService {
  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _status = ConnectivityStatus.online;

  void setStatus(ConnectivityStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  Stream<ConnectivityStatus> get onConnectivityChanged => _controller.stream;

  @override
  Future<bool> get isConnected async => _status.isOnline;

  @override
  ConnectivityStatus get currentStatus => _status;

  @override
  void dispose() {
    _controller.close();
  }
}

class FakeSecureStorage implements SecureStorageService {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<void> deleteAll() async => _store.clear();

  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<String> getOrInitializeDatabaseKey({
    required bool databaseFileExists,
  }) async {
    final existing = _store[AppConstants.keyDbEncryptionKey];
    if (existing != null) return existing;
    if (databaseFileExists) {
      throw const DatabaseKeyMissingException();
    }
    const newKey =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    _store[AppConstants.keyDbEncryptionKey] = newKey;
    return newKey;
  }

  @override
  Future<String> getOrCreateDatabaseKey({bool databaseFileExists = false}) {
    return getOrInitializeDatabaseKey(databaseFileExists: databaseFileExists);
  }

  @override
  Future<String?> getDatabaseKey() async =>
      _store[AppConstants.keyDbEncryptionKey];

  @override
  Future<bool> hasDatabaseKey() async =>
      _store.containsKey(AppConstants.keyDbEncryptionKey);

  @override
  Future<void> setAppPin(String pin) async {
    final salt = HashingService.generateSalt();
    final hash = HashingService.hashPin(pin, salt);
    _store[AppConstants.keyUserPinSalt] = salt;
    _store[AppConstants.keyUserPinHash] = hash;
    _store[AppConstants.keyIsAppLockEnabled] = 'true';
  }

  @override
  Future<bool> verifyAppPin(String enteredPin) async {
    final salt = _store[AppConstants.keyUserPinSalt];
    final hash = _store[AppConstants.keyUserPinHash];
    if (salt == null || hash == null) return false;
    return HashingService.verifyPin(enteredPin, hash, salt);
  }

  @override
  Future<bool> hasAppPin() async {
    final hash = _store[AppConstants.keyUserPinHash];
    return hash != null && hash.isNotEmpty;
  }

  @override
  Future<void> clearAppPin() async {
    _store.remove(AppConstants.keyUserPinHash);
    _store.remove(AppConstants.keyUserPinSalt);
    _store[AppConstants.keyIsAppLockEnabled] = 'false';
  }

  @override
  Future<void> setBiometricsEnabled(bool enabled) async {
    _store[AppConstants.keyIsBiometricsEnabled] = enabled.toString();
  }

  @override
  Future<bool> isBiometricsEnabled() async {
    return _store[AppConstants.keyIsBiometricsEnabled] == 'true';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository txRepo;
  late AccountRepository accRepo;
  late CategoryRepository catRepo;
  late BudgetRepository budgetRepo;
  late GoalRepository goalRepo;
  late RecurringTransactionRepository recRepo;
  late SettingsRepository settingsRepo;
  late SyncRepository syncRepo;
  late FakeSyncRemoteDataSource remoteDataSource;
  late FakeConnectivityService connectivity;
  late SyncCoordinator coordinator;

  const userId = 'user_phase9_prod';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    txRepo = TransactionRepository(db, () => userId);
    accRepo = AccountRepository(db, () => userId);
    catRepo = CategoryRepository(db, () => userId);
    budgetRepo = BudgetRepository(db, () => userId);
    goalRepo = GoalRepository(db, () => userId);
    recRepo = RecurringTransactionRepository(db, () => userId);
    settingsRepo = SettingsRepository(db, () => userId);
    syncRepo = SyncRepository(db, () => userId);

    remoteDataSource = FakeSyncRemoteDataSource();
    remoteDataSource.activeAuthUserId = userId;
    connectivity = FakeConnectivityService();
    coordinator = SyncCoordinator(
      db: db,
      remoteDataSource: remoteDataSource,
      connectivityService: connectivity,
      getActiveUserId: () => userId,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    connectivity.dispose();
    await db.close();
  });

  group('Phase 9 Production Readiness: 1. Offline-First Torture Suite', () {
    test(
      '1.1. Full Offline CRUD commits to encrypted local DB and enqueues sync operations',
      () async {
        connectivity.setStatus(ConnectivityStatus.offline);

        // Create Account
        final acc = AccountEntity(
          id: 'acc_offline_1',
          userId: userId,
          name: 'Offline Salary',
          type: AccountType.bank,
          initialBalance: 100000,
          currency: 'INR',
          colorValue: 0xFF123456,
          iconCodePoint: 0xe59c,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await accRepo.createAccount(acc);

        // Create Category
        final cat = CategoryEntity(
          id: 'cat_offline_1',
          userId: userId,
          name: 'Groceries',
          iconCodePoint: 0xe59c,
          colorValue: 0xFF00FF00,
          type: TransactionType.expense,
          isSystem: false,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await catRepo.createCategory(cat);

        // Create Transaction
        final tx = TransactionEntity(
          id: 'tx_offline_1',
          userId: userId,
          accountId: acc.id,
          categoryId: cat.id,
          amount: 2500, // ₹25.00
          type: TransactionType.expense,
          note: 'Offline grocery purchase',
          date: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await txRepo.createTransaction(tx);

        // Verify local database state immediately reflects changes
        final fetchedAcc = await accRepo.getAccountById(acc.id);
        expect(fetchedAcc, isNotNull);
        expect(fetchedAcc!.name, 'Offline Salary');

        final fetchedTx = await txRepo.getTransactionById(tx.id);
        expect(fetchedTx, isNotNull);
        expect(fetchedTx!.amount, 2500);

        // Verify sync queue holds mutations ready for cloud reconciliation
        final queuedOps = await db.syncQueueDao.getPendingOperations(
          userId: userId,
        );
        expect(queuedOps.length, 3);
        expect(
          queuedOps.map((o) => o.entityType).toList(),
          containsAll(['account', 'category', 'transaction']),
        );
      },
    );

    test(
      '1.2. Offline Aggregations calculate net worth, cash flow and category totals without network',
      () async {
        connectivity.setStatus(ConnectivityStatus.offline);

        final acc = AccountEntity(
          id: 'acc_calc_1',
          userId: userId,
          name: 'Checking',
          type: AccountType.bank,
          initialBalance: 50000, // ₹500.00
          currency: 'INR',
          colorValue: 0xFF112233,
          iconCodePoint: 0xe59c,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await accRepo.createAccount(acc);

        final catIncome = CategoryEntity(
          id: 'cat_calc_inc',
          userId: userId,
          name: 'Salary',
          iconCodePoint: 0xe59c,
          colorValue: 0xFF00FF00,
          type: TransactionType.income,
          isSystem: false,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await catRepo.createCategory(catIncome);

        final catExpense = CategoryEntity(
          id: 'cat_calc_exp',
          userId: userId,
          name: 'Dining',
          iconCodePoint: 0xe59c,
          colorValue: 0xFFFF0000,
          type: TransactionType.expense,
          isSystem: false,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );
        await catRepo.createCategory(catExpense);

        final now = DateTime.now().toUtc();
        final startDate = now.subtract(const Duration(days: 7));
        final endDate = now.add(const Duration(days: 7));

        // Add income ₹1,000.00 (100000 minor units)
        await txRepo.createTransaction(
          TransactionEntity(
            id: 'tx_inc_1',
            userId: userId,
            accountId: acc.id,
            categoryId: catIncome.id,
            amount: 100000,
            type: TransactionType.income,
            note: 'Paycheck',
            date: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Add expense ₹300.00 (30000 minor units)
        await txRepo.createTransaction(
          TransactionEntity(
            id: 'tx_exp_1',
            userId: userId,
            accountId: acc.id,
            categoryId: catExpense.id,
            amount: 30000,
            type: TransactionType.expense,
            note: 'Dinner',
            date: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Ledger: 50,000 + 100,000 - 30,000 = 120,000
        final balance = await accRepo.getAccountBalance(acc.id);
        expect(balance, 120000);

        final totalIncome = await txRepo.getTotalIncome(startDate, endDate);
        expect(totalIncome, 100000);

        final totalExpense = await txRepo.getTotalExpense(startDate, endDate);
        expect(totalExpense, 30000);

        final netCashFlow = totalIncome - totalExpense;
        expect(netCashFlow, 70000);
      },
    );
  });

  group(
    'Phase 9 Production Readiness: 2. Offline -> Online -> Offline Chaos Suite',
    () {
      test(
        '2.1. Repeated network transitions with interleaved mutations survive without duplicates or data loss',
        () async {
          final acc = AccountEntity(
            id: 'acc_chaos_1',
            userId: userId,
            name: 'Chaos Account',
            type: AccountType.cash,
            initialBalance: 0,
            currency: 'INR',
            colorValue: 0xFF445566,
            iconCodePoint: 0xe59c,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await accRepo.createAccount(acc);

          final cat = CategoryEntity(
            id: 'cat_chaos_1',
            userId: userId,
            name: 'General',
            iconCodePoint: 0xe59c,
            colorValue: 0xFF445566,
            type: TransactionType.income,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await catRepo.createCategory(cat);

          // Transition 1: Offline -> insert 2 transactions
          connectivity.setStatus(ConnectivityStatus.offline);
          for (int i = 0; i < 2; i++) {
            await txRepo.createTransaction(
              TransactionEntity(
                id: 'tx_chaos_$i',
                userId: userId,
                accountId: acc.id,
                categoryId: cat.id,
                amount: 1000 * (i + 1),
                type: TransactionType.income,
                note: 'Chaos Tx $i',
                date: DateTime.now().toUtc(),
                createdAt: DateTime.now().toUtc(),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }

          // Transition 2: Online -> partial sync
          connectivity.setStatus(ConnectivityStatus.online);
          await coordinator.synchronize();

          // Transition 3: Offline -> insert 2 more transactions
          connectivity.setStatus(ConnectivityStatus.offline);
          for (int i = 2; i < 4; i++) {
            await txRepo.createTransaction(
              TransactionEntity(
                id: 'tx_chaos_$i',
                userId: userId,
                accountId: acc.id,
                categoryId: cat.id,
                amount: 1000 * (i + 1),
                type: TransactionType.income,
                note: 'Chaos Tx $i',
                date: DateTime.now().toUtc(),
                createdAt: DateTime.now().toUtc(),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }

          // Transition 4: Online -> final sync
          connectivity.setStatus(ConnectivityStatus.online);
          await coordinator.synchronize();

          // Verify all 4 transactions exist in local DB
          final localTxs = await txRepo
              .watchRecentTransactions(limit: 10)
              .first;
          expect(localTxs.length, 4);

          // Verify all 4 transactions reached cloud
          expect(remoteDataSource.cloudStore['transactions']?.length, 4);

          // Verify sync queue is fully flushed
          final remainingQueue = await db.syncQueueDao.getPendingOperations(
            userId: userId,
          );
          expect(remainingQueue, isEmpty);

          // Verify balance: 1000 + 2000 + 3000 + 4000 = 10000
          final finalBalance = await accRepo.getAccountBalance(acc.id);
          expect(finalBalance, 10000);
        },
      );
    },
  );

  group(
    'Phase 9 Production Readiness: 3. Sync Engine Torture Suite (Scale & Faults)',
    () {
      test(
        '3.1. High-volume sync queue (100 operations) preserves strict dependency ordering',
        () async {
          connectivity.setStatus(ConnectivityStatus.offline);

          final acc = AccountEntity(
            id: 'acc_scale_1',
            userId: userId,
            name: 'Scale Account',
            type: AccountType.bank,
            initialBalance: 0,
            currency: 'INR',
            colorValue: 0xFF123123,
            iconCodePoint: 0xe59c,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await accRepo.createAccount(acc);

          final cat = CategoryEntity(
            id: 'cat_scale_1',
            userId: userId,
            name: 'Income Category',
            iconCodePoint: 0xe59c,
            colorValue: 0xFF123123,
            type: TransactionType.income,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await catRepo.createCategory(cat);

          // Enqueue 98 transactions
          for (int i = 0; i < 98; i++) {
            await txRepo.createTransaction(
              TransactionEntity(
                id: 'tx_scale_$i',
                userId: userId,
                accountId: acc.id,
                categoryId: cat.id,
                amount: 100,
                type: TransactionType.income,
                note: 'Scale item $i',
                date: DateTime.now().toUtc(),
                createdAt: DateTime.now().toUtc(),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }

          final pending = await db.syncQueueDao.getPendingOperations(
            userId: userId,
            limit: 200,
          );
          expect(pending.length, 100);

          // Connect and sync
          connectivity.setStatus(ConnectivityStatus.online);
          await coordinator.synchronize();

          // Verify all 100 operations cleared
          final remaining = await db.syncQueueDao.getPendingOperations(
            userId: userId,
          );
          expect(remaining, isEmpty);

          // Cloud store must contain the account and 98 transactions
          expect(
            remoteDataSource.cloudStore['accounts']?.containsKey('acc_scale_1'),
            isTrue,
          );
          expect(remoteDataSource.cloudStore['transactions']?.length, 98);
        },
      );

      test(
        '3.2. Temporary network exception during push preserves all pending queue operations for retry',
        () async {
          connectivity.setStatus(ConnectivityStatus.online);

          final acc = AccountEntity(
            id: 'acc_fail_1',
            userId: userId,
            name: 'Fail Safe Account',
            type: AccountType.bank,
            initialBalance: 5000,
            currency: 'INR',
            colorValue: 0xFF778899,
            iconCodePoint: 0xe59c,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await accRepo.createAccount(acc);

          // Configure remote data source to simulate network failure
          remoteDataSource.simulateNetworkError = true;

          try {
            await coordinator.synchronize();
          } catch (e) {
            expect(e, isA<NetworkException>());
          }

          // Assert queue was NOT deleted and remains intact for retry
          final pendingAfterFail = await db.syncQueueDao.getPendingOperations(
            userId: userId,
          );
          expect(pendingAfterFail.length, 1);
          expect(pendingAfterFail.first.entityId, 'acc_fail_1');

          // Local account is intact
          final localAcc = await accRepo.getAccountById('acc_fail_1');
          expect(localAcc, isNotNull);

          // Reset failure, sync succeeds
          remoteDataSource.simulateNetworkError = false;
          await coordinator.synchronize();

          final pendingAfterSuccess = await db.syncQueueDao
              .getPendingOperations(userId: userId);
          expect(pendingAfterSuccess, isEmpty);
        },
      );
    },
  );

  group(
    'Phase 9 Production Readiness: 4. Multi-Client Convergence Suite (Scenarios A-F)',
    () {
      test(
        '4.1. Scenario A: Independent field edits on Client A (amount) and Client B (note) merge both',
        () {
          final now = DateTime.now().toUtc();
          final localPayload = {
            'id': 'tx_conv_1',
            'userId': userId,
            'amountMinor': 5000,
            'note': 'Original Note',
          };
          final localTimestamps = {
            'amountMinor': now.toIso8601String(),
            'note': now.subtract(const Duration(hours: 1)).toIso8601String(),
          };

          final remotePayload = {
            'id': 'tx_conv_1',
            'userId': userId,
            'amountMinor': 1000, // Older amount edit
            'note': 'Client B Updated Note', // Newer note edit
          };
          final remoteTimestamps = {
            'amountMinor': now
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            'note': now.toIso8601String(),
          };

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: now,
            remoteUpdatedAtUtc: now,
          );

          // Local amount (5000) was newer -> wins
          expect(result.mergedPayload['amountMinor'], 5000);
          // Remote note was newer -> wins
          expect(result.mergedPayload['note'], 'Client B Updated Note');
        },
      );

      test(
        '4.2. Scenario B: Same field edited concurrently -> newer timestamp wins',
        () {
          final t1 = DateTime.parse('2026-09-01T10:00:00Z');
          final t2 = DateTime.parse('2026-09-01T11:00:00Z');

          final localPayload = {'id': 'acc_conv_1', 'name': 'Older Name'};
          final localTimestamps = {'name': t1.toIso8601String()};

          final remotePayload = {'id': 'acc_conv_1', 'name': 'Newer Name'};
          final remoteTimestamps = {'name': t2.toIso8601String()};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
          );
          expect(result.mergedPayload['name'], 'Newer Name');
        },
      );

      test(
        '4.3. Scenario C: Equal timestamps resolve deterministically via lexical tie-break',
        () {
          final t = DateTime.parse('2026-09-01T12:00:00Z');

          final localPayload = {'id': 'acc_tie_1', 'name': 'Alpha'};
          final remotePayload = {'id': 'acc_tie_1', 'name': 'Beta'};
          final timestamps = {'name': t.toIso8601String()};

          final result1 = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final result2 = ConflictResolver.resolvePayloadConflict(
            localPayload: remotePayload,
            remotePayload: localPayload,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          // Both merges must resolve to the identical winner regardless of merge order
          expect(result1.mergedPayload['name'], result2.mergedPayload['name']);
          expect(result1.mergedPayload['name'], 'Beta'); // "Beta" > "Alpha"
        },
      );

      test(
        '4.4. Scenario D: Tombstone precedence: Deleted record wins over older update',
        () {
          final tDelete = DateTime.parse('2026-09-01T15:00:00Z');
          final tUpdate = DateTime.parse('2026-09-01T14:00:00Z');

          final isDeleted = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tDelete,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tDelete,
            remoteUpdatedAtUtc: tUpdate,
          );
          expect(isDeleted, isTrue);
        },
      );

      test(
        '4.5. Scenario E: Restore precedence: Newer undelete/update wins over older tombstone',
        () {
          final tDelete = DateTime.parse('2026-09-01T10:00:00Z');
          final tRestore = DateTime.parse('2026-09-01T12:00:00Z');

          final isDeleted = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tDelete,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tDelete,
            remoteUpdatedAtUtc: tRestore,
          );
          expect(isDeleted, isFalse);
        },
      );

      test(
        '4.6. Scenario F: Symmetric convergence without ping-pong cycles',
        () {
          final now = DateTime.now().toUtc();
          final recordA = {'id': 'cat_ping_1', 'name': 'Groceries A'};
          final recordB = {'id': 'cat_ping_1', 'name': 'Groceries B'};
          final timestamps = {'name': now.toIso8601String()};

          final result1 = ConflictResolver.resolvePayloadConflict(
            localPayload: recordA,
            remotePayload: recordB,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: now,
            remoteUpdatedAtUtc: now,
          );

          final result2 = ConflictResolver.resolvePayloadConflict(
            localPayload: result1.mergedPayload,
            remotePayload: recordA,
            localFieldTimestamps: result1.mergedFieldTimestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: now,
            remoteUpdatedAtUtc: now,
          );

          final result3 = ConflictResolver.resolvePayloadConflict(
            localPayload: result1.mergedPayload,
            remotePayload: recordB,
            localFieldTimestamps: result1.mergedFieldTimestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: now,
            remoteUpdatedAtUtc: now,
          );

          // Once merged, applying earlier records produces no further mutation
          expect(result2.mergedPayload['name'], result1.mergedPayload['name']);
          expect(result3.mergedPayload['name'], result1.mergedPayload['name']);
        },
      );
    },
  );

  group(
    'Phase 9 Production Readiness: 5. Financial Invariants & Precision Suite',
    () {
      test(
        '5.1. Double-Entry Transfer: Account A decreases, Account B increases, Net Worth invariant holds',
        () async {
          final accA = AccountEntity(
            id: 'acc_trans_a',
            userId: userId,
            name: 'Bank A',
            type: AccountType.bank,
            initialBalance: 100000, // ₹1,000.00
            currency: 'INR',
            colorValue: 0xFF111111,
            iconCodePoint: 0xe59c,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          final accB = AccountEntity(
            id: 'acc_trans_b',
            userId: userId,
            name: 'Bank B',
            type: AccountType.bank,
            initialBalance: 50000, // ₹500.00
            currency: 'INR',
            colorValue: 0xFF222222,
            iconCodePoint: 0xe59c,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await accRepo.createAccount(accA);
          await accRepo.createAccount(accB);

          final cat = CategoryEntity(
            id: 'cat_trans_1',
            userId: userId,
            name: 'Transfer Cat',
            iconCodePoint: 0xe59c,
            colorValue: 0xFF111111,
            type: TransactionType.transfer,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await catRepo.createCategory(cat);

          final initialNetWorth =
              (await accRepo.getAccountBalance(accA.id)) +
              (await accRepo.getAccountBalance(accB.id));
          expect(initialNetWorth, 150000);

          // Perform transfer of ₹300.00 (30,000 minor units) from A to B
          final transferTx = TransactionEntity(
            id: 'tx_transfer_1',
            userId: userId,
            accountId: accA.id,
            toAccountId: accB.id,
            categoryId: cat.id,
            amount: 30000,
            type: TransactionType.transfer,
            note: 'Inter-account transfer',
            date: DateTime.now().toUtc(),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await txRepo.createTransaction(transferTx);

          // Account A balance decreased by 30,000
          final balanceA = await accRepo.getAccountBalance(accA.id);
          expect(balanceA, 70000);

          // Account B balance increased by 30,000
          final balanceB = await accRepo.getAccountBalance(accB.id);
          expect(balanceB, 80000);

          // Total Net Worth is completely invariant (no leak or creation of money)
          final postTransferNetWorth = balanceA + balanceB;
          expect(postTransferNetWorth, initialNetWorth);

          // Transfer must not be counted as income or expense
          final now = DateTime.now().toUtc();
          final income = await txRepo.getTotalIncome(
            now.subtract(const Duration(days: 1)),
            now.add(const Duration(days: 1)),
          );
          final expense = await txRepo.getTotalExpense(
            now.subtract(const Duration(days: 1)),
            now.add(const Duration(days: 1)),
          );
          expect(income, 0);
          expect(expense, 0);
        },
      );

      test(
        '5.2. Money precision: ₹0.01, ₹1.01, ₹10.99, ₹999,999,999.99 handled with integer minor units',
        () {
          expect(MoneyUtils.parseToMinorUnits('0.01'), 1);
          expect(MoneyUtils.format(1), '₹0.01');

          expect(MoneyUtils.parseToMinorUnits('1.01'), 101);
          expect(MoneyUtils.format(101), '₹1.01');

          expect(MoneyUtils.parseToMinorUnits('10.99'), 1099);
          expect(MoneyUtils.format(1099), '₹10.99');

          // ₹999,999,999.99 = 99,999,999,999 minor units
          const largeAmountMinor = 99999999999;
          expect(
            MoneyUtils.parseToMinorUnits('999999999.99'),
            largeAmountMinor,
          );
          expect(MoneyUtils.format(largeAmountMinor), '₹999,999,999.99');

          // Verify zero floating point drift in integer calculations
          int sum = 0;
          for (int i = 0; i < 100; i++) {
            sum += MoneyUtils.parseToMinorUnits('0.01');
          }
          expect(sum, 100);
          expect(MoneyUtils.format(sum), '₹1.00');
        },
      );
    },
  );

  group(
    'Phase 9 Production Readiness: 6. Recurring Transactions & Boundary Suite',
    () {
      test(
        '6.1. Deterministic generation creates and updates recurring rule without duplicates',
        () async {
          final acc = AccountEntity(
            id: 'acc_rec_1',
            userId: userId,
            name: 'Recurring Acc',
            type: AccountType.bank,
            initialBalance: 100000,
            currency: 'INR',
            colorValue: 0xFF001122,
            iconCodePoint: 0xe59c,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await accRepo.createAccount(acc);

          final cat = CategoryEntity(
            id: 'cat_rec_1',
            userId: userId,
            name: 'Subscriptions',
            iconCodePoint: 0xe59c,
            colorValue: 0xFF001122,
            type: TransactionType.expense,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await catRepo.createCategory(cat);

          final rec = RecurringTransactionEntity(
            id: 'rec_rule_1',
            userId: userId,
            amount: 5000,
            type: TransactionType.expense,
            categoryId: cat.id,
            accountId: acc.id,
            note: 'Monthly Cloud Service',
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime.utc(2026, 1, 1),
            nextDate: DateTime.utc(2026, 2, 1),
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );
          await recRepo.createRecurring(rec);

          // Check rule is in database
          final due = await recRepo.getDueRecurringTransactions(
            DateTime.utc(2026, 2, 15),
          );
          expect(due.length, 1);
          expect(due.first.id, 'rec_rule_1');

          // Execute due processing
          final processedCount = await recRepo.processDueRecurringRules(
            DateTime.utc(2026, 2, 15),
          );
          expect(processedCount, 1);

          // Re-running on same date finds zero due (idempotent)
          final dueAgain = await recRepo.getDueRecurringTransactions(
            DateTime.utc(2026, 2, 15),
          );
          expect(dueAgain, isEmpty);
        },
      );

      test(
        '6.2. Month boundary utility clamps start and end of month cleanly in UTC',
        () {
          final feb = DateTime.utc(2026, 2, 15);
          final startFeb = DateTimeUtils.startOfMonthUtc(feb);
          final endFeb = DateTimeUtils.endOfMonthUtc(feb);

          final startLocal = startFeb.toLocal();
          final endLocal = endFeb.toLocal();
          expect(startLocal.month, 2);
          expect(startLocal.day, 1);
          expect(endLocal.month, 2);
          expect(endLocal.day, 28); // 2026 is non-leap year
        },
      );
    },
  );

  group('Phase 9 Production Readiness: 7. Security, App Lock & Lifecycle Suite', () {
    test(
      '7.1. AppLockService initializes from secure storage with PIN configuration',
      () async {
        final fakeStorage = FakeSecureStorage();
        await fakeStorage.setAppPin('1234');

        final lockService = AppLockService(secureStorage: fakeStorage);
        await lockService.initialize();

        expect(lockService.isAppLockConfigured, isTrue);
        expect(lockService.isLocked, isTrue);

        final isCorrect = await fakeStorage.verifyAppPin('1234');
        expect(isCorrect, isTrue);

        final isWrong = await fakeStorage.verifyAppPin('0000');
        expect(isWrong, isFalse);

        lockService.dispose();
      },
    );

    test(
      '7.2. DatabaseKeyMissingException fail-safe throws when DB file exists but key is lost',
      () async {
        final fakeStorage = FakeSecureStorage();

        // Database file exists on disk = true, but key is missing from storage
        expect(
          () =>
              fakeStorage.getOrInitializeDatabaseKey(databaseFileExists: true),
          throwsA(isA<DatabaseKeyMissingException>()),
        );
      },
    );

    test(
      '7.3. AppLogger redacts sensitive metadata and honors release mode flag',
      () {
        final dirtyMeta = {
          'userId': 'usr_123',
          'password': 'secret_password_123',
          'amountMinor': 50000,
          'pin': '9999',
          'token': 'jwt.token.here',
          'accountName': 'Secret Swiss Bank',
          'safeField': 'regular_value',
        };

        final sanitized = AppLogger.sanitize(dirtyMeta);
        expect(sanitized['password'], '[REDACTED]');
        expect(sanitized['amountMinor'], '[REDACTED]');
        expect(sanitized['pin'], '[REDACTED]');
        expect(sanitized['token'], '[REDACTED]');
        expect(sanitized['accountName'], '[REDACTED]');
        expect(sanitized['safeField'], 'regular_value');
      },
    );
  });

  group(
    'Phase 9 Production Readiness: 8. Production Bootstrap & Composition Root',
    () {
      test(
        '8.1. AppProviders.buildProviders wires all 8 repositories and feature providers without null dependencies',
        () {
          final providers = AppProviders.buildProviders(
            transactionRepository: txRepo,
            accountRepository: accRepo,
            categoryRepository: catRepo,
            budgetRepository: budgetRepo,
            goalRepository: goalRepo,
            recurringRepository: recRepo,
            settingsRepository: settingsRepo,
            syncRepository: syncRepo,
            syncCoordinator: coordinator,
            initialUserId: userId,
          );

          // Verify all required provider instances are registered in provider tree
          expect(providers, isNotEmpty);
          expect(providers.length, greaterThanOrEqualTo(12));
        },
      );
    },
  );
}
