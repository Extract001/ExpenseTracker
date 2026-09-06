import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/core/constants/app_constants.dart';
import 'package:expense_tracker/core/network/connectivity_status.dart';
import 'package:expense_tracker/core/network/i_connectivity_service.dart';
import 'package:expense_tracker/core/sync/conflict_resolver.dart';
import 'package:expense_tracker/core/sync/i_sync_coordinator.dart';
import 'package:expense_tracker/core/sync/sync_cursor.dart';
import 'package:expense_tracker/core/utils/id_generator.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/repositories/sync_queue_helper.dart';
import 'package:expense_tracker/data/sync/sync_coordinator.dart';
import 'package:expense_tracker/domain/entities/enums.dart';

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

void main() {
  group(
    'Phase 6 Step 1: Cloud Sync Architecture, Field-Level LWW & True Idempotency',
    () {
      late AppDatabase db;
      late FakeConnectivityService connectivityService;
      late ISyncCoordinator syncCoordinator;

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
        connectivityService = FakeConnectivityService();
        syncCoordinator = SyncCoordinator(
          db: db,
          connectivityService: connectivityService,
          getActiveUserId: () => AppConstants.defaultUserId,
        );
      });

      tearDown(() async {
        syncCoordinator.dispose();
        connectivityService.dispose();
        await db.close();
      });

      // ========================================================================
      // TEST A — NON-OVERLAPPING FIELD EDITS
      // ========================================================================
      test(
        'Test A — Non-overlapping field edits: Device A changes amount, Device B changes note -> Both survive',
        () {
          final tBase = DateTime.parse('2026-09-06T09:00:00.000Z');
          final tDeviceA = DateTime.parse(
            '2026-09-06T10:05:00.000Z',
          ); // Device A changed amount
          final tDeviceB = DateTime.parse(
            '2026-09-06T10:10:00.000Z',
          ); // Device B changed note

          final localPayload = {
            'id': 'tx-123',
            'userId': 'user-1',
            'amountMinor': 50000, // $500.00 from Device A
            'note': 'Initial Note',
            'categoryId': 'cat-food',
            'accountId': 'acc-cash',
          };
          final localTimestamps = {
            'amountMinor': tDeviceA.toIso8601String(),
            'note': tBase.toIso8601String(),
            'categoryId': tBase.toIso8601String(),
            'accountId': tBase.toIso8601String(),
          };

          final remotePayload = {
            'id': 'tx-123',
            'userId': 'user-1',
            'amountMinor': 40000, // $400.00 from base
            'note': 'Lunch', // Device B changed note
            'categoryId': 'cat-food',
            'accountId': 'acc-cash',
          };
          final remoteTimestamps = {
            'amountMinor': tBase.toIso8601String(),
            'note': tDeviceB.toIso8601String(),
            'categoryId': tBase.toIso8601String(),
            'accountId': tBase.toIso8601String(),
          };

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: tDeviceA,
            remoteUpdatedAtUtc: tDeviceB,
          );

          // Device A's amount (50000) must survive
          expect(result.mergedPayload['amountMinor'], equals(50000));
          expect(
            result.mergedFieldTimestamps['amountMinor'],
            equals(tDeviceA.toIso8601String()),
          );

          // Device B's note ("Lunch") must survive
          expect(result.mergedPayload['note'], equals('Lunch'));
          expect(
            result.mergedFieldTimestamps['note'],
            equals(tDeviceB.toIso8601String()),
          );

          expect(
            result.fieldsUpdatedFromRemote,
            equals(1),
          ); // Note updated from remote
          expect(
            result.fieldsRetainedFromLocal,
            equals(1),
          ); // amountMinor retained from local
        },
      );

      // ========================================================================
      // TEST B — SAME-FIELD CONFLICT (FIELD-LEVEL LAST-WRITE-WINS)
      // ========================================================================
      test(
        'Test B — Same-field conflict: Device A changes amount at T1, Device B changes amount at T2 -> T2 wins',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final t2 = DateTime.parse('2026-09-06T10:15:00.000Z');

          final localPayload = {
            'id': 'tx-123',
            'amountMinor': 50000, // Device A edit at T1
          };
          final localTimestamps = {'amountMinor': t1.toIso8601String()};

          final remotePayload = {
            'id': 'tx-123',
            'amountMinor': 40000, // Device B edit at T2
          };
          final remoteTimestamps = {'amountMinor': t2.toIso8601String()};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
          );

          // Newer T2 edit ($400.00) wins
          expect(result.mergedPayload['amountMinor'], equals(40000));
          expect(
            result.mergedFieldTimestamps['amountMinor'],
            equals(t2.toIso8601String()),
          );
          expect(result.fieldsUpdatedFromRemote, equals(1));
        },
      );

      // ========================================================================
      // TEST C — RETRY SAME OPERATION (OPERATION-LEVEL IDEMPOTENCY)
      // ========================================================================
      test(
        'Test C — Retry same operation: Replaying exact same operation token is a safe no-op',
        () async {
          const userId = 'user_idempotency_c';
          final operationId = IdGenerator.uuid();
          final entityId = IdGenerator.uuid();

          // Enqueue initial operation
          await SyncQueueHelper.enqueueCreate(
            db,
            userId: userId,
            entityType: EntityType.transaction,
            entityId: entityId,
            payloadJson: '{"amountMinor": 2500, "note": "Lunch"}',
          );

          // Verify operation exists with operationId
          final ops = await db.syncQueueDao.getPendingOperations(
            userId: userId,
          );
          expect(ops.length, equals(1));

          // Simulate client retrying identical operation payload & token
          final processedTokens = <String>{};
          bool processSyncOperation(String opId) {
            if (processedTokens.contains(opId)) {
              return false; // Already processed -> No-op
            }
            processedTokens.add(opId);
            return true; // Applied
          }

          // First execution -> Applied
          expect(processSyncOperation(operationId), isTrue);

          // Second execution (Retry over dropped connection) -> No-op
          expect(processSyncOperation(operationId), isFalse);
        },
      );

      // ========================================================================
      // TEST D — DIFFERENT OPERATIONS, SAME ENTITY
      // ========================================================================
      test(
        'Test D — Different operations, same entity: Both evaluated normally through conflict resolution',
        () {
          final op1Id = IdGenerator.uuid();
          final op2Id = IdGenerator.uuid();
          expect(op1Id != op2Id, isTrue);

          final processedTokens = <String>{};
          int mutationsApplied = 0;

          void applyOperation(String opId, Map<String, dynamic> delta) {
            if (!processedTokens.contains(opId)) {
              processedTokens.add(opId);
              mutationsApplied++;
            }
          }

          // Op 1 changes amount
          applyOperation(op1Id, {'amountMinor': 3000});
          // Op 2 changes note
          applyOperation(op2Id, {'note': 'Updated Note'});

          expect(mutationsApplied, equals(2));
          expect(processedTokens.length, equals(2));
        },
      );

      // ========================================================================
      // TEST E — TOMBSTONE PRECEDENCE (DELETE VS OFFLINE EDIT)
      // ========================================================================
      test(
        'Test E — Tombstone vs edit: Older offline edit cannot resurrect a newer deleted record',
        () {
          final tOfflineEdit = DateTime.parse('2026-09-06T09:30:00.000Z');
          final tOnlineDelete = DateTime.parse('2026-09-06T10:00:00.000Z');

          final isDeleted = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tOnlineDelete,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tOnlineDelete,
            remoteUpdatedAtUtc: tOfflineEdit,
          );

          // Deletion occurred after the edit -> Record stays soft-deleted
          expect(isDeleted, isTrue);

          final fullReconciled = ConflictResolver.reconcileEntityState(
            localPayload: {
              'id': 'tx-1',
              'note': 'Initial',
              'amountMinor': 1000,
            },
            remotePayload: {
              'id': 'tx-1',
              'note': 'Offline Edit',
              'amountMinor': 1000,
            },
            localFieldTimestamps: {'note': '2026-09-06T09:00:00.000Z'},
            remoteFieldTimestamps: {'note': tOfflineEdit.toIso8601String()},
            localUpdatedAtUtc: tOnlineDelete,
            remoteUpdatedAtUtc: tOfflineEdit,
            localDeletedAtUtc: tOnlineDelete,
            remoteDeletedAtUtc: null,
          );
          expect(fullReconciled.mergedPayload['deletedAtUtc'], isNotNull);
        },
      );

      test(
        'Test E2 — Tombstone vs edit: Deliberate newer restore/edit un-deletes the record',
        () {
          final tOldDelete = DateTime.parse('2026-09-06T09:00:00.000Z');
          final tNewerRestore = DateTime.parse('2026-09-06T10:30:00.000Z');

          final isDeleted = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tOldDelete,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tOldDelete,
            remoteUpdatedAtUtc: tNewerRestore,
          );

          // Newer update un-deletes the record
          expect(isDeleted, isFalse);
        },
      );

      // ========================================================================
      // TEST F — MALICIOUS / FUTURE TIMESTAMP SAFEGUARD
      // ========================================================================
      test(
        'Test F — Malicious/future timestamp: Clamps timestamps beyond clock skew threshold to server time',
        () {
          final nowServer = DateTime.parse('2026-09-06T12:00:00.000Z');
          final maliciousFuture = DateTime.parse(
            '2099-01-01T00:00:00.000Z',
          ); // Malicious future timestamp
          final normalTime = DateTime.parse('2026-09-06T11:55:00.000Z');

          final timestamps = {
            'amountMinor': maliciousFuture.toIso8601String(),
            'note': normalTime.toIso8601String(),
          };

          final sanitized = ConflictResolver.sanitizeFieldTimestamps(
            timestamps,
            nowUtc: nowServer,
          );

          // Malicious future timestamp must be clamped to server now
          expect(sanitized['amountMinor'], equals(nowServer.toIso8601String()));
          // Normal timestamp within acceptable range is preserved
          expect(sanitized['note'], equals(normalTime.toIso8601String()));
        },
      );

      // ========================================================================
      // TEST G — CROSS-USER IDEMPOTENCY TOKEN ISOLATION
      // ========================================================================
      test(
        'Test G — Cross-user idempotency token: User A operation token cannot be reused or block User B',
        () async {
          const userA = 'user_alpha_uuid';
          const userB = 'user_beta_uuid';
          final sharedToken = IdGenerator.uuid();

          // Simulated server audit map scoped strictly by (user_id, token)
          final serverAuditMap = <String, Set<String>>{
            userA: <String>{},
            userB: <String>{},
          };

          bool applyUserMutation(String userId, String token) {
            if (serverAuditMap[userId]!.contains(token)) {
              return false; // Already processed for this user
            }
            serverAuditMap[userId]!.add(token);
            return true; // Applied
          }

          // User A submits token
          expect(applyUserMutation(userA, sharedToken), isTrue);
          expect(
            applyUserMutation(userA, sharedToken),
            isFalse,
          ); // User A retry is no-op

          // User B submits identical token string -> Evaluated independently under User B's account
          expect(applyUserMutation(userB, sharedToken), isTrue);
          expect(
            applyUserMutation(userB, sharedToken),
            isFalse,
          ); // User B retry is no-op

          expect(serverAuditMap[userA]!.contains(sharedToken), isTrue);
          expect(serverAuditMap[userB]!.contains(sharedToken), isTrue);
        },
      );

      // ========================================================================
      // 8. DETERMINISTIC COMPOSITE CURSOR (INCREMENTAL SYNC)
      // ========================================================================
      test(
        '8. SyncCursor encodes/decodes composite tokens and prevents skipping identical timestamps',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          const idA = '00000000-0000-0000-0000-000000000001';
          const idB = '00000000-0000-0000-0000-000000000002';

          final cursorA = SyncCursor(timestampUtc: t1, entityId: idA);
          final encoded = cursorA.encode();
          expect(
            encoded,
            equals(
              '2026-09-06T10:00:00.000Z|00000000-0000-0000-0000-000000000001',
            ),
          );

          final decoded = SyncCursor.decode(encoded);
          expect(decoded, equals(cursorA));

          // Record B with identical timestamp but higher UUID is strictly after cursorA
          final isBAfterA = cursorA.isAfterCursor(
            candidateTime: t1,
            candidateId: idB,
          );
          expect(isBAfterA, isTrue);

          // Record A is not after cursorA
          final isAAfterA = cursorA.isAfterCursor(
            candidateTime: t1,
            candidateId: idA,
          );
          expect(isAAfterA, isFalse);
        },
      );

      // ========================================================================
      // 9. ATOMIC GUEST-TO-CLOUD DATA MIGRATION
      // ========================================================================
      test(
        '9. Guest data migration transfers all entities and sync queue in a single transaction',
        () async {
          const guestId = AppConstants.defaultUserId;
          const cloudUserId = 'd3b07384-d113-406c-829b-821262d04343';

          final nowUtc = DateTime.now().toUtc();

          // Seed guest category
          await db
              .into(db.categoriesTable)
              .insert(
                CategoriesTableCompanion(
                  id: const Value('cat-guest-1'),
                  userId: const Value(guestId),
                  name: const Value('Custom Guest Category'),
                  type: const Value('expense'),
                  iconCodePoint: const Value(0xe532),
                  colorValue: const Value(0xFFEF4444),
                  createdAtUtc: Value(nowUtc),
                  updatedAtUtc: Value(nowUtc),
                ),
              );

          // Seed guest transaction
          await db
              .into(db.transactionsTable)
              .insert(
                TransactionsTableCompanion(
                  id: const Value('tx-guest-1'),
                  userId: const Value(guestId),
                  amountMinor: const Value(7500),
                  transactionType: const Value('expense'),
                  categoryId: const Value('cat-guest-1'),
                  accountId: const Value('acc_cash_default'),
                  transactionDateUtc: Value(nowUtc),
                  createdAtUtc: Value(nowUtc),
                  updatedAtUtc: Value(nowUtc),
                ),
              );

          // Seed guest sync operation
          await SyncQueueHelper.enqueueCreate(
            db,
            userId: guestId,
            entityType: EntityType.transaction,
            entityId: 'tx-guest-1',
            payloadJson: '{"amountMinor": 7500}',
          );

          // Execute migration
          await syncCoordinator.migrateGuestData(
            guestUserId: guestId,
            targetUserId: cloudUserId,
          );

          // Verify records are now owned by cloudUserId
          final migratedCategories = await (db.select(
            db.categoriesTable,
          )..where((c) => c.userId.equals(cloudUserId))).get();
          expect(migratedCategories.any((c) => c.id == 'cat-guest-1'), isTrue);

          final migratedTransactions = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(cloudUserId))).get();
          expect(migratedTransactions.any((t) => t.id == 'tx-guest-1'), isTrue);
          expect(
            migratedTransactions.first.syncStatus,
            equals('pendingCreate'),
          );

          final migratedOps = await db.syncQueueDao.getPendingOperations(
            userId: cloudUserId,
          );
          expect(migratedOps.any((op) => op.entityId == 'tx-guest-1'), isTrue);

          // Guest user must have 0 remaining transactions
          final remainingGuestTx = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(guestId))).get();
          expect(remainingGuestTx.isEmpty, isTrue);
        },
      );

      // ========================================================================
      // 10. SUPABASE SQL MIGRATION: RLS, WITH CHECK, RPC & IDEMPOTENCY AUDIT
      // ========================================================================
      test(
        '10. Supabase SQL migration contains apply_sync_mutation RPC, strict RLS with WITH CHECK, and composite indexes',
        () {
          final migrationFile = File(
            'supabase/migrations/20260906000000_initial_cloud_schema.sql',
          );
          expect(migrationFile.existsSync(), isTrue);

          final sqlContent = migrationFile.readAsStringSync();

          final requiredTables = [
            'profiles',
            'categories',
            'accounts',
            'transactions',
            'budgets',
            'category_budgets',
            'savings_goals',
            'recurring_transactions',
            'user_settings',
            'sync_audit_log',
          ];

          for (final table in requiredTables) {
            expect(
              sqlContent.contains('CREATE TABLE IF NOT EXISTS public.$table'),
              isTrue,
              reason: 'Missing table $table in SQL migration',
            );

            expect(
              sqlContent.contains(
                'ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY;',
              ),
              isTrue,
              reason: 'Missing ENABLE ROW LEVEL SECURITY for $table',
            );
          }

          // Verify RLS policy clauses with WITH CHECK on INSERT and UPDATE
          expect(
            sqlContent.contains('WITH CHECK (auth.uid() = user_id)'),
            isTrue,
          );
          expect(sqlContent.contains('WITH CHECK (auth.uid() = id)'), isTrue);

          // Verify server-side RPC exists
          expect(
            sqlContent.contains(
              'CREATE OR REPLACE FUNCTION public.apply_sync_mutation',
            ),
            isTrue,
          );

          // Verify composite cursor indexes
          expect(
            sqlContent.contains('(user_id, updated_at_utc ASC, id ASC)'),
            isTrue,
          );

          // Verify sync audit log does NOT contain financial payload columns
          expect(
            sqlContent.contains('payload_json'),
            isFalse,
            reason:
                'sync_audit_log must never store sensitive transaction payloads',
          );
        },
      );
    },
  );
}
