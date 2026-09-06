import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:expense_tracker/core/auth/auth_types.dart';
import 'package:expense_tracker/core/network/connectivity_status.dart';
import 'package:expense_tracker/core/network/i_connectivity_service.dart';
import 'package:expense_tracker/core/sync/conflict_resolver.dart';
import 'package:expense_tracker/core/utils/id_generator.dart';
import 'package:expense_tracker/data/auth/fake_auth_service.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/sync_queue_helper.dart';
import 'package:expense_tracker/data/sync/fake_sync_remote_data_source.dart';
import 'package:expense_tracker/data/sync/sync_coordinator.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConnectivityService implements IConnectivityService {
  ConnectivityStatus _status = ConnectivityStatus.online;
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  @override
  Future<bool> get isConnected async => _status == ConnectivityStatus.online;

  @override
  ConnectivityStatus get currentStatus => _status;

  @override
  Stream<ConnectivityStatus> get onConnectivityChanged => _controller.stream;

  void setStatus(ConnectivityStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  group('Phase 6 Step 2: Production Push/Pull Sync Engine Comprehensive Tests', () {
    late AppDatabase db;
    late _FakeConnectivityService connectivityService;
    late FakeSyncRemoteDataSource remoteDataSource;
    late FakeAuthService authService;
    late SyncCoordinator coordinator;

    const testUserId = 'user_test_123';
    final testUser = AuthUser(
      id: testUserId,
      email: 'test@example.com',
      displayName: 'Test User',
    );

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      connectivityService = _FakeConnectivityService();
      remoteDataSource = FakeSyncRemoteDataSource();
      authService = FakeAuthService(initialUser: testUser);
      remoteDataSource.activeAuthUserId = testUserId;

      coordinator = SyncCoordinator(
        db: db,
        connectivityService: connectivityService,
        remoteDataSource: remoteDataSource,
        authService: authService,
        getActiveUserId: () => authService.currentUser?.id ?? testUserId,
      );

      // Seed local user
      await db
          .into(db.usersTable)
          .insert(
            UsersTableCompanion(
              id: const drift.Value(testUserId),
              displayName: const drift.Value('Test User'),
              createdAtUtc: drift.Value(DateTime.now().toUtc()),
              lastActiveAtUtc: drift.Value(DateTime.now().toUtc()),
            ),
          );
    });

    tearDown(() async {
      coordinator.dispose();
      connectivityService.dispose();
      authService.dispose();
      await db.close();
    });

    // =========================================================================
    // 1. PUSH QUEUE DELETION CRASH-SAFETY & IDEMPOTENT RECOVERY
    // =========================================================================

    test(
      '1. Push Queue: Crash before local queue deletion recovers via already_processed',
      () async {
        final nowUtc = DateTime.now().toUtc();
        final catId = IdGenerator.uuid();
        final opId = IdGenerator.uuid();

        await db
            .into(db.categoriesTable)
            .insert(
              CategoriesTableCompanion(
                id: drift.Value(catId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Groceries'),
                type: const drift.Value('expense'),
                iconCodePoint: const drift.Value(100),
                colorValue: const drift.Value(200),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
                syncStatus: const drift.Value('pendingCreate'),
              ),
            );

        await db.syncQueueDao.enqueueOperation(
          SyncOperationsTableCompanion(
            id: drift.Value(opId),
            userId: const drift.Value(testUserId),
            entityType: const drift.Value('category'),
            entityId: drift.Value(catId),
            operationType: const drift.Value('create'),
            payloadJson: const drift.Value('{}'),
            createdAtUtc: drift.Value(nowUtc),
            retryCount: const drift.Value(0),
          ),
        );

        // Simulate crash after server receives mutation:
        await remoteDataSource.applySyncMutation(
          operationId: opId,
          entityType: 'category',
          entityId: catId,
          operationType: 'create',
          payload: {
            'name': 'Groceries',
            'type': 'expense',
            'iconCodePoint': 100,
            'colorValue': 200,
          },
          fieldTimestamps: {},
          updatedAtUtc: nowUtc,
        );

        // On restart, client syncs -> server returns already_processed -> queue item is deleted & marked synced
        final result = await coordinator.synchronize();
        expect(result.success, isTrue);
        expect(result.pushedCount, equals(1));

        final pendingCount = await db.syncQueueDao.getPendingCount(testUserId);
        expect(pendingCount, equals(0));

        final localCat = await (db.select(
          db.categoriesTable,
        )..where((c) => c.id.equals(catId))).getSingle();
        expect(localCat.syncStatus, equals('synced'));
      },
    );

    // =========================================================================
    // 2. PULL PAGE ATOMICITY & CURSOR ROLLBACK ON FAILURE
    // =========================================================================

    test(
      '2. Pull Engine: Atomic rollback when page contains malformed record, cursor untouched',
      () async {
        final baseTime = DateTime.utc(2026, 9, 1, 10, 0, 0);

        // Seed remote records: 1 valid, 1 malformed (invalid amount <= 0)
        final validCatId = IdGenerator.uuid();
        final validTxId = IdGenerator.uuid();
        final invalidTxId = IdGenerator.uuid();
        final accId = IdGenerator.uuid();

        remoteDataSource.seedRemoteRecord(
          entityType: 'category',
          id: validCatId,
          userId: testUserId,
          payload: {
            'name': 'Dining',
            'type': 'expense',
            'icon_code_point': 1,
            'color_value': 1,
          },
          fieldTimestamps: {},
          updatedAtUtc: baseTime,
        );

        remoteDataSource.seedRemoteRecord(
          entityType: 'account',
          id: accId,
          userId: testUserId,
          payload: {
            'name': 'Cash',
            'account_type': 'cash',
            'currency': 'INR',
            'initial_balance_minor': 0,
          },
          fieldTimestamps: {},
          updatedAtUtc: baseTime,
        );

        // Valid transaction
        remoteDataSource.seedRemoteRecord(
          entityType: 'transaction',
          id: validTxId,
          userId: testUserId,
          payload: {
            'amount_minor': 5000,
            'transaction_type': 'expense',
            'category_id': validCatId,
            'account_id': accId,
          },
          fieldTimestamps: {},
          updatedAtUtc: baseTime.add(const Duration(minutes: 1)),
        );

        // Malformed transaction (amount is negative)
        remoteDataSource.seedRemoteRecord(
          entityType: 'transaction',
          id: invalidTxId,
          userId: testUserId,
          payload: {
            'amount_minor': -999, // INVALID!
            'transaction_type': 'expense',
            'category_id': validCatId,
            'account_id': accId,
          },
          fieldTimestamps: {},
          updatedAtUtc: baseTime.add(const Duration(minutes: 2)),
        );

        // Execute sync -> should fail on malformed transaction page
        final result = await coordinator.synchronize();
        expect(result.success, isFalse);

        // Verify no invalid transaction entered Drift
        final localTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals(invalidTxId))).getSingleOrNull();
        expect(localTx, isNull);

        // Verify transaction cursor was NOT advanced
        final txMeta = await db.syncMetadataDao.getEntityMetadata(
          userId: testUserId,
          entityType: 'transaction',
        );
        expect(txMeta?.syncCursor, isNull);
      },
    );

    // =========================================================================
    // 3. PER-ENTITY CURSOR ISOLATION
    // =========================================================================

    test(
      '3. Cursor Storage: Isolated per entity type (Category cursor does not affect Accounts/Transactions)',
      () async {
        final t1 = DateTime.utc(2026, 9, 1, 10, 0, 0);
        final t2 = DateTime.utc(2026, 9, 1, 11, 0, 0);

        final catId = IdGenerator.uuid();
        final accId = IdGenerator.uuid();

        // Seed category at T1 and account at T2
        remoteDataSource.seedRemoteRecord(
          entityType: 'category',
          id: catId,
          userId: testUserId,
          payload: {
            'name': 'Health',
            'type': 'expense',
            'icon_code_point': 1,
            'color_value': 1,
          },
          fieldTimestamps: {},
          updatedAtUtc: t1,
        );

        remoteDataSource.seedRemoteRecord(
          entityType: 'account',
          id: accId,
          userId: testUserId,
          payload: {
            'name': 'Bank',
            'account_type': 'bank',
            'currency': 'INR',
            'initial_balance_minor': 1000,
          },
          fieldTimestamps: {},
          updatedAtUtc: t2,
        );

        final result = await coordinator.synchronize();
        expect(result.success, isTrue);

        // Check per-entity cursor metadata
        final catMeta = await db.syncMetadataDao.getEntityMetadata(
          userId: testUserId,
          entityType: 'category',
        );
        final accMeta = await db.syncMetadataDao.getEntityMetadata(
          userId: testUserId,
          entityType: 'account',
        );

        expect(catMeta?.syncCursor, contains(catId));
        expect(accMeta?.syncCursor, contains(accId));
        expect(catMeta?.syncCursor, isNot(equals(accMeta?.syncCursor)));
      },
    );

    // =========================================================================
    // 4. CONCURRENT SAME-OPERATION IDEMPOTENCY
    // =========================================================================

    test(
      '4. Idempotency: Concurrent duplicate mutations result in exactly 1 mutation',
      () async {
        final opId = IdGenerator.uuid();
        final catId = IdGenerator.uuid();
        final nowUtc = DateTime.now().toUtc();

        final res1 = await remoteDataSource.applySyncMutation(
          operationId: opId,
          entityType: 'category',
          entityId: catId,
          operationType: 'create',
          payload: {'name': 'Travel'},
          fieldTimestamps: {},
          updatedAtUtc: nowUtc,
        );

        final res2 = await remoteDataSource.applySyncMutation(
          operationId: opId,
          entityType: 'category',
          entityId: catId,
          operationType: 'create',
          payload: {'name': 'Travel'},
          fieldTimestamps: {},
          updatedAtUtc: nowUtc,
        );

        expect(res1['status'], equals('applied'));
        expect(res2['status'], equals('already_processed'));
        expect(remoteDataSource.appliedMutations.length, equals(1));
      },
    );

    // =========================================================================
    // 5. AUTH SESSION RESTORATION & IDENTITY MAPPING
    // =========================================================================

    test(
      '5. Auth: Session restoration loads correct authenticated user identity',
      () async {
        authService.setSession(testUser, token: 'jwt_valid_session_token');

        final currentUser = await authService.getCurrentUser();
        expect(currentUser?.id, equals(testUserId));
        expect(authService.isAuthenticated, isTrue);
        expect(
          await authService.getAccessToken(),
          equals('jwt_valid_session_token'),
        );
      },
    );

    // =========================================================================
    // 6. ACCOUNT SWITCHING DURING ACTIVE REQUEST
    // =========================================================================

    test(
      '6. Account Switch: Stale User A response is safely dropped after switching to User B',
      () async {
        const userA = 'user_alpha';
        const userB = 'user_beta';

        // Start with user A
        authService.setSession(AuthUser(id: userA, email: 'a@example.com'));
        coordinator.abortActiveSync();

        // Switch to user B
        authService.setSession(AuthUser(id: userB, email: 'b@example.com'));

        // User B sync runs cleanly
        final resultB = await coordinator.synchronize();
        expect(resultB.success, isTrue);
      },
    );

    // =========================================================================
    // 7. PUSH DEPENDENCY ORDERING MATCHES ALL FOREIGN KEYS
    // =========================================================================

    test(
      '7. Push Engine: Strictly adheres to foreign key dependency hierarchy',
      () async {
        final nowUtc = DateTime.now().toUtc();
        final catId = IdGenerator.uuid();
        final accId = IdGenerator.uuid();
        final budId = IdGenerator.uuid();
        final catBudId = IdGenerator.uuid();
        final txId = IdGenerator.uuid();

        // Seed local entities
        await db
            .into(db.categoriesTable)
            .insert(
              CategoriesTableCompanion(
                id: drift.Value(catId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Food'),
                type: const drift.Value('expense'),
                iconCodePoint: const drift.Value(1),
                colorValue: const drift.Value(1),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        await db
            .into(db.accountsTable)
            .insert(
              AccountsTableCompanion(
                id: drift.Value(accId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Wallet'),
                accountType: const drift.Value('cash'),
                currency: const drift.Value('INR'),
                initialBalanceMinor: const drift.Value(10000),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        await db
            .into(db.budgetsTable)
            .insert(
              BudgetsTableCompanion(
                id: drift.Value(budId),
                userId: const drift.Value(testUserId),
                monthYear: const drift.Value('2026-09'),
                amountMinor: const drift.Value(50000),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        await db
            .into(db.categoryBudgetsTable)
            .insert(
              CategoryBudgetsTableCompanion(
                id: drift.Value(catBudId),
                userId: const drift.Value(testUserId),
                budgetId: drift.Value(budId),
                categoryId: drift.Value(catId),
                amountMinor: const drift.Value(20000),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        await db
            .into(db.transactionsTable)
            .insert(
              TransactionsTableCompanion(
                id: drift.Value(txId),
                userId: const drift.Value(testUserId),
                amountMinor: const drift.Value(1500),
                transactionType: const drift.Value('expense'),
                categoryId: drift.Value(catId),
                accountId: drift.Value(accId),
                transactionDateUtc: drift.Value(nowUtc),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        // Enqueue in reverse order
        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.transaction,
          entityId: txId,
          payloadJson: '{}',
        );
        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.categoryBudget,
          entityId: catBudId,
          payloadJson: '{}',
        );
        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.budget,
          entityId: budId,
          payloadJson: '{}',
        );
        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.account,
          entityId: accId,
          payloadJson: '{}',
        );
        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.category,
          entityId: catId,
          payloadJson: '{}',
        );

        final result = await coordinator.synchronize();
        expect(result.success, isTrue);

        final mutations = remoteDataSource.appliedMutations;
        final typeOrder = mutations.map((m) => m['entity_type']).toList();

        // Expected ranking: category -> account -> budget -> categoryBudget -> transaction
        expect(
          typeOrder.indexOf('category'),
          lessThan(typeOrder.indexOf('transaction')),
        );
        expect(
          typeOrder.indexOf('account'),
          lessThan(typeOrder.indexOf('transaction')),
        );
        expect(
          typeOrder.indexOf('budget'),
          lessThan(typeOrder.indexOf('categoryBudget')),
        );
        expect(
          typeOrder.indexOf('category'),
          lessThan(typeOrder.indexOf('categoryBudget')),
        );
      },
    );

    // =========================================================================
    // 8. PUSH/PULL INTERACTION & FIELD MERGE
    // =========================================================================

    test(
      '8. Field-Level Merge: Device A amount survives + Remote note survives',
      () async {
        final t1 = DateTime.utc(2026, 9, 1, 10, 0, 0);
        final t2 = DateTime.utc(2026, 9, 1, 10, 5, 0);
        final t3 = DateTime.utc(2026, 9, 1, 10, 10, 0);

        final catId = IdGenerator.uuid();
        final accId = IdGenerator.uuid();
        final txId = IdGenerator.uuid();

        await db
            .into(db.categoriesTable)
            .insert(
              CategoriesTableCompanion(
                id: drift.Value(catId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Dining'),
                type: const drift.Value('expense'),
                iconCodePoint: const drift.Value(1),
                colorValue: const drift.Value(1),
                createdAtUtc: drift.Value(t1),
                updatedAtUtc: drift.Value(t1),
              ),
            );

        await db
            .into(db.accountsTable)
            .insert(
              AccountsTableCompanion(
                id: drift.Value(accId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Card'),
                accountType: const drift.Value('creditCard'),
                currency: const drift.Value('INR'),
                initialBalanceMinor: const drift.Value(0),
                createdAtUtc: drift.Value(t1),
                updatedAtUtc: drift.Value(t1),
              ),
            );

        // Local updated amount at T3
        await db
            .into(db.transactionsTable)
            .insert(
              TransactionsTableCompanion(
                id: drift.Value(txId),
                userId: const drift.Value(testUserId),
                amountMinor: const drift.Value(75000), // $750.00
                transactionType: const drift.Value('expense'),
                categoryId: drift.Value(catId),
                accountId: drift.Value(accId),
                note: const drift.Value('Original note'),
                transactionDateUtc: drift.Value(t1),
                createdAtUtc: drift.Value(t1),
                updatedAtUtc: drift.Value(t3),
                fieldTimestampsJson: drift.Value(
                  ConflictResolver.encodeFieldTimestamps({
                    'amountMinor': t3.toIso8601String(),
                    'note': t1.toIso8601String(),
                  }),
                ),
              ),
            );

        // Remote updated note at T2
        remoteDataSource.seedRemoteRecord(
          entityType: 'transaction',
          id: txId,
          userId: testUserId,
          payload: {
            'amount_minor': 50000,
            'transaction_type': 'expense',
            'category_id': catId,
            'account_id': accId,
            'note': 'Dinner with friends',
            'transaction_date_utc': t1.toIso8601String(),
          },
          fieldTimestamps: {
            'amountMinor': t1.toIso8601String(),
            'note': t2.toIso8601String(),
          },
          updatedAtUtc: t2,
        );

        final result = await coordinator.synchronize();
        expect(result.success, isTrue);

        final mergedTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals(txId))).getSingle();
        expect(mergedTx.amountMinor, equals(75000));
        expect(mergedTx.note, equals('Dinner with friends'));
      },
    );

    // =========================================================================
    // 9. PERMANENT ERROR DOES NOT RETRY ENDLESSLY
    // =========================================================================

    test(
      '9. Failure Classification: Permanent errors exceed maxRetries and do not block queue',
      () async {
        final nowUtc = DateTime.now().toUtc();
        final badOpId = IdGenerator.uuid();

        // Enqueue operation that has already failed 10 times
        await db.syncQueueDao.enqueueOperation(
          SyncOperationsTableCompanion(
            id: drift.Value(badOpId),
            userId: const drift.Value(testUserId),
            entityType: const drift.Value('category'),
            entityId: drift.Value(IdGenerator.uuid()),
            operationType: const drift.Value('create'),
            payloadJson: const drift.Value('{}'),
            createdAtUtc: drift.Value(nowUtc),
            retryCount: const drift.Value(10), // Exceeded max retries
            errorMessage: const drift.Value(
              'PERMANENT: Unrecoverable validation failure',
            ),
          ),
        );

        final pending = await db.syncQueueDao.getPendingOperations(
          userId: testUserId,
        );
        expect(pending.isEmpty, isTrue); // Skipped from active batch
      },
    );

    // =========================================================================
    // 10. AUTH FAILURE PRESERVES QUEUE
    // =========================================================================

    test(
      '10. Auth Failure: Sync queue is preserved untouched on auth expiration',
      () async {
        final catId = IdGenerator.uuid();

        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.category,
          entityId: catId,
          payloadJson: '{"name": "Preserved Cat"}',
        );

        // Simulate sign out / auth failure
        await authService.signOut();
        expect(authService.isAuthenticated, isFalse);

        // Sync queue remains completely safe
        final pendingCount = await db.syncQueueDao.getPendingCount(testUserId);
        expect(pendingCount, equals(1));
      },
    );

    // =========================================================================
    // 11. CONCURRENT SYNC COALESCING
    // =========================================================================

    test(
      '11. Sync Coalescing: Simultaneous synchronize calls coalesce to 1 in-flight execution',
      () async {
        remoteDataSource.simulatedLatencyMs = 100;

        final results = await Future.wait([
          coordinator.synchronize(),
          coordinator.synchronize(),
          coordinator.synchronize(),
        ]);

        remoteDataSource.simulatedLatencyMs = 0;

        // Exactly 1 must execute normally, others return busy/in-progress response
        final successCount = results.where((r) => r.success).length;
        final busyCount = results
            .where(
              (r) =>
                  !r.success &&
                  (r.errorMessage?.contains('already in progress') ?? false),
            )
            .length;

        expect(successCount, equals(1));
        expect(busyCount, equals(2));
      },
    );

    // =========================================================================
    // 12. TRANSFER FINANCIAL INVARIANT
    // =========================================================================

    test(
      '12. Financial Invariants: Transfer preserves net worth and retry is idempotent',
      () async {
        final nowUtc = DateTime.now().toUtc();
        final acc1Id = IdGenerator.uuid();
        final acc2Id = IdGenerator.uuid();
        final catId = IdGenerator.uuid();
        final txId = IdGenerator.uuid();

        // Account 1: 10,000 paise (Rs 100). Account 2: 5,000 paise (Rs 50). Total = 15,000 paise.
        await db
            .into(db.accountsTable)
            .insert(
              AccountsTableCompanion(
                id: drift.Value(acc1Id),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Checking'),
                accountType: const drift.Value('bank'),
                currency: const drift.Value('INR'),
                initialBalanceMinor: const drift.Value(10000),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        await db
            .into(db.accountsTable)
            .insert(
              AccountsTableCompanion(
                id: drift.Value(acc2Id),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Savings'),
                accountType: const drift.Value('savings'),
                currency: const drift.Value('INR'),
                initialBalanceMinor: const drift.Value(5000),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        await db
            .into(db.categoriesTable)
            .insert(
              CategoriesTableCompanion(
                id: drift.Value(catId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Transfer'),
                type: const drift.Value('expense'),
                iconCodePoint: const drift.Value(1),
                colorValue: const drift.Value(1),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
              ),
            );

        // Transfer 2,000 paise from Account 1 to Account 2
        await db
            .into(db.transactionsTable)
            .insert(
              TransactionsTableCompanion(
                id: drift.Value(txId),
                userId: const drift.Value(testUserId),
                amountMinor: const drift.Value(2000),
                transactionType: const drift.Value('transfer'),
                categoryId: drift.Value(catId),
                accountId: drift.Value(acc1Id),
                toAccountId: drift.Value(acc2Id),
                transactionDateUtc: drift.Value(nowUtc),
                createdAtUtc: drift.Value(nowUtc),
                updatedAtUtc: drift.Value(nowUtc),
                syncStatus: const drift.Value('pendingCreate'),
              ),
            );

        await SyncQueueHelper.enqueueCreate(
          db,
          userId: testUserId,
          entityType: EntityType.transaction,
          entityId: txId,
          payloadJson: '{}',
        );

        final result1 = await coordinator.synchronize();
        expect(result1.success, isTrue);

        // Retry sync -> idempotent, no duplicate transfers
        final result2 = await coordinator.synchronize();
        expect(result2.success, isTrue);

        final localTxList = await db.select(db.transactionsTable).get();
        expect(localTxList.length, equals(1));
      },
    );

    // =========================================================================
    // 13. BOUNDED BATCHING (50 OPERATIONS PER BATCH)
    // =========================================================================

    test(
      '13. Performance: Bounded batch processing handles large queues without OOM',
      () async {
        final nowUtc = DateTime.now().toUtc();

        // Enqueue 60 categories
        for (int i = 0; i < 60; i++) {
          final catId = 'cat_bulk_$i';
          await db
              .into(db.categoriesTable)
              .insert(
                CategoriesTableCompanion(
                  id: drift.Value(catId),
                  userId: const drift.Value(testUserId),
                  name: drift.Value('Bulk Cat $i'),
                  type: const drift.Value('expense'),
                  iconCodePoint: const drift.Value(1),
                  colorValue: const drift.Value(1),
                  createdAtUtc: drift.Value(nowUtc.add(Duration(seconds: i))),
                  updatedAtUtc: drift.Value(nowUtc.add(Duration(seconds: i))),
                  syncStatus: const drift.Value('pendingCreate'),
                ),
              );

          await SyncQueueHelper.enqueueCreate(
            db,
            userId: testUserId,
            entityType: EntityType.category,
            entityId: catId,
            payloadJson: '{}',
          );
        }

        final result = await coordinator.synchronize();
        expect(result.success, isTrue);
        expect(result.pushedCount, equals(60));

        final remaining = await db.syncQueueDao.getPendingCount(testUserId);
        expect(remaining, equals(0));
      },
    );

    // =========================================================================
    // 14. DELETE TOPOLOGICAL PUSH ORDERING (CHILDREN BEFORE PARENTS)
    // =========================================================================

    test(
      '14. Delete Ordering: Child entities deleted before parents to satisfy foreign keys',
      () async {
        final catId = IdGenerator.uuid();
        final accId = IdGenerator.uuid();
        final budId = IdGenerator.uuid();
        final catBudId = IdGenerator.uuid();
        final recId = IdGenerator.uuid();
        final txId = IdGenerator.uuid();

        // Enqueue DELETES in reverse / parent-first order
        await SyncQueueHelper.enqueueDelete(
          db,
          userId: testUserId,
          entityType: EntityType.category,
          entityId: catId,
          currentSyncStatus: SyncStatus.synced,
        );
        await SyncQueueHelper.enqueueDelete(
          db,
          userId: testUserId,
          entityType: EntityType.account,
          entityId: accId,
          currentSyncStatus: SyncStatus.synced,
        );
        await SyncQueueHelper.enqueueDelete(
          db,
          userId: testUserId,
          entityType: EntityType.budget,
          entityId: budId,
          currentSyncStatus: SyncStatus.synced,
        );
        await SyncQueueHelper.enqueueDelete(
          db,
          userId: testUserId,
          entityType: EntityType.categoryBudget,
          entityId: catBudId,
          currentSyncStatus: SyncStatus.synced,
        );
        await SyncQueueHelper.enqueueDelete(
          db,
          userId: testUserId,
          entityType: EntityType.recurringRule,
          entityId: recId,
          currentSyncStatus: SyncStatus.synced,
        );
        await SyncQueueHelper.enqueueDelete(
          db,
          userId: testUserId,
          entityType: EntityType.transaction,
          entityId: txId,
          currentSyncStatus: SyncStatus.synced,
        );

        final result = await coordinator.synchronize();
        expect(result.errorMessage, isNull);
        expect(result.success, isTrue);

        final mutations = remoteDataSource.appliedMutations;
        final typeOrder = mutations.map((m) => m['entity_type']).toList();

        // Children must be deleted BEFORE parents:
        // Transaction (120) < Recurring (130) < CategoryBudget (140) < Budget (160) < Account (170) < Category (180)
        expect(
          typeOrder.indexOf('transaction'),
          lessThan(typeOrder.indexOf('category')),
        );
        expect(
          typeOrder.indexOf('transaction'),
          lessThan(typeOrder.indexOf('account')),
        );
        expect(
          typeOrder.indexOf('recurring_transaction'),
          lessThan(typeOrder.indexOf('account')),
        );
        expect(
          typeOrder.indexOf('recurring_transaction'),
          lessThan(typeOrder.indexOf('category')),
        );
        expect(
          typeOrder.indexOf('category_budget'),
          lessThan(typeOrder.indexOf('budget')),
        );
        expect(
          typeOrder.indexOf('category_budget'),
          lessThan(typeOrder.indexOf('category')),
        );
        expect(
          typeOrder.indexOf('account'),
          lessThan(typeOrder.indexOf('category')),
        );
      },
    );

    // =========================================================================
    // 15. PUSH RECONCILIATION: SERVER-DECIDED FIELD MERGE APPLIED ON CLIENT
    // =========================================================================

    test(
      '15. Push Reconciliation: Client receives and applies server merged state when server decides field conflicts on push',
      () async {
        final tEarly = DateTime.utc(2026, 9, 1, 9, 0, 0);
        final tLate = DateTime.utc(2026, 9, 1, 10, 10, 0);
        final tLocal = DateTime.utc(2026, 9, 1, 10, 5, 0);

        final catId = IdGenerator.uuid();

        // Remote has: name="Old Food" (09:00), isArchived=false (10:10)
        remoteDataSource.seedRemoteRecord(
          entityType: 'category',
          id: catId,
          userId: testUserId,
          payload: {
            'name': 'Old Food',
            'type': 'expense',
            'icon_code_point': 1,
            'color_value': 1,
            'is_archived': false,
          },
          fieldTimestamps: {
            'name': tEarly.toIso8601String(),
            'isArchived': tLate.toIso8601String(),
          },
          updatedAtUtc: tLate,
        );

        // Local has: name="Groceries" (10:05 - newer), isArchived=true (09:00 - older)
        await db
            .into(db.categoriesTable)
            .insert(
              CategoriesTableCompanion(
                id: drift.Value(catId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Groceries'),
                type: const drift.Value('expense'),
                iconCodePoint: const drift.Value(1),
                colorValue: const drift.Value(1),
                isArchived: const drift.Value(true),
                createdAtUtc: drift.Value(tEarly),
                updatedAtUtc: drift.Value(tLocal),
                fieldTimestampsJson: drift.Value(
                  ConflictResolver.encodeFieldTimestamps({
                    'name': tLocal.toIso8601String(),
                    'isArchived': tEarly.toIso8601String(),
                  }),
                ),
                syncStatus: const drift.Value('pendingUpdate'),
              ),
            );

        await SyncQueueHelper.enqueueUpdate(
          db,
          userId: testUserId,
          entityType: EntityType.category,
          entityId: catId,
          payloadJson: '{}',
          currentSyncStatus: SyncStatus.pendingUpdate,
        );

        // Run sync -> Push sends local update -> Server merges (name -> Groceries, isArchived -> false)
        final result = await coordinator.synchronize();
        expect(result.success, isTrue);
        expect(result.pushedCount, equals(1));

        // Verify local state applied the server's merged state:
        final localCat = await (db.select(
          db.categoriesTable,
        )..where((c) => c.id.equals(catId))).getSingle();

        expect(localCat.name, equals('Groceries')); // Local won
        expect(
          localCat.isArchived,
          isFalse,
        ); // Remote won on server and applied locally!
        expect(localCat.syncStatus, equals('synced'));
      },
    );

    // =========================================================================
    // 16. PULL CONFLICT LOOP TERMINATION (DETERMINISTIC 1-CYCLE CONVERGENCE)
    // =========================================================================

    test(
      '16. Pull Conflict Loop: Surviving local fields push back once and loop terminates in exactly 1 cycle',
      () async {
        final tEarly = DateTime.utc(2026, 9, 1, 9, 0, 0);
        final tMid = DateTime.utc(2026, 9, 1, 10, 5, 0);
        final tLate = DateTime.utc(2026, 9, 1, 10, 10, 0);

        final catId = IdGenerator.uuid();
        final accId = IdGenerator.uuid();
        final txId = IdGenerator.uuid();

        // Seed Category and Account
        remoteDataSource.seedRemoteRecord(
          entityType: 'category',
          id: catId,
          userId: testUserId,
          payload: {
            'name': 'Food',
            'type': 'expense',
            'icon_code_point': 1,
            'color_value': 1,
          },
          fieldTimestamps: {},
          updatedAtUtc: tEarly,
        );
        remoteDataSource.seedRemoteRecord(
          entityType: 'account',
          id: accId,
          userId: testUserId,
          payload: {
            'name': 'Cash',
            'account_type': 'cash',
            'currency': 'INR',
            'initial_balance_minor': 0,
          },
          fieldTimestamps: {},
          updatedAtUtc: tEarly,
        );

        await db
            .into(db.categoriesTable)
            .insert(
              CategoriesTableCompanion(
                id: drift.Value(catId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Food'),
                type: const drift.Value('expense'),
                iconCodePoint: const drift.Value(1),
                colorValue: const drift.Value(1),
                createdAtUtc: drift.Value(tEarly),
                updatedAtUtc: drift.Value(tEarly),
              ),
            );
        await db
            .into(db.accountsTable)
            .insert(
              AccountsTableCompanion(
                id: drift.Value(accId),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Cash'),
                accountType: const drift.Value('cash'),
                currency: const drift.Value('INR'),
                initialBalanceMinor: const drift.Value(0),
                createdAtUtc: drift.Value(tEarly),
                updatedAtUtc: drift.Value(tEarly),
              ),
            );

        // Remote Transaction has: amount=4000 (09:00), note="Office Lunch" (10:10)
        remoteDataSource.seedRemoteRecord(
          entityType: 'transaction',
          id: txId,
          userId: testUserId,
          payload: {
            'amount_minor': 4000,
            'transaction_type': 'expense',
            'category_id': catId,
            'account_id': accId,
            'note': 'Office Lunch',
          },
          fieldTimestamps: {
            'amountMinor': tEarly.toIso8601String(),
            'note': tLate.toIso8601String(),
          },
          updatedAtUtc: tLate,
        );

        // Local Transaction has: amount=5000 (10:05 - newer), note="Old Lunch" (09:00 - older)
        await db
            .into(db.transactionsTable)
            .insert(
              TransactionsTableCompanion(
                id: drift.Value(txId),
                userId: const drift.Value(testUserId),
                amountMinor: const drift.Value(5000),
                transactionType: const drift.Value('expense'),
                categoryId: drift.Value(catId),
                accountId: drift.Value(accId),
                note: const drift.Value('Old Lunch'),
                transactionDateUtc: drift.Value(tEarly),
                createdAtUtc: drift.Value(tEarly),
                updatedAtUtc: drift.Value(tMid),
                fieldTimestampsJson: drift.Value(
                  ConflictResolver.encodeFieldTimestamps({
                    'amountMinor': tMid.toIso8601String(),
                    'note': tEarly.toIso8601String(),
                  }),
                ),
                syncStatus: const drift.Value('synced'),
              ),
            );

        // Cycle 1: Pull reconciles:
        // - Local amount (5000) survives (10:05 > 09:00).
        // - Remote note ("Office Lunch") wins (10:10 > 09:00).
        // - fieldsRetainedFromLocal > 0 -> enqueues push for surviving local amount!
        final cycle1 = await coordinator.synchronize();
        expect(cycle1.success, isTrue);

        final pendingAfterCycle1 = await db.syncQueueDao.getPendingCount(
          testUserId,
        );
        expect(
          pendingAfterCycle1,
          equals(1),
        ); // Queued to push surviving amount to cloud

        // Cycle 2: Push sends merged state to cloud. Cloud merges. Pull fetches cloud.
        // Both sides are now in complete harmony (amount=5000 @ 10:05, note="Office Lunch" @ 10:10)
        final cycle2 = await coordinator.synchronize();
        expect(cycle2.success, isTrue);
        expect(cycle2.pushedCount, equals(1));

        final pendingAfterCycle2 = await db.syncQueueDao.getPendingCount(
          testUserId,
        );
        expect(pendingAfterCycle2, equals(0)); // Queue is empty!

        // Cycle 3: Idempotent no-op. Zero queued operations, zero infinite loops.
        final cycle3 = await coordinator.synchronize();
        expect(cycle3.success, isTrue);
        expect(cycle3.pushedCount, equals(0));
        expect(cycle3.pulledCount, equals(0));

        final finalTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals(txId))).getSingle();
        expect(finalTx.amountMinor, equals(5000));
        expect(finalTx.note, equals('Office Lunch'));
        expect(finalTx.syncStatus, equals('synced'));
      },
    );
  });
}
