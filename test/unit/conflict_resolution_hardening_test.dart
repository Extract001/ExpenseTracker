import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:expense_tracker/core/auth/auth_types.dart';
import 'package:expense_tracker/core/network/connectivity_status.dart';
import 'package:expense_tracker/core/network/i_connectivity_service.dart';
import 'package:expense_tracker/core/sync/conflict_resolver.dart';
import 'package:expense_tracker/core/sync/sync_types.dart';
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
  group('Phase 7: Conflict Resolution Hardening Test Suite', () {
    // =========================================================================
    // GROUP 1: DETERMINISTIC TIE-BREAKS & FIELD-LEVEL LWW
    // =========================================================================
    group('1. Deterministic Tie-Breaks & Field-Level LWW', () {
      test(
        '1.1 Equal field timestamps with identical values -> deterministic no-op',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final local = {'name': 'Groceries', 'colorValue': 4283215696};
          final remote = {'name': 'Groceries', 'colorValue': 4283215696};
          final timestamps = {
            'name': t.toIso8601String(),
            'colorValue': t.toIso8601String(),
          };

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(result.mergedPayload['name'], equals('Groceries'));
          expect(result.mergedPayload['colorValue'], equals(4283215696));
          expect(result.fieldsUpdatedFromRemote, equals(0));
          expect(result.fieldsRetainedFromLocal, equals(0));
        },
      );

      test(
        '1.2 Equal field timestamps with differing values -> Deterministic intrinsic winner (A ⊕ B == B ⊕ A)',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final stateA = {'name': 'Local Name', 'amountMinor': 1000};
          final stateB = {'name': 'Remote Name', 'amountMinor': 2000};
          final timestamps = {
            'name': t.toIso8601String(),
            'amountMinor': t.toIso8601String(),
          };

          final mergeAB = ConflictResolver.resolvePayloadConflict(
            localPayload: stateA,
            remotePayload: stateB,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final mergeBA = ConflictResolver.resolvePayloadConflict(
            localPayload: stateB,
            remotePayload: stateA,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          // Intrinsic deterministic tie-breaker selects identical winner regardless of argument order
          expect(mergeAB.mergedPayload['name'], equals('Remote Name'));
          expect(mergeAB.mergedPayload['amountMinor'], equals(2000));
          expect(mergeBA.mergedPayload['name'], equals('Remote Name'));
          expect(mergeBA.mergedPayload['amountMinor'], equals(2000));
        },
      );

      test(
        '1.3 Strict LWW: Newer local timestamp wins over older remote timestamp',
        () {
          final tOlder = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tNewer = DateTime.parse('2026-09-06T11:00:00.000Z');

          final local = {'note': 'New Local Note'};
          final remote = {'note': 'Old Remote Note'};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: {'note': tNewer.toIso8601String()},
            remoteFieldTimestamps: {'note': tOlder.toIso8601String()},
            localUpdatedAtUtc: tNewer,
            remoteUpdatedAtUtc: tOlder,
          );

          expect(result.mergedPayload['note'], equals('New Local Note'));
          expect(result.fieldsRetainedFromLocal, equals(1));
          expect(result.fieldsUpdatedFromRemote, equals(0));
        },
      );

      test(
        '1.4 Strict LWW: Newer remote timestamp wins over older local timestamp',
        () {
          final tOlder = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tNewer = DateTime.parse('2026-09-06T11:00:00.000Z');

          final local = {'amountMinor': 5000};
          final remote = {'amountMinor': 9900};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: {'amountMinor': tOlder.toIso8601String()},
            remoteFieldTimestamps: {'amountMinor': tNewer.toIso8601String()},
            localUpdatedAtUtc: tOlder,
            remoteUpdatedAtUtc: tNewer,
          );

          expect(result.mergedPayload['amountMinor'], equals(9900));
          expect(result.fieldsUpdatedFromRemote, equals(1));
          expect(result.fieldsRetainedFromLocal, equals(0));
        },
      );

      test('1.5 Non-overlapping multi-field edits: both survive intact', () {
        final tBase = DateTime.parse('2026-09-06T09:00:00.000Z');
        final tA = DateTime.parse('2026-09-06T10:00:00.000Z');
        final tB = DateTime.parse('2026-09-06T11:00:00.000Z');

        final local = {'amountMinor': 7500, 'note': 'Base Note'};
        final remote = {'amountMinor': 5000, 'note': 'Updated Remote Note'};

        final result = ConflictResolver.resolvePayloadConflict(
          localPayload: local,
          remotePayload: remote,
          localFieldTimestamps: {
            'amountMinor': tB.toIso8601String(), // Local modified amount at tB
            'note': tBase.toIso8601String(),
          },
          remoteFieldTimestamps: {
            'amountMinor': tBase.toIso8601String(),
            'note': tA.toIso8601String(), // Remote modified note at tA
          },
          localUpdatedAtUtc: tB,
          remoteUpdatedAtUtc: tA,
        );

        expect(result.mergedPayload['amountMinor'], equals(7500));
        expect(result.mergedPayload['note'], equals('Updated Remote Note'));
        expect(result.fieldsRetainedFromLocal, equals(1));
        expect(result.fieldsUpdatedFromRemote, equals(1));
      });

      test(
        '1.6 Commutativity / Arrival-order independence: merge(A, B) == merge(B, A)',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final t2 = DateTime.parse('2026-09-06T11:00:00.000Z');

          final stateA = {'amountMinor': 5000, 'note': 'A Note'};
          final timestampsA = {
            'amountMinor': t2.toIso8601String(),
            'note': t1.toIso8601String(),
          };

          final stateB = {'amountMinor': 3000, 'note': 'B Note'};
          final timestampsB = {
            'amountMinor': t1.toIso8601String(),
            'note': t2.toIso8601String(),
          };

          final mergeAB = ConflictResolver.resolvePayloadConflict(
            localPayload: stateA,
            remotePayload: stateB,
            localFieldTimestamps: timestampsA,
            remoteFieldTimestamps: timestampsB,
            localUpdatedAtUtc: t2,
            remoteUpdatedAtUtc: t2,
          );

          final mergeBA = ConflictResolver.resolvePayloadConflict(
            localPayload: stateB,
            remotePayload: stateA,
            localFieldTimestamps: timestampsB,
            remoteFieldTimestamps: timestampsA,
            localUpdatedAtUtc: t2,
            remoteUpdatedAtUtc: t2,
          );

          expect(mergeAB.mergedPayload['amountMinor'], equals(5000));
          expect(mergeAB.mergedPayload['note'], equals('B Note'));
          expect(mergeBA.mergedPayload['amountMinor'], equals(5000));
          expect(mergeBA.mergedPayload['note'], equals('B Note'));
        },
      );
    });

    // =========================================================================
    // GROUP 2: NULLABLE FIELDS & PARTIAL PAYLOADS
    // =========================================================================
    group('2. Nullable Fields & Partial Payloads', () {
      test(
        '2.1 Missing / omitted field in partial update does not wipe local field',
        () {
          final tLocal = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tRemote = DateTime.parse('2026-09-06T11:00:00.000Z');

          final local = {
            'note': 'Important Note',
            'attachmentPath': '/docs/receipt.png',
          };
          // Remote partial update only contains note
          final remote = {'note': 'Updated Note'};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: {
              'note': tLocal.toIso8601String(),
              'attachmentPath': tLocal.toIso8601String(),
            },
            remoteFieldTimestamps: {'note': tRemote.toIso8601String()},
            localUpdatedAtUtc: tLocal,
            remoteUpdatedAtUtc: tRemote,
          );

          expect(result.mergedPayload['note'], equals('Updated Note'));
          expect(
            result.mergedPayload['attachmentPath'],
            equals('/docs/receipt.png'),
          );
        },
      );

      test('2.2 Explicit null with newer timestamp clears local field', () {
        final tLocal = DateTime.parse('2026-09-06T10:00:00.000Z');
        final tRemote = DateTime.parse('2026-09-06T11:00:00.000Z');

        final local = {'attachmentPath': '/docs/receipt.png'};
        final remote = {'attachmentPath': null};

        final result = ConflictResolver.resolvePayloadConflict(
          localPayload: local,
          remotePayload: remote,
          localFieldTimestamps: {'attachmentPath': tLocal.toIso8601String()},
          remoteFieldTimestamps: {'attachmentPath': tRemote.toIso8601String()},
          localUpdatedAtUtc: tLocal,
          remoteUpdatedAtUtc: tRemote,
        );

        expect(result.mergedPayload['attachmentPath'], isNull);
        expect(result.fieldsUpdatedFromRemote, equals(1));
      });

      test(
        '2.3 Explicit null with older timestamp is ignored and local non-null retained',
        () {
          final tRemote = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tLocal = DateTime.parse('2026-09-06T11:00:00.000Z');

          final local = {'attachmentPath': '/docs/new_receipt.png'};
          final remote = {'attachmentPath': null};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: {'attachmentPath': tLocal.toIso8601String()},
            remoteFieldTimestamps: {
              'attachmentPath': tRemote.toIso8601String(),
            },
            localUpdatedAtUtc: tLocal,
            remoteUpdatedAtUtc: tRemote,
          );

          expect(
            result.mergedPayload['attachmentPath'],
            equals('/docs/new_receipt.png'),
          );
          expect(result.fieldsRetainedFromLocal, equals(1));
        },
      );

      test(
        '2.4 Equal timestamp null vs non-null: Non-null wins symmetrically (A ⊕ B == B ⊕ A)',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final stateVal = {'note': 'Active Note'};
          final stateNull = {'note': null};
          final ts = {'note': t.toIso8601String()};

          final mergeValNull = ConflictResolver.resolvePayloadConflict(
            localPayload: stateVal,
            remotePayload: stateNull,
            localFieldTimestamps: ts,
            remoteFieldTimestamps: ts,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final mergeNullVal = ConflictResolver.resolvePayloadConflict(
            localPayload: stateNull,
            remotePayload: stateVal,
            localFieldTimestamps: ts,
            remoteFieldTimestamps: ts,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(mergeValNull.mergedPayload['note'], equals('Active Note'));
          expect(mergeNullVal.mergedPayload['note'], equals('Active Note'));
        },
      );
    });

    // =========================================================================
    // GROUP 3: UNKNOWN CLOUD FIELDS & SCHEMA EVOLUTION
    // =========================================================================
    group('3. Unknown Cloud Fields & Schema Evolution', () {
      test(
        '3.1 Unknown future cloud fields are merged without crashing known fields',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final local = {'name': 'Salary', 'amountMinor': 500000};
          final remote = {
            'name': 'Salary',
            'amountMinor': 500000,
            'future_ai_tag': 'tax_exempt',
            'cloud_extra_metadata': {'version': 3},
          };

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: {
              'name': t.toIso8601String(),
              'amountMinor': t.toIso8601String(),
            },
            remoteFieldTimestamps: {
              'name': t.toIso8601String(),
              'amountMinor': t.toIso8601String(),
              'future_ai_tag': t.toIso8601String(),
              'cloud_extra_metadata': t.toIso8601String(),
            },
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(result.mergedPayload['name'], equals('Salary'));
          expect(result.mergedPayload['amountMinor'], equals(500000));
          expect(result.mergedPayload['future_ai_tag'], equals('tax_exempt'));
        },
      );
    });

    // =========================================================================
    // GROUP 4: CLOCK SKEW CLAMPING
    // =========================================================================
    group('4. Clock Skew Clamping', () {
      test('4.1 Forward clock skew > 5 minutes is clamped to nowUtc', () {
        final nowUtc = DateTime.parse('2026-09-06T12:00:00.000Z');
        final maliciousFutureTime = DateTime.parse(
          '2026-09-06T13:30:00.000Z',
        ); // +90 mins

        final sanitized = ConflictResolver.sanitizeFieldTimestamps({
          'amountMinor': maliciousFutureTime.toIso8601String(),
        }, nowUtc: nowUtc);

        expect(sanitized['amountMinor'], equals(nowUtc.toIso8601String()));
      });

      test('4.2 Timestamps within 5 minutes skew window are preserved', () {
        final nowUtc = DateTime.parse('2026-09-06T12:00:00.000Z');
        final slightFutureTime = DateTime.parse(
          '2026-09-06T12:03:00.000Z',
        ); // +3 mins

        final sanitized = ConflictResolver.sanitizeFieldTimestamps({
          'amountMinor': slightFutureTime.toIso8601String(),
        }, nowUtc: nowUtc);

        expect(
          sanitized['amountMinor'],
          equals(slightFutureTime.toIso8601String()),
        );
      });
    });

    // =========================================================================
    // GROUP 5: DELETE VS UPDATE & UPDATE VS DELETE RESOLUTION
    // =========================================================================
    group('5. Delete vs Update & Update vs Delete Resolution', () {
      test(
        '5.1 Remote Update strictly newer than Local Delete -> Entity is restored',
        () {
          final tDelete = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tUpdate = DateTime.parse('2026-09-06T11:00:00.000Z');

          final shouldDelete = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tDelete,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tDelete,
            remoteUpdatedAtUtc: tUpdate,
          );

          expect(shouldDelete, isFalse);
        },
      );

      test(
        '5.2 Local Delete strictly newer than Remote Update -> Entity remains deleted',
        () {
          final tUpdate = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tDelete = DateTime.parse('2026-09-06T11:00:00.000Z');

          final shouldDelete = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tDelete,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tDelete,
            remoteUpdatedAtUtc: tUpdate,
          );

          expect(shouldDelete, isTrue);
        },
      );

      test(
        '5.3 Local Update strictly newer than Remote Delete -> Entity is restored',
        () {
          final tDelete = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tUpdate = DateTime.parse('2026-09-06T11:00:00.000Z');

          final shouldDelete = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: null,
            remoteDeletedAtUtc: tDelete,
            localUpdatedAtUtc: tUpdate,
            remoteUpdatedAtUtc: tDelete,
          );

          expect(shouldDelete, isFalse);
        },
      );

      test(
        '5.4 Remote Delete strictly newer than Local Update -> Entity is deleted',
        () {
          final tUpdate = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tDelete = DateTime.parse('2026-09-06T11:00:00.000Z');

          final shouldDelete = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: null,
            remoteDeletedAtUtc: tDelete,
            localUpdatedAtUtc: tUpdate,
            remoteUpdatedAtUtc: tDelete,
          );

          expect(shouldDelete, isTrue);
        },
      );

      test('5.5 Equal-time update vs delete tie-break -> Delete wins', () {
        final t = DateTime.parse('2026-09-06T12:00:00.000Z');

        final shouldDeleteLocalDel = ConflictResolver.shouldRecordBeDeleted(
          localDeletedAtUtc: t,
          remoteDeletedAtUtc: null,
          localUpdatedAtUtc: t,
          remoteUpdatedAtUtc: t,
        );
        expect(shouldDeleteLocalDel, isTrue);

        final shouldDeleteRemoteDel = ConflictResolver.shouldRecordBeDeleted(
          localDeletedAtUtc: null,
          remoteDeletedAtUtc: t,
          localUpdatedAtUtc: t,
          remoteUpdatedAtUtc: t,
        );
        expect(shouldDeleteRemoteDel, isTrue);
      });
    });

    // =========================================================================
    // GROUP 6: TOMBSTONE HANDLING & REPEATED INGESTION
    // =========================================================================
    group('6. Tombstone Handling & Repeated Ingestion', () {
      test(
        '6.1 reconcileEntityState sets deletedAtUtc correctly on deletion and restoration',
        () {
          final tDelete = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tUpdate = DateTime.parse('2026-09-06T11:00:00.000Z');

          // Case A: Deletion wins
          final resA = ConflictResolver.reconcileEntityState(
            localPayload: {'name': 'Test'},
            remotePayload: {'name': 'Test'},
            localFieldTimestamps: {'name': tDelete.toIso8601String()},
            remoteFieldTimestamps: {'name': tDelete.toIso8601String()},
            localUpdatedAtUtc: tDelete,
            remoteUpdatedAtUtc: tDelete,
            localDeletedAtUtc: tDelete,
            remoteDeletedAtUtc: null,
          );
          expect(resA.mergedPayload['deletedAtUtc'], isNotNull);

          // Case B: Restoration wins
          final resB = ConflictResolver.reconcileEntityState(
            localPayload: {'name': 'Test'},
            remotePayload: {'name': 'Test Restored'},
            localFieldTimestamps: {'name': tDelete.toIso8601String()},
            remoteFieldTimestamps: {'name': tUpdate.toIso8601String()},
            localUpdatedAtUtc: tDelete,
            remoteUpdatedAtUtc: tUpdate,
            localDeletedAtUtc: tDelete,
            remoteDeletedAtUtc: null,
          );
          expect(resB.mergedPayload['deletedAtUtc'], isNull);
          expect(resB.mergedPayload['name'], equals('Test Restored'));
        },
      );
    });

    // =========================================================================
    // GROUP 7: END-TO-END PUSH/PULL RECONCILIATION WITH DATABASE
    // =========================================================================
    group('7. End-to-End Push/Pull Reconciliation with Database', () {
      late AppDatabase db;
      late _FakeConnectivityService connectivityService;
      late FakeSyncRemoteDataSource remoteDataSource;
      late FakeAuthService authService;
      late SyncCoordinator coordinator;

      const testUserId = 'user_p7_test';
      final testUser = AuthUser(
        id: testUserId,
        email: 'p7@example.com',
        displayName: 'P7 User',
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

        await db
            .into(db.usersTable)
            .insert(
              UsersTableCompanion(
                id: const drift.Value(testUserId),
                displayName: const drift.Value('P7 User'),
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

      test(
        '7.1 Push reconciliation applies server merged_record atomically',
        () async {
          final catId = IdGenerator.uuid();
          final nowUtc = DateTime.now().toUtc();

          // Local category has amountMinor modified
          await db
              .into(db.categoriesTable)
              .insert(
                CategoriesTableCompanion(
                  id: drift.Value(catId),
                  userId: const drift.Value(testUserId),
                  name: const drift.Value('Local Food'),
                  type: const drift.Value('expense'),
                  iconCodePoint: const drift.Value(1),
                  colorValue: const drift.Value(100),
                  isSystem: const drift.Value(false),
                  isArchived: const drift.Value(false),
                  createdAtUtc: drift.Value(nowUtc),
                  updatedAtUtc: drift.Value(nowUtc),
                  syncStatus: drift.Value(SyncStatus.pendingUpdate.name),
                ),
              );

          // Enqueue update
          await SyncQueueHelper.enqueueUpdate(
            db,
            userId: testUserId,
            entityType: EntityType.category,
            entityId: catId,
            payloadJson: jsonEncode({
              'name': 'Local Food',
              'type': 'expense',
              'iconCodePoint': 1,
              'colorValue': 100,
              'isSystem': false,
              'isArchived': false,
            }),
            currentSyncStatus: SyncStatus.pendingUpdate,
          );

          // Remote already had color modified with newer timestamp
          final tRemote = nowUtc.add(const Duration(seconds: 10));
          remoteDataSource.seedRemoteRecord(
            entityType: 'category',
            id: catId,
            userId: testUserId,
            payload: {
              'name': 'Remote Food',
              'type': 'expense',
              'iconCodePoint': 1,
              'colorValue': 999,
              'isSystem': false,
              'isArchived': false,
            },
            fieldTimestamps: {
              'name': nowUtc.toIso8601String(),
              'colorValue': tRemote.toIso8601String(),
            },
            updatedAtUtc: tRemote,
          );

          final result = await coordinator.synchronize();
          expect(result.success, isTrue);
          expect(result.pushedCount, equals(1));

          // Queue should be empty
          final pending = await db.syncQueueDao.getPendingCount(testUserId);
          expect(pending, equals(0));

          // Local DB has the merged colorValue = 999
          final updatedCat = await (db.select(
            db.categoriesTable,
          )..where((t) => t.id.equals(catId))).getSingle();
          expect(updatedCat.colorValue, equals(999));
          expect(updatedCat.syncStatus, equals(SyncStatus.synced.name));
        },
      );

      test(
        '7.2 Finite deterministic convergence: Multi-cycle sync stabilizes to zero operations without ping-pong',
        () async {
          final catId = IdGenerator.uuid();
          final nowUtc = DateTime.now().toUtc();

          remoteDataSource.seedRemoteRecord(
            entityType: 'category',
            id: catId,
            userId: testUserId,
            payload: {
              'name': 'Cloud Utilities',
              'type': 'expense',
              'iconCodePoint': 5,
              'colorValue': 555,
              'isSystem': false,
              'isArchived': false,
            },
            fieldTimestamps: {'name': nowUtc.toIso8601String()},
            updatedAtUtc: nowUtc,
          );

          // Cycle 1: Ingests remote record
          final result1 = await coordinator.synchronize();
          expect(result1.success, isTrue);
          expect(result1.pulledCount, equals(1));

          final pendingAfterSync1 = await db.syncQueueDao.getPendingCount(
            testUserId,
          );
          expect(pendingAfterSync1, equals(0));

          // Cycle 2: Stable no-op (0 pushed, 0 pulled)
          final result2 = await coordinator.synchronize();
          expect(result2.success, isTrue);
          expect(result2.pushedCount, equals(0));
          expect(result2.pulledCount, equals(0));

          // Cycle 3: Verified zero operations remain
          final pendingAfterSync2 = await db.syncQueueDao.getPendingCount(
            testUserId,
          );
          expect(pendingAfterSync2, equals(0));
        },
      );
    });

    // =========================================================================
    // GROUP 8: MULTI-CLIENT CONVERGENCE SCENARIOS
    // =========================================================================
    group('8. Multi-Client 5 Convergence Scenarios', () {
      test(
        '8.1 Scenario A: Independent field edits on two clients survive on both',
        () {
          final tBase = DateTime.parse('2026-09-06T09:00:00.000Z');
          final tClient1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tClient2 = DateTime.parse('2026-09-06T11:00:00.000Z');

          // Client 1 changed amount at 10:00
          final payloadClient1 = {'amountMinor': 12000, 'note': 'Initial'};
          final timestampsClient1 = {
            'amountMinor': tClient1.toIso8601String(),
            'note': tBase.toIso8601String(),
          };

          // Client 2 changed note at 11:00
          final payloadClient2 = {'amountMinor': 5000, 'note': 'Team Lunch'};
          final timestampsClient2 = {
            'amountMinor': tBase.toIso8601String(),
            'note': tClient2.toIso8601String(),
          };

          final merged = ConflictResolver.resolvePayloadConflict(
            localPayload: payloadClient1,
            remotePayload: payloadClient2,
            localFieldTimestamps: timestampsClient1,
            remoteFieldTimestamps: timestampsClient2,
            localUpdatedAtUtc: tClient1,
            remoteUpdatedAtUtc: tClient2,
          );

          expect(
            merged.mergedPayload['amountMinor'],
            equals(12000),
          ); // Client 1's newer amount
          expect(
            merged.mergedPayload['note'],
            equals('Team Lunch'),
          ); // Client 2's newer note
        },
      );

      test(
        '8.2 Scenario B: Overlapping field edits resolve via strict LWW',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final t2 = DateTime.parse('2026-09-06T10:05:00.000Z');

          final payloadClient1 = {'amountMinor': 3000};
          final timestampsClient1 = {'amountMinor': t1.toIso8601String()};

          final payloadClient2 = {'amountMinor': 4500};
          final timestampsClient2 = {'amountMinor': t2.toIso8601String()};

          final merged = ConflictResolver.resolvePayloadConflict(
            localPayload: payloadClient1,
            remotePayload: payloadClient2,
            localFieldTimestamps: timestampsClient1,
            remoteFieldTimestamps: timestampsClient2,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
          );

          expect(merged.mergedPayload['amountMinor'], equals(4500));
        },
      );

      test(
        '8.3 Scenario C: Concurrent Category & Transaction creation preserves topological consistency',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final conn = _FakeConnectivityService();
          final remote = FakeSyncRemoteDataSource();
          final auth = FakeAuthService(
            initialUser: AuthUser(
              id: 'user_sc_c',
              email: 'c@test.com',
              displayName: 'C',
            ),
          );
          remote.activeAuthUserId = 'user_sc_c';

          final coord = SyncCoordinator(
            db: db,
            connectivityService: conn,
            remoteDataSource: remote,
            authService: auth,
            getActiveUserId: () => 'user_sc_c',
          );

          final catId = IdGenerator.uuid();
          final accId = IdGenerator.uuid();
          final txId = IdGenerator.uuid();
          final nowUtc = DateTime.now().toUtc();

          // Enqueue Category, Account, and Transaction
          await db
              .into(db.categoriesTable)
              .insert(
                CategoriesTableCompanion(
                  id: drift.Value(catId),
                  userId: const drift.Value('user_sc_c'),
                  name: const drift.Value('Dining'),
                  type: const drift.Value('expense'),
                  iconCodePoint: const drift.Value(1),
                  colorValue: const drift.Value(100),
                  isSystem: const drift.Value(false),
                  isArchived: const drift.Value(false),
                  createdAtUtc: drift.Value(nowUtc),
                  updatedAtUtc: drift.Value(nowUtc),
                  syncStatus: drift.Value(SyncStatus.pendingCreate.name),
                ),
              );
          await SyncQueueHelper.enqueueCreate(
            db,
            userId: 'user_sc_c',
            entityType: EntityType.category,
            entityId: catId,
            payloadJson: jsonEncode({
              'name': 'Dining',
              'type': 'expense',
              'iconCodePoint': 1,
              'colorValue': 100,
              'isSystem': false,
              'isArchived': false,
            }),
          );

          await db
              .into(db.accountsTable)
              .insert(
                AccountsTableCompanion(
                  id: drift.Value(accId),
                  userId: const drift.Value('user_sc_c'),
                  name: const drift.Value('Checking'),
                  accountType: const drift.Value('bank'),
                  initialBalanceMinor: const drift.Value(100000),
                  colorValue: const drift.Value(200),
                  iconCodePoint: const drift.Value(2),
                  createdAtUtc: drift.Value(nowUtc),
                  updatedAtUtc: drift.Value(nowUtc),
                  syncStatus: drift.Value(SyncStatus.pendingCreate.name),
                ),
              );
          await SyncQueueHelper.enqueueCreate(
            db,
            userId: 'user_sc_c',
            entityType: EntityType.account,
            entityId: accId,
            payloadJson: jsonEncode({
              'name': 'Checking',
              'accountType': 'bank',
              'initialBalanceMinor': 100000,
              'colorValue': 200,
              'iconCodePoint': 2,
            }),
          );

          await db
              .into(db.transactionsTable)
              .insert(
                TransactionsTableCompanion(
                  id: drift.Value(txId),
                  userId: const drift.Value('user_sc_c'),
                  accountId: drift.Value(accId),
                  categoryId: drift.Value(catId),
                  amountMinor: const drift.Value(2500),
                  transactionType: const drift.Value('expense'),
                  transactionDateUtc: drift.Value(nowUtc),
                  isRecurring: const drift.Value(false),
                  createdAtUtc: drift.Value(nowUtc),
                  updatedAtUtc: drift.Value(nowUtc),
                  syncStatus: drift.Value(SyncStatus.pendingCreate.name),
                ),
              );
          await SyncQueueHelper.enqueueCreate(
            db,
            userId: 'user_sc_c',
            entityType: EntityType.transaction,
            entityId: txId,
            payloadJson: jsonEncode({
              'accountId': accId,
              'categoryId': catId,
              'amountMinor': 2500,
              'transactionType': 'expense',
              'transactionDateUtc': nowUtc.toIso8601String(),
              'isRecurring': false,
            }),
          );

          final res = await coord.synchronize();
          expect(res.success, isTrue);
          expect(res.pushedCount, equals(3));

          // In the cloud, mutations were applied in topological order: Category (rank 10), Account (rank 20), Transaction (rank 70)
          expect(remote.appliedMutations.length, equals(3));
          expect(remote.appliedMutations[0]['entity_type'], equals('category'));
          expect(remote.appliedMutations[1]['entity_type'], equals('account'));
          expect(
            remote.appliedMutations[2]['entity_type'],
            equals('transaction'),
          );

          coord.dispose();
          conn.dispose();
          auth.dispose();
          await db.close();
        },
      );

      test(
        '8.4 Scenario D: Client 1 deletes account at T1, Client 2 updates account at T2 -> restored',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final t2 = DateTime.parse('2026-09-06T10:30:00.000Z');

          final res = ConflictResolver.reconcileEntityState(
            localPayload: {'name': 'Checking Account'},
            remotePayload: {'name': 'Primary Checking'},
            localFieldTimestamps: {'name': t1.toIso8601String()},
            remoteFieldTimestamps: {'name': t2.toIso8601String()},
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
            localDeletedAtUtc: t1, // Client 1 deleted at T1
            remoteDeletedAtUtc: null, // Client 2 edited at T2
          );

          expect(res.mergedPayload['deletedAtUtc'], isNull); // Restored!
          expect(res.mergedPayload['name'], equals('Primary Checking'));
        },
      );

      test(
        '8.5 Scenario E: 3 devices concurrently editing distinct and overlapping fields converge',
        () {
          final tBase = DateTime.parse('2026-09-06T09:00:00.000Z');
          final tD1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tD2 = DateTime.parse('2026-09-06T10:15:00.000Z');
          final tD3 = DateTime.parse('2026-09-06T10:30:00.000Z');

          // Initial base state
          Map<String, dynamic> state = {
            'amountMinor': 1000,
            'note': 'Initial Note',
            'attachmentPath': '/a.jpg',
          };
          Map<String, String> timestamps = {
            'amountMinor': tBase.toIso8601String(),
            'note': tBase.toIso8601String(),
            'attachmentPath': tBase.toIso8601String(),
          };

          // Device 1 changes amount at 10:00
          final d1Change = ConflictResolver.resolvePayloadConflict(
            localPayload: state,
            remotePayload: {'amountMinor': 2000},
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: {'amountMinor': tD1.toIso8601String()},
            localUpdatedAtUtc: tBase,
            remoteUpdatedAtUtc: tD1,
          );
          state = Map<String, dynamic>.from(d1Change.mergedPayload);
          timestamps = Map<String, String>.from(d1Change.mergedFieldTimestamps);

          // Device 2 changes note at 10:15
          final d2Change = ConflictResolver.resolvePayloadConflict(
            localPayload: state,
            remotePayload: {'note': 'Coffee with team'},
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: {'note': tD2.toIso8601String()},
            localUpdatedAtUtc: tD1,
            remoteUpdatedAtUtc: tD2,
          );
          state = Map<String, dynamic>.from(d2Change.mergedPayload);
          timestamps = Map<String, String>.from(d2Change.mergedFieldTimestamps);

          // Device 3 changes amount at 10:30 (overrides D1) and clears attachment
          final d3Change = ConflictResolver.resolvePayloadConflict(
            localPayload: state,
            remotePayload: {'amountMinor': 3500, 'attachmentPath': null},
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: {
              'amountMinor': tD3.toIso8601String(),
              'attachmentPath': tD3.toIso8601String(),
            },
            localUpdatedAtUtc: tD2,
            remoteUpdatedAtUtc: tD3,
          );
          state = Map<String, dynamic>.from(d3Change.mergedPayload);

          expect(
            state['amountMinor'],
            equals(3500),
          ); // D3 wins amount (10:30 > 10:00)
          expect(
            state['note'],
            equals('Coffee with team'),
          ); // D2 wins note (10:15)
          expect(
            state['attachmentPath'],
            isNull,
          ); // D3 cleared attachment (10:30)
        },
      );
    });

    // =========================================================================
    // GROUP 9: INVARIANTS & SAFETY BOUNDARIES
    // =========================================================================
    group('9. Invariants & Safety Boundaries', () {
      test(
        '9.1 Immutable identity fields cannot be overridden by remote payload',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final local = {
            'id': 'local-uuid-1',
            'userId': 'user-1',
            'createdAtUtc': '2026-09-01T00:00:00.000Z',
            'name': 'Local Category',
          };
          final remote = {
            'id': 'malicious-remote-uuid',
            'userId': 'malicious-user',
            'createdAtUtc': '2020-01-01T00:00:00.000Z',
            'name': 'Remote Category',
          };

          final res = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: {'name': t.toIso8601String()},
            remoteFieldTimestamps: {'name': t.toIso8601String()},
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(res.mergedPayload['id'], equals('local-uuid-1'));
          expect(res.mergedPayload['userId'], equals('user-1'));
          expect(
            res.mergedPayload['createdAtUtc'],
            equals('2026-09-01T00:00:00.000Z'),
          );
        },
      );

      test(
        '9.2 Algebraic properties: Idempotence, Commutativity, Associativity, and Repeated Application',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final t2 = DateTime.parse('2026-09-06T11:00:00.000Z');
          final t3 = DateTime.parse('2026-09-06T12:00:00.000Z');

          final a = {'amountMinor': 1000, 'note': 'A'};
          final tsA = {
            'amountMinor': t1.toIso8601String(),
            'note': t1.toIso8601String(),
          };

          final b = {'amountMinor': 2000, 'note': 'B'};
          final tsB = {
            'amountMinor': t2.toIso8601String(),
            'note': t2.toIso8601String(),
          };

          final c = {'amountMinor': 3000, 'note': 'C'};
          final tsC = {
            'amountMinor': t3.toIso8601String(),
            'note': t3.toIso8601String(),
          };

          // 1. Idempotence: merge(A, A) == A
          final mergeAA = ConflictResolver.resolvePayloadConflict(
            localPayload: a,
            remotePayload: a,
            localFieldTimestamps: tsA,
            remoteFieldTimestamps: tsA,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t1,
          );
          expect(
            mergeAA.mergedPayload['amountMinor'],
            equals(a['amountMinor']),
          );
          expect(mergeAA.mergedPayload['note'], equals(a['note']));

          // 2. Commutativity: merge(A, B) == merge(B, A)
          final mergeAB = ConflictResolver.resolvePayloadConflict(
            localPayload: a,
            remotePayload: b,
            localFieldTimestamps: tsA,
            remoteFieldTimestamps: tsB,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
          );
          final mergeBA = ConflictResolver.resolvePayloadConflict(
            localPayload: b,
            remotePayload: a,
            localFieldTimestamps: tsB,
            remoteFieldTimestamps: tsA,
            localUpdatedAtUtc: t2,
            remoteUpdatedAtUtc: t1,
          );
          expect(
            mergeAB.mergedPayload['amountMinor'],
            equals(mergeBA.mergedPayload['amountMinor']),
          );
          expect(
            mergeAB.mergedPayload['note'],
            equals(mergeBA.mergedPayload['note']),
          );

          // 3. Repeated Application Stability: merge(A, merge(A, B)) == merge(A, B)
          final mergeAWithAB = ConflictResolver.resolvePayloadConflict(
            localPayload: a,
            remotePayload: mergeAB.mergedPayload,
            localFieldTimestamps: tsA,
            remoteFieldTimestamps: mergeAB.mergedFieldTimestamps,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
          );
          expect(
            mergeAWithAB.mergedPayload['amountMinor'],
            equals(mergeAB.mergedPayload['amountMinor']),
          );
          expect(
            mergeAWithAB.mergedPayload['note'],
            equals(mergeAB.mergedPayload['note']),
          );

          // 4. Associativity: merge(merge(A, B), C) == merge(A, merge(B, C))
          final mergeABC_1 = ConflictResolver.resolvePayloadConflict(
            localPayload: mergeAB.mergedPayload,
            remotePayload: c,
            localFieldTimestamps: mergeAB.mergedFieldTimestamps,
            remoteFieldTimestamps: tsC,
            localUpdatedAtUtc: t2,
            remoteUpdatedAtUtc: t3,
          );

          final mergeBC = ConflictResolver.resolvePayloadConflict(
            localPayload: b,
            remotePayload: c,
            localFieldTimestamps: tsB,
            remoteFieldTimestamps: tsC,
            localUpdatedAtUtc: t2,
            remoteUpdatedAtUtc: t3,
          );
          final mergeABC_2 = ConflictResolver.resolvePayloadConflict(
            localPayload: a,
            remotePayload: mergeBC.mergedPayload,
            localFieldTimestamps: tsA,
            remoteFieldTimestamps: mergeBC.mergedFieldTimestamps,
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t3,
          );

          expect(
            mergeABC_1.mergedPayload['amountMinor'],
            equals(mergeABC_2.mergedPayload['amountMinor']),
          );
          expect(
            mergeABC_1.mergedPayload['note'],
            equals(mergeABC_2.mergedPayload['note']),
          );
        },
      );

      test(
        '9.3 Financial invariant: Negative transaction amount rejected during pull validation',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final conn = _FakeConnectivityService();
          final remote = FakeSyncRemoteDataSource();
          final auth = FakeAuthService(
            initialUser: AuthUser(
              id: 'user_fin',
              email: 'fin@test.com',
              displayName: 'Fin',
            ),
          );
          remote.activeAuthUserId = 'user_fin';

          final coord = SyncCoordinator(
            db: db,
            connectivityService: conn,
            remoteDataSource: remote,
            authService: auth,
            getActiveUserId: () => 'user_fin',
          );

          // Seed invalid remote transaction with amountMinor = -500
          final txId = IdGenerator.uuid();
          final nowUtc = DateTime.now().toUtc();
          remote.seedRemoteRecord(
            entityType: 'transaction',
            id: txId,
            userId: 'user_fin',
            payload: {
              'accountId': IdGenerator.uuid(),
              'categoryId': IdGenerator.uuid(),
              'amountMinor': -500, // Invalid negative amount
              'transactionType': 'expense',
              'transactionDateUtc': nowUtc.toIso8601String(),
              'isRecurring': false,
            },
            fieldTimestamps: {'amountMinor': nowUtc.toIso8601String()},
            updatedAtUtc: nowUtc,
          );

          // Pull must fail due to validation error and transaction rolled back
          final res = await coord.synchronize();
          expect(res.success, isFalse);
          expect(
            res.errorMessage,
            contains('Transaction missing valid amountMinor > 0'),
          );

          coord.dispose();
          conn.dispose();
          auth.dispose();
          await db.close();
        },
      );
    });

    // =========================================================================
    // GROUP 10: CANONICAL SERIALIZATION & DETERMINISTIC REPRESENTATION
    // =========================================================================
    group('10. Canonical Serialization & Deterministic Representation', () {
      test(
        '10.1 Same map with different insertion order -> identical canonical JSON representation',
        () {
          final map1 = {'b': 2, 'a': 1, 'z': 26, 'm': 13};
          final map2 = {'z': 26, 'm': 13, 'a': 1, 'b': 2};

          final canonical1 = ConflictResolver.canonicalJsonEncode(map1);
          final canonical2 = ConflictResolver.canonicalJsonEncode(map2);

          expect(canonical1, equals(canonical2));
          expect(canonical1, equals('{"a":1,"b":2,"m":13,"z":26}'));
        },
      );

      test(
        '10.2 Nested maps with different insertion order -> identical canonical JSON representation',
        () {
          final nested1 = {
            'outerB': {'innerZ': 'last', 'innerA': 'first'},
            'outerA': {'x': 100, 'w': 50},
          };
          final nested2 = {
            'outerA': {'w': 50, 'x': 100},
            'outerB': {'innerA': 'first', 'innerZ': 'last'},
          };

          final c1 = ConflictResolver.canonicalJsonEncode(nested1);
          final c2 = ConflictResolver.canonicalJsonEncode(nested2);

          expect(c1, equals(c2));
          expect(
            c1,
            equals(
              '{"outerA":{"w":50,"x":100},"outerB":{"innerA":"first","innerZ":"last"}}',
            ),
          );
        },
      );

      test('10.3 Same arrays -> identical canonical JSON representation', () {
        final list1 = [
          1,
          2,
          {'k': 'v', 'a': 'b'},
        ];
        final list2 = [
          1,
          2,
          {'a': 'b', 'k': 'v'},
        ];

        final c1 = ConflictResolver.canonicalJsonEncode(list1);
        final c2 = ConflictResolver.canonicalJsonEncode(list2);

        expect(c1, equals(c2));
        expect(c1, equals('[1,2,{"a":"b","k":"v"}]'));
      });

      test(
        '10.4 Different arrays -> deterministic distinct canonical ordering',
        () {
          final listA = [1, 2, 3];
          final listB = [1, 2, 4];

          final cA = ConflictResolver.canonicalJsonEncode(listA);
          final cB = ConflictResolver.canonicalJsonEncode(listB);

          expect(cA, isNot(equals(cB)));
          expect(cB.compareTo(cA), greaterThan(0));
        },
      );

      test('10.5 Null handling in canonical JSON serialization', () {
        expect(ConflictResolver.canonicalJsonEncode(null), equals('null'));
        expect(
          ConflictResolver.canonicalJsonEncode({'b': null, 'a': 1}),
          equals('{"a":1,"b":null}'),
        );
      });

      test('10.6 Numeric values formatting in canonical JSON', () {
        expect(ConflictResolver.canonicalJsonEncode(42), equals('42'));
        expect(ConflictResolver.canonicalJsonEncode(3.14), equals('3.14'));
        expect(
          ConflictResolver.canonicalJsonEncode({'amt': 10500}),
          equals('{"amt":10500}'),
        );
      });

      test(
        '10.7 Nested mixed structures (maps inside lists and lists inside maps)',
        () {
          final mixed1 = {
            'items': [
              {'name': 'Item 2', 'id': 2},
              {'name': 'Item 1', 'id': 1},
            ],
            'meta': {'tag': 'test'},
          };
          final mixed2 = {
            'meta': {'tag': 'test'},
            'items': [
              {'id': 2, 'name': 'Item 2'},
              {'id': 1, 'name': 'Item 1'},
            ],
          };

          final c1 = ConflictResolver.canonicalJsonEncode(mixed1);
          final c2 = ConflictResolver.canonicalJsonEncode(mixed2);

          expect(c1, equals(c2));
        },
      );

      test(
        '10.8 Equal timestamp + logically identical maps with different insertion order -> clean no-op',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final local = {
            'metadata': {'b': 2, 'a': 1},
          };
          final remote = {
            'metadata': {'a': 1, 'b': 2},
          };
          final ts = {'metadata': t.toIso8601String()};

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: local,
            remotePayload: remote,
            localFieldTimestamps: ts,
            remoteFieldTimestamps: ts,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(result.fieldsUpdatedFromRemote, equals(0));
          expect(result.fieldsRetainedFromLocal, equals(0));
        },
      );

      test(
        '10.9 Equal timestamp + logically different maps -> deterministic winner regardless of direction (A ⊕ B == B ⊕ A)',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');
          final mapA = {
            'meta': {'code': 'ALPHA'},
          };
          final mapB = {
            'meta': {'code': 'BETA'},
          };
          final ts = {'meta': t.toIso8601String()};

          final mergeAB = ConflictResolver.resolvePayloadConflict(
            localPayload: mapA,
            remotePayload: mapB,
            localFieldTimestamps: ts,
            remoteFieldTimestamps: ts,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final mergeBA = ConflictResolver.resolvePayloadConflict(
            localPayload: mapB,
            remotePayload: mapA,
            localFieldTimestamps: ts,
            remoteFieldTimestamps: ts,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final canonicalAB = ConflictResolver.canonicalJsonEncode(
            mergeAB.mergedPayload['meta'],
          );
          final canonicalBA = ConflictResolver.canonicalJsonEncode(
            mergeBA.mergedPayload['meta'],
          );

          expect(canonicalAB, equals(canonicalBA));
          expect(mergeAB.mergedPayload['meta']['code'], equals('BETA'));
          expect(mergeBA.mergedPayload['meta']['code'], equals('BETA'));
        },
      );
    });

    // =========================================================================
    // GROUP 11: MULTI-CLIENT ARRIVAL PERMUTATIONS & REPEATED APPLICATION
    // =========================================================================
    group(
      '11. Multi-Client Arrival Permutations (6 Orders) & Repeated Application',
      () {
        test(
          '11.1 Repeated application: R1 = merge(A, B), R2 = merge(R1, B), R3 = merge(R2, B) -> R1 == R2 == R3',
          () {
            final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
            final t2 = DateTime.parse('2026-09-06T11:00:00.000Z');

            final stateA = {'amountMinor': 1000, 'note': 'First'};
            final tsA = {
              'amountMinor': t1.toIso8601String(),
              'note': t1.toIso8601String(),
            };

            final stateB = {'amountMinor': 2000, 'note': 'Second'};
            final tsB = {
              'amountMinor': t2.toIso8601String(),
              'note': t2.toIso8601String(),
            };

            final r1 = ConflictResolver.resolvePayloadConflict(
              localPayload: stateA,
              remotePayload: stateB,
              localFieldTimestamps: tsA,
              remoteFieldTimestamps: tsB,
              localUpdatedAtUtc: t1,
              remoteUpdatedAtUtc: t2,
            );

            final r2 = ConflictResolver.resolvePayloadConflict(
              localPayload: r1.mergedPayload,
              remotePayload: stateB,
              localFieldTimestamps: r1.mergedFieldTimestamps,
              remoteFieldTimestamps: tsB,
              localUpdatedAtUtc: t2,
              remoteUpdatedAtUtc: t2,
            );

            final r3 = ConflictResolver.resolvePayloadConflict(
              localPayload: r2.mergedPayload,
              remotePayload: stateB,
              localFieldTimestamps: r2.mergedFieldTimestamps,
              remoteFieldTimestamps: tsB,
              localUpdatedAtUtc: t2,
              remoteUpdatedAtUtc: t2,
            );

            expect(
              r1.mergedPayload['amountMinor'],
              equals(r2.mergedPayload['amountMinor']),
            );
            expect(
              r2.mergedPayload['amountMinor'],
              equals(r3.mergedPayload['amountMinor']),
            );
            expect(r1.mergedPayload['note'], equals(r2.mergedPayload['note']));
            expect(r2.mergedPayload['note'], equals(r3.mergedPayload['note']));
          },
        );

        test(
          '11.2 Arrival-order independence across all 6 permutations of 3 client states (A, B, C)',
          () {
            final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
            final t3 = DateTime.parse('2026-09-06T12:00:00.000Z');

            final a = {'amountMinor': 1000, 'note': 'A Note', 'tag': 'Alpha'};
            final tsA = {
              'amountMinor': t1.toIso8601String(),
              'note': t1.toIso8601String(),
              'tag': t3.toIso8601String(), // A has newer tag
            };

            final b = {'amountMinor': 5000, 'note': 'B Note', 'tag': 'Beta'};
            final tsB = {
              'amountMinor': t3.toIso8601String(), // B has newer amount
              'note': t1.toIso8601String(),
              'tag': t1.toIso8601String(),
            };

            final c = {'amountMinor': 2000, 'note': 'C Note', 'tag': 'Gamma'};
            final tsC = {
              'amountMinor': t1.toIso8601String(),
              'note': t3.toIso8601String(), // C has newer note
              'tag': t1.toIso8601String(),
            };

            FieldConflictResult mergeTwo(
              Map<String, dynamic> p1,
              Map<String, String> ts1,
              DateTime u1,
              Map<String, dynamic> p2,
              Map<String, String> ts2,
              DateTime u2,
            ) {
              return ConflictResolver.resolvePayloadConflict(
                localPayload: p1,
                remotePayload: p2,
                localFieldTimestamps: ts1,
                remoteFieldTimestamps: ts2,
                localUpdatedAtUtc: u1,
                remoteUpdatedAtUtc: u2,
              );
            }

            Map<String, dynamic> mergeThree(
              Map<String, dynamic> s1,
              Map<String, String> ts1,
              DateTime u1,
              Map<String, dynamic> s2,
              Map<String, String> ts2,
              DateTime u2,
              Map<String, dynamic> s3,
              Map<String, String> ts3,
              DateTime u3,
            ) {
              final first = mergeTwo(s1, ts1, u1, s2, ts2, u2);
              final second = mergeTwo(
                first.mergedPayload,
                first.mergedFieldTimestamps,
                u2.isAfter(u1) ? u2 : u1,
                s3,
                ts3,
                u3,
              );
              return second.mergedPayload;
            }

            // Permutation 1: A -> B -> C
            final p1 = mergeThree(a, tsA, t3, b, tsB, t3, c, tsC, t3);
            // Permutation 2: A -> C -> B
            final p2 = mergeThree(a, tsA, t3, c, tsC, t3, b, tsB, t3);
            // Permutation 3: B -> A -> C
            final p3 = mergeThree(b, tsB, t3, a, tsA, t3, c, tsC, t3);
            // Permutation 4: B -> C -> A
            final p4 = mergeThree(b, tsB, t3, c, tsC, t3, a, tsA, t3);
            // Permutation 5: C -> A -> B
            final p5 = mergeThree(c, tsC, t3, a, tsA, t3, b, tsB, t3);
            // Permutation 6: C -> B -> A
            final p6 = mergeThree(c, tsC, t3, b, tsB, t3, a, tsA, t3);

            const expectedAmount = 5000; // From B (t3)
            const expectedNote = 'C Note'; // From C (t3)
            const expectedTag = 'Alpha'; // From A (t3)

            for (final p in [p1, p2, p3, p4, p5, p6]) {
              expect(p['amountMinor'], equals(expectedAmount));
              expect(p['note'], equals(expectedNote));
              expect(p['tag'], equals(expectedTag));
            }
          },
        );
      },
    );

    // =========================================================================
    // GROUP 12: COMPREHENSIVE TOMBSTONE LIFECYCLE & DELETE INVARIANTS
    // =========================================================================
    group('12. Comprehensive Tombstone Lifecycle & Delete Invariants', () {
      test('12.1 Equal timestamp Delete vs Delete: remains deleted', () {
        final t = DateTime.parse('2026-09-06T12:00:00.000Z');
        final isDel = ConflictResolver.shouldRecordBeDeleted(
          localDeletedAtUtc: t,
          remoteDeletedAtUtc: t,
          localUpdatedAtUtc: t,
          remoteUpdatedAtUtc: t,
        );
        expect(isDel, isTrue);
      });

      test('12.2 Newer Delete vs older Update: Delete strictly wins', () {
        final tOld = DateTime.parse('2026-09-06T10:00:00.000Z');
        final tNew = DateTime.parse('2026-09-06T11:00:00.000Z');

        final isDel = ConflictResolver.shouldRecordBeDeleted(
          localDeletedAtUtc: tNew,
          remoteDeletedAtUtc: null,
          localUpdatedAtUtc: tNew,
          remoteUpdatedAtUtc: tOld,
        );
        expect(isDel, isTrue);
      });

      test(
        '12.3 Newer Update vs older Delete: Update strictly wins (Restoration)',
        () {
          final tOld = DateTime.parse('2026-09-06T10:00:00.000Z');
          final tNew = DateTime.parse('2026-09-06T11:00:00.000Z');

          final isDel = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: tOld,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: tOld,
            remoteUpdatedAtUtc: tNew,
          );
          expect(isDel, isFalse);
        },
      );

      test(
        '12.4 Equal timestamp Delete vs Update: Delete wins symmetrically',
        () {
          final t = DateTime.parse('2026-09-06T12:00:00.000Z');

          final isDel1 = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: t,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );
          expect(isDel1, isTrue);

          final isDel2 = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: null,
            remoteDeletedAtUtc: t,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );
          expect(isDel2, isTrue);
        },
      );

      test(
        '12.5 Multiple successive deletes maintain deleted state without errors',
        () {
          final t1 = DateTime.parse('2026-09-06T10:00:00.000Z');
          final t2 = DateTime.parse('2026-09-06T11:00:00.000Z');

          final res = ConflictResolver.reconcileEntityState(
            localPayload: {'name': 'Deleted Item'},
            remotePayload: {'name': 'Deleted Item'},
            localFieldTimestamps: {'name': t1.toIso8601String()},
            remoteFieldTimestamps: {'name': t2.toIso8601String()},
            localUpdatedAtUtc: t1,
            remoteUpdatedAtUtc: t2,
            localDeletedAtUtc: t1,
            remoteDeletedAtUtc: t2,
          );

          expect(
            res.mergedPayload['deletedAtUtc'],
            equals(t2.toIso8601String()),
          );
        },
      );
    });

    // =========================================================================
    // GROUP 13: CROSS-LAYER CLIENT/SERVER ORDERING BOUNDARY COMPATIBILITY
    // =========================================================================
    group('13. Cross-Layer Client/Server Ordering Boundary Compatibility', () {
      test(
        '13.1 Equal timestamp scalar conflict: mergeClient(A,B) == mergeClient(B,A) == mergeServer(A,B)',
        () async {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final stateA = {'amountMinor': 1000};
          final stateB = {'amountMinor': 2000};
          final timestamps = {'amountMinor': t.toIso8601String()};

          // 1. Client merge in both arrival directions
          final clientMergeAB = ConflictResolver.resolvePayloadConflict(
            localPayload: stateA,
            remotePayload: stateB,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final clientMergeBA = ConflictResolver.resolvePayloadConflict(
            localPayload: stateB,
            remotePayload: stateA,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(clientMergeAB.mergedPayload['amountMinor'], equals(2000));
          expect(clientMergeBA.mergedPayload['amountMinor'], equals(2000));

          // 2. Server simulation (FakeSyncRemoteDataSource simulates Supabase PostgreSQL RPC)
          final remoteServer1 = FakeSyncRemoteDataSource();
          remoteServer1.seedRemoteRecord(
            entityType: 'transactions',
            id: 'tx-cross-1',
            userId: 'user-1',
            payload: stateA,
            fieldTimestamps: timestamps,
            updatedAtUtc: t,
          );

          // Server receives mutation B when holding state A
          final resB = await remoteServer1.applySyncMutation(
            operationId: 'op-b-1',
            entityType: 'transactions',
            entityId: 'tx-cross-1',
            operationType: 'update',
            payload: stateB,
            fieldTimestamps: timestamps,
            updatedAtUtc: t,
          );
          final serverWinner1 =
              resB['merged_record']?['amountMinor'] ??
              resB['merged_record']?['amount_minor'];

          // Server starting with state B, receiving mutation A
          final remoteServer2 = FakeSyncRemoteDataSource();
          remoteServer2.seedRemoteRecord(
            entityType: 'transactions',
            id: 'tx-cross-1',
            userId: 'user-1',
            payload: stateB,
            fieldTimestamps: timestamps,
            updatedAtUtc: t,
          );
          final resA = await remoteServer2.applySyncMutation(
            operationId: 'op-a-1',
            entityType: 'transactions',
            entityId: 'tx-cross-1',
            operationType: 'update',
            payload: stateA,
            fieldTimestamps: timestamps,
            updatedAtUtc: t,
          );
          final serverWinner2 =
              resA['merged_record']?['amountMinor'] ??
              resA['merged_record']?['amount_minor'];

          // Invariant: mergeClient(A,B) == mergeClient(B,A) == mergeServer(A,B) == mergeServer(B,A)
          expect(serverWinner1, equals(2000));
          expect(serverWinner2, equals(2000));
          expect(
            clientMergeAB.mergedPayload['amountMinor'],
            equals(serverWinner1),
          );
        },
      );

      test(
        '13.2 Logically equal maps with different key insertion order produce identical canonical JSON and clean no-op',
        () {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final map1 = {'a': 1, 'b': 2};
          final map2 = {'b': 2, 'a': 1};

          final canon1 = ConflictResolver.canonicalJsonEncode(map1);
          final canon2 = ConflictResolver.canonicalJsonEncode(map2);

          expect(canon1, equals('{"a":1,"b":2}'));
          expect(canon2, equals('{"a":1,"b":2}'));
          expect(canon1, equals(canon2));

          final result = ConflictResolver.resolvePayloadConflict(
            localPayload: {'metadata': map1},
            remotePayload: {'metadata': map2},
            localFieldTimestamps: {'metadata': t.toIso8601String()},
            remoteFieldTimestamps: {'metadata': t.toIso8601String()},
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(result.fieldsUpdatedFromRemote, equals(0));
          expect(result.fieldsRetainedFromLocal, equals(0));
        },
      );

      test(
        '13.3 Nested maps with differing key orders evaluate to identical canonical JSON',
        () {
          final nested1 = {
            'a': {'x': 1, 'y': 2},
          };
          final nested2 = {
            'a': {'y': 2, 'x': 1},
          };

          final canon1 = ConflictResolver.canonicalJsonEncode(nested1);
          final canon2 = ConflictResolver.canonicalJsonEncode(nested2);

          expect(canon1, equals('{"a":{"x":1,"y":2}}'));
          expect(canon2, equals('{"a":{"x":1,"y":2}}'));
          expect(canon1, equals(canon2));
        },
      );

      test(
        '13.4 Equal timestamp null vs non-null: non-null strictly takes precedence across client and server',
        () async {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final stateNull = {'note': null};
          final stateVal = {'note': 'Coffee'};
          final timestamps = {'note': t.toIso8601String()};

          // Client resolution
          final mergeClient1 = ConflictResolver.resolvePayloadConflict(
            localPayload: stateNull,
            remotePayload: stateVal,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final mergeClient2 = ConflictResolver.resolvePayloadConflict(
            localPayload: stateVal,
            remotePayload: stateNull,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(mergeClient1.mergedPayload['note'], equals('Coffee'));
          expect(mergeClient2.mergedPayload['note'], equals('Coffee'));

          // Server simulation
          final remoteServer = FakeSyncRemoteDataSource();
          remoteServer.seedRemoteRecord(
            entityType: 'transactions',
            id: 'tx-cross-null',
            userId: 'user-1',
            payload: stateNull,
            fieldTimestamps: timestamps,
            updatedAtUtc: t,
          );

          final res = await remoteServer.applySyncMutation(
            operationId: 'op-null-1',
            entityType: 'transactions',
            entityId: 'tx-cross-null',
            operationType: 'update',
            payload: stateVal,
            fieldTimestamps: timestamps,
            updatedAtUtc: t,
          );

          expect(res['merged_record']?['note'], equals('Coffee'));
        },
      );

      test(
        '13.5 Equal timestamp delete vs update: delete strictly prevails symmetrically across client and server',
        () async {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));

          // Client evaluation
          final shouldBeDeleted1 = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: t,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );
          final shouldBeDeleted2 = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: null,
            remoteDeletedAtUtc: t,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(shouldBeDeleted1, isTrue);
          expect(shouldBeDeleted2, isTrue);

          // Server simulation
          final remoteServer = FakeSyncRemoteDataSource();
          remoteServer.seedRemoteRecord(
            entityType: 'transactions',
            id: 'tx-cross-del',
            userId: 'user-1',
            payload: {'note': 'Active Transaction'},
            fieldTimestamps: {'note': t.toIso8601String()},
            updatedAtUtc: t,
            deletedAtUtc: null,
          );

          final res = await remoteServer.applySyncMutation(
            operationId: 'op-del-1',
            entityType: 'transactions',
            entityId: 'tx-cross-del',
            operationType: 'delete',
            payload: const {},
            fieldTimestamps: const {},
            updatedAtUtc: t,
            deletedAtUtc: t,
          );

          expect(
            res['merged_record']?['deleted_at_utc'],
            equals(t.toIso8601String()),
          );
        },
      );

      test(
        '13.6 Different arrays on equal timestamps: deterministic winner selected symmetrically',
        () {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final arr1 = {
            'tags': [1, 2],
          };
          final arr2 = {
            'tags': [2, 1],
          };
          final timestamps = {'tags': t.toIso8601String()};

          final canon1 = ConflictResolver.canonicalJsonEncode(arr1['tags']);
          final canon2 = ConflictResolver.canonicalJsonEncode(arr2['tags']);

          expect(canon1, equals('[1,2]'));
          expect(canon2, equals('[2,1]'));

          final mergeAB = ConflictResolver.resolvePayloadConflict(
            localPayload: arr1,
            remotePayload: arr2,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final mergeBA = ConflictResolver.resolvePayloadConflict(
            localPayload: arr2,
            remotePayload: arr1,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          // [2,1] > [1,2] lexicographically -> winner is [2,1] in both directions
          expect(mergeAB.mergedPayload['tags'], equals([2, 1]));
          expect(mergeBA.mergedPayload['tags'], equals([2, 1]));
        },
      );

      test(
        '13.7 Different numeric values on equal timestamp: deterministic total ordering',
        () {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final s1 = {'amountMinor': 500};
          final s2 = {'amountMinor': 5000};
          final timestamps = {'amountMinor': t.toIso8601String()};

          final merge12 = ConflictResolver.resolvePayloadConflict(
            localPayload: s1,
            remotePayload: s2,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          final merge21 = ConflictResolver.resolvePayloadConflict(
            localPayload: s2,
            remotePayload: s1,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(
            merge12.mergedPayload['amountMinor'],
            equals(merge21.mergedPayload['amountMinor']),
          );
        },
      );

      test(
        '13.8 Three-way merge associativity: merge(A, merge(B, C)) == merge(merge(A, B), C)',
        () {
          final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
          final stateA = {'note': 'Alpha', 'amountMinor': 100};
          final stateB = {'note': 'Beta', 'amountMinor': 200};
          final stateC = {'note': 'Gamma', 'amountMinor': 300};
          final timestamps = {
            'note': t.toIso8601String(),
            'amountMinor': t.toIso8601String(),
          };

          // Grouping 1: merge(A, merge(B, C))
          final bc = ConflictResolver.resolvePayloadConflict(
            localPayload: stateB,
            remotePayload: stateC,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );
          final aBc = ConflictResolver.resolvePayloadConflict(
            localPayload: stateA,
            remotePayload: bc.mergedPayload,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: bc.mergedFieldTimestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          // Grouping 2: merge(merge(A, B), C)
          final ab = ConflictResolver.resolvePayloadConflict(
            localPayload: stateA,
            remotePayload: stateB,
            localFieldTimestamps: timestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );
          final abC = ConflictResolver.resolvePayloadConflict(
            localPayload: ab.mergedPayload,
            remotePayload: stateC,
            localFieldTimestamps: ab.mergedFieldTimestamps,
            remoteFieldTimestamps: timestamps,
            localUpdatedAtUtc: t,
            remoteUpdatedAtUtc: t,
          );

          expect(aBc.mergedPayload['note'], equals(abC.mergedPayload['note']));
          expect(
            aBc.mergedPayload['amountMinor'],
            equals(abC.mergedPayload['amountMinor']),
          );
        },
      );
    });
  });
}
