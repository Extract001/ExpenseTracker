import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/auth/i_auth_service.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/connectivity_status.dart';
import '../../core/network/i_connectivity_service.dart';
import '../../core/sync/conflict_resolver.dart';
import '../../core/sync/i_sync_coordinator.dart';
import '../../core/sync/i_sync_remote_data_source.dart';
import '../../core/sync/sync_cursor.dart';
import '../../core/sync/sync_types.dart';
import '../../domain/entities/enums.dart';
import '../database/app_database.dart';
import '../repositories/sync_queue_helper.dart';
import 'fake_sync_remote_data_source.dart';

/// Production implementation of [ISyncCoordinator].
///
/// Orchestrates offline-first synchronization between the local encrypted Drift database
/// and Supabase PostgreSQL with field-level LWW conflict resolution, topological dependency ordering,
/// composite cursor pagination, operation-level idempotency, and atomic guest data migration.
class SyncCoordinator implements ISyncCoordinator {
  final AppDatabase _db;
  final IConnectivityService _connectivityService;
  final ISyncRemoteDataSource _remoteDataSource;
  final IAuthService? _authService;
  final String Function()? _getActiveUserId;

  final StreamController<SyncEngineState> _stateController =
      StreamController<SyncEngineState>.broadcast();
  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();

  SyncEngineState _currentState = SyncEngineState.idle;
  SyncResult? _lastSyncResult;
  DateTime? _lastSyncTimeUtc;

  StreamSubscription<ConnectivityStatus>? _connectivitySub;
  StreamSubscription? _authSub;

  bool _isDisposed = false;
  bool _isSyncRunning = false;
  int _syncGeneration = 0;

  SyncCoordinator({
    required AppDatabase db,
    required IConnectivityService connectivityService,
    ISyncRemoteDataSource? remoteDataSource,
    IAuthService? authService,
    String Function()? getActiveUserId,
  }) : _db = db,
       _connectivityService = connectivityService,
       _remoteDataSource = remoteDataSource ?? FakeSyncRemoteDataSource(),
       _authService = authService,
       _getActiveUserId = getActiveUserId {
    _init();
  }

  String get _activeUserId =>
      _getActiveUserId?.call() ??
      _authService?.currentUser?.id ??
      AppConstants.defaultUserId;

  void _init() {
    _connectivitySub = _connectivityService.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );

    _authSub = _authService?.authStateChanges.listen((state) {
      if (_isDisposed) return;
      if (!state.isAuthenticated) {
        abortActiveSync();
      }
    });
  }

  void _handleConnectivityChange(ConnectivityStatus status) async {
    if (_isDisposed) return;
    if (status == ConnectivityStatus.offline) {
      _updateState(SyncEngineState.offline);
    } else if (status == ConnectivityStatus.online) {
      final wasOffline = _currentState == SyncEngineState.offline;
      _updateState(SyncEngineState.idle);
      if (wasOffline) {
        final authService = _authService;
        if (authService != null && !authService.isAuthenticated) {
          try {
            await authService.signInAnonymously();
          } catch (_) {
            // If anonymous sign in is disabled or network fails, continue
          }
        }
        synchronize();
      }
    }
  }

  void _updateState(SyncEngineState newState) {
    if (_currentState == newState || _isDisposed) return;
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Stream<SyncEngineState> get syncStateStream => _stateController.stream;

  @override
  SyncEngineState get currentState => _currentState;

  @override
  Stream<SyncProgress> get progressStream => _progressController.stream;

  @override
  SyncResult? get lastSyncResult => _lastSyncResult;

  @override
  DateTime? get lastSyncTimeUtc => _lastSyncTimeUtc;

  @override
  void abortActiveSync() {
    _syncGeneration++;
    _isSyncRunning = false;
    if (!_isDisposed) {
      _updateState(SyncEngineState.idle);
    }
  }

  @override
  Future<int> getPendingOperationsCount(String userId) {
    return _db.syncQueueDao.getPendingCount(userId);
  }

  @override
  Future<SyncResult> synchronize({bool force = false}) async {
    if (_isDisposed) {
      return SyncResult.failure('SyncCoordinator is disposed');
    }

    if (_isSyncRunning) {
      return SyncResult.failure('Synchronization already in progress');
    }
    _isSyncRunning = true;

    _syncGeneration++;
    final currentGen = _syncGeneration;

    try {
      final isOnline = await _connectivityService.isConnected;
      if (!isOnline && !force) {
        _updateState(SyncEngineState.offline);
        return SyncResult.failure('Device is offline');
      }

      _updateState(SyncEngineState.syncing);

      final userId = _activeUserId;
      int pushedCount = 0;
      int pulledCount = 0;
      int conflictsResolvedCount = 0;

      // Step 1: PUSH pending operations to cloud
      final pushResult = await _processPushQueue(userId, currentGen);
      pushedCount = pushResult.pushedCount;

      if (currentGen != _syncGeneration) {
        return SyncResult.failure('Synchronization aborted');
      }

      // Step 2: PULL remote updates from cloud
      final pullResult = await _processPull(userId, currentGen);
      pulledCount = pullResult.pulledCount;
      conflictsResolvedCount = pullResult.conflictsResolvedCount;

      if (currentGen != _syncGeneration) {
        return SyncResult.failure('Synchronization aborted');
      }

      final result = SyncResult.success(
        pushed: pushedCount,
        pulled: pulledCount,
        conflicts: conflictsResolvedCount,
      );

      _lastSyncResult = result;
      _lastSyncTimeUtc = DateTime.now().toUtc();
      _updateState(SyncEngineState.idle);
      return result;
    } on NetworkException catch (e) {
      _updateState(SyncEngineState.offline);
      final result = SyncResult.failure(e.message);
      _lastSyncResult = result;
      return result;
    } catch (e) {
      _updateState(SyncEngineState.error);
      final result = SyncResult.failure(e.toString());
      _lastSyncResult = result;
      return result;
    } finally {
      if (currentGen == _syncGeneration) {
        _isSyncRunning = false;
      }
    }
  }

  // ===========================================================================
  // PUSH ENGINE
  // ===========================================================================

  Future<_PushResult> _processPushQueue(String userId, int expectedGen) async {
    int totalPushed = 0;

    while (true) {
      if (expectedGen != _syncGeneration || _isDisposed) break;

      // 1. Fetch bounded batch of pending operations
      final pendingOps = await _db.syncQueueDao.getPendingOperations(
        userId: userId,
        limit: 50,
      );

      if (pendingOps.isEmpty) break;

      // 2. Sort topologically by dependency hierarchy (Parents created before children; children deleted before parents)
      final sortedOps = List<SyncOperationData>.from(pendingOps);
      sortedOps.sort((a, b) {
        final isDelA = a.operationType == SyncOperationType.delete.name;
        final isDelB = b.operationType == SyncOperationType.delete.name;
        final rankA = _getDependencyRank(a.entityType, isDelete: isDelA);
        final rankB = _getDependencyRank(b.entityType, isDelete: isDelB);
        final rankComp = rankA.compareTo(rankB);
        if (rankComp != 0) return rankComp;
        return a.createdAtUtc.compareTo(b.createdAtUtc);
      });

      _progressController.add(
        SyncProgress(
          totalOperations: sortedOps.length,
          completedOperations: totalPushed,
        ),
      );

      for (final op in sortedOps) {
        if (expectedGen != _syncGeneration || _isDisposed) break;

        final nowUtc = DateTime.now().toUtc();

        try {
          if (op.operationType == SyncOperationType.delete.name) {
            // Delete operation
            final res = await _remoteDataSource.applySyncMutation(
              operationId: op.id,
              entityType: op.entityType,
              entityId: op.entityId,
              operationType: 'delete',
              payload: const {},
              fieldTimestamps: const {},
              updatedAtUtc: nowUtc,
              deletedAtUtc: nowUtc,
            );

            final status = res['status'] as String?;
            if (status == 'applied' || status == 'already_processed') {
              await _db.transaction(() async {
                if (expectedGen != _syncGeneration ||
                    _activeUserId != userId ||
                    _isDisposed) {
                  throw StateError(
                    'Sync aborted: active user changed during push',
                  );
                }
                await _db.syncQueueDao.deleteOperation(op.id);
              });
              totalPushed++;
            }
          } else {
            // Create or Update operation
            final entityData = await _fetchLocalEntityPayload(
              entityType: op.entityType,
              entityId: op.entityId,
              userId: userId,
            );

            if (entityData == null) {
              // Entity was hard deleted or missing, clean up operation
              await _db.syncQueueDao.deleteOperation(op.id);
              continue;
            }

            final remoteUserId = _authService?.currentUser?.id ?? userId;
            final outgoingPayload =
                Map<String, dynamic>.from(entityData.payload);
            if (_authService?.currentUser?.id != null) {
              outgoingPayload['userId'] = remoteUserId;
              outgoingPayload['user_id'] = remoteUserId;
            }
            if (outgoingPayload.containsKey('colorValue') &&
                outgoingPayload['colorValue'] is num) {
              outgoingPayload['colorValue'] =
                  (outgoingPayload['colorValue'] as num).toInt().toSigned(32);
            }
            if (outgoingPayload.containsKey('color_value') &&
                outgoingPayload['color_value'] is num) {
              outgoingPayload['color_value'] =
                  (outgoingPayload['color_value'] as num).toInt().toSigned(32);
            }

            final res = await _remoteDataSource.applySyncMutation(
              operationId: op.id,
              entityType: op.entityType,
              entityId: op.entityId,
              operationType: op.operationType,
              payload: outgoingPayload,
              fieldTimestamps: entityData.fieldTimestamps,
              updatedAtUtc: entityData.updatedAtUtc,
              deletedAtUtc: entityData.deletedAtUtc,
            );

            final status = res['status'] as String?;
            if (status == 'applied' || status == 'already_processed') {
              // Atomic transaction: apply returned merged state + delete from queue + mark local entity synced
              await _db.transaction(() async {
                if (expectedGen != _syncGeneration ||
                    _activeUserId != userId ||
                    _isDisposed) {
                  throw StateError(
                    'Sync aborted: active user changed during push',
                  );
                }

                // If the server resolved field-level conflicts or returned authoritative state on already_processed, apply it locally
                final mergedRecord =
                    res['merged_record'] ??
                    res['authoritative_record'] ??
                    res['authoritative_state'] ??
                    res['server_state'];
                if (mergedRecord is Map) {
                  final mergedMap = Map<String, dynamic>.from(mergedRecord);
                  final remoteFieldTimestamps = Map<String, String>.from(
                    mergedMap['field_timestamps_json'] as Map? ?? {},
                  );
                  final remoteUpdatedAt =
                      DateTime.tryParse(
                        mergedMap['updated_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      nowUtc;
                  final remoteDeletedAt = mergedMap['deleted_at_utc'] != null
                      ? DateTime.tryParse(
                          mergedMap['deleted_at_utc'] as String,
                        )?.toUtc()
                      : null;

                  final conflictResult = ConflictResolver.reconcileEntityState(
                    localPayload: entityData.payload,
                    remotePayload: mergedMap,
                    localFieldTimestamps: entityData.fieldTimestamps,
                    remoteFieldTimestamps: remoteFieldTimestamps,
                    localUpdatedAtUtc: entityData.updatedAtUtc,
                    remoteUpdatedAtUtc: remoteUpdatedAt,
                    localDeletedAtUtc: entityData.deletedAtUtc,
                    remoteDeletedAtUtc: remoteDeletedAt,
                  );

                  await _updateLocalEntityFromReconciliation(
                    userId: userId,
                    entityType: op.entityType,
                    entityId: op.entityId,
                    conflictResult: conflictResult,
                  );
                }

                await _db.syncQueueDao.deleteOperation(op.id);
                await _markLocalEntitySynced(
                  entityType: op.entityType,
                  entityId: op.entityId,
                );
              });
              totalPushed++;
            }
          }
        } on NetworkException catch (e) {
          await _db.syncQueueDao.recordOperationFailure(
            id: op.id,
            errorMessage: e.message,
            attemptTimeUtc: nowUtc,
          );
          rethrow;
        } catch (e) {
          await _db.syncQueueDao.recordOperationFailure(
            id: op.id,
            errorMessage: e.toString(),
            attemptTimeUtc: nowUtc,
          );
          // Continue processing independent items
        }
      }
    }

    return _PushResult(pushedCount: totalPushed);
  }

  int _getDependencyRank(String entityType, {bool isDelete = false}) {
    if (isDelete) {
      // DELETES: Children MUST be deleted BEFORE Parents to satisfy ON DELETE RESTRICT constraints
      switch (entityType.toLowerCase()) {
        case 'usersetting':
        case 'user_settings':
        case 'settings':
          return 110;
        case 'transaction':
        case 'transactions':
          return 120; // Deleted before recurring rules, accounts, categories
        case 'recurringrule':
        case 'recurring_rule':
        case 'recurringtransaction':
        case 'recurring_transaction':
        case 'recurring_transactions':
          return 130; // Deleted before accounts, categories
        case 'categorybudget':
        case 'category_budget':
        case 'categorybudgets':
        case 'category_budgets':
          return 140; // Deleted before budgets, categories
        case 'goal':
        case 'savingsgoal':
        case 'savings_goal':
        case 'savingsgoals':
        case 'savings_goals':
          return 150;
        case 'budget':
        case 'budgets':
          return 160;
        case 'account':
        case 'accounts':
          return 170; // Deleted after transactions & recurring rules
        case 'category':
        case 'categories':
          return 180; // Deleted last (referenced by transactions, category_budgets, recurring)
        default:
          return 190;
      }
    } else {
      // CREATES / UPDATES: Parents MUST be created BEFORE Children
      switch (entityType.toLowerCase()) {
        case 'category':
        case 'categories':
          return 10;
        case 'account':
        case 'accounts':
          return 20;
        case 'budget':
        case 'budgets':
          return 30;
        case 'goal':
        case 'savingsgoal':
        case 'savings_goal':
        case 'savingsgoals':
        case 'savings_goals':
          return 40;
        case 'categorybudget':
        case 'category_budget':
        case 'categorybudgets':
        case 'category_budgets':
          return 50; // Depends on Category, Budget
        case 'recurringrule':
        case 'recurring_rule':
        case 'recurringtransaction':
        case 'recurring_transaction':
        case 'recurring_transactions':
          return 60; // Depends on Category, Account
        case 'transaction':
        case 'transactions':
          return 70; // Depends on Category, Account, RecurringRule
        case 'usersetting':
        case 'user_settings':
        case 'settings':
          return 80;
        default:
          return 90;
      }
    }
  }

  // ===========================================================================
  // PULL ENGINE
  // ===========================================================================

  Future<_PullResult> _processPull(String userId, int expectedGen) async {
    int totalPulled = 0;
    int totalConflictsResolved = 0;

    final entityTypes = [
      'category',
      'account',
      'budget',
      'goal',
      'category_budget',
      'transaction',
      'recurring_rule',
    ];

    for (final entityType in entityTypes) {
      if (expectedGen != _syncGeneration ||
          _activeUserId != userId ||
          _isDisposed) {
        break;
      }

      // Entity-scoped cursor isolation (Per-entity cursor prevents cross-entity skipping)
      final meta = await _db.syncMetadataDao.getEntityMetadata(
        userId: userId,
        entityType: entityType,
      );
      SyncCursor? cursor = SyncCursor.decode(meta?.syncCursor);

      while (true) {
        if (expectedGen != _syncGeneration ||
            _activeUserId != userId ||
            _isDisposed) {
          break;
        }

        final remoteRecords = await _remoteDataSource.pullEntities(
          userId: userId,
          entityType: entityType,
          cursor: cursor,
          limit: 50,
        );

        if (remoteRecords.isEmpty) {
          break;
        }

        // 1. Validate ALL records in page before starting atomic commit
        for (final remote in remoteRecords) {
          _validateRemoteRecord(entityType, remote, userId);
        }

        // 2. Atomic page commit in a single Drift transaction
        await _db.transaction(() async {
          if (expectedGen != _syncGeneration ||
              _activeUserId != userId ||
              _isDisposed) {
            throw StateError(
              'Sync aborted: user switched or coordinator disposed',
            );
          }

          for (final remote in remoteRecords) {
            final remoteId = remote['id'] as String;
            final remoteUpdatedAt =
                DateTime.tryParse(
                  remote['updated_at_utc'] as String? ?? '',
                )?.toUtc() ??
                DateTime.now().toUtc();
            final remoteDeletedAt = remote['deleted_at_utc'] != null
                ? DateTime.tryParse(remote['deleted_at_utc'] as String)?.toUtc()
                : null;
            final remoteFieldTimestamps = Map<String, String>.from(
              remote['field_timestamps_json'] as Map? ?? {},
            );

            // Reconcile with local Drift entity
            final reconcileResult = await _reconcileAndApplyRemoteRecord(
              userId: userId,
              entityType: entityType,
              remoteRecord: remote,
              remoteFieldTimestamps: remoteFieldTimestamps,
              remoteUpdatedAtUtc: remoteUpdatedAt,
              remoteDeletedAtUtc: remoteDeletedAt,
            );

            if (reconcileResult.fieldsUpdatedFromRemote > 0) {
              totalConflictsResolved++;
            }
            totalPulled++;

            // Advance cursor
            cursor = SyncCursor(
              timestampUtc: remoteUpdatedAt,
              entityId: remoteId,
            );
          }

          // Advance and commit entity-scoped cursor ONLY after all records in page succeed
          if (cursor != null) {
            await _db.syncMetadataDao.setEntityCursor(
              userId: userId,
              entityType: entityType,
              lastSyncUtc: cursor!.timestampUtc,
              cursor: cursor!.encode(),
            );
          }
        });

        if (remoteRecords.length < 50) break;
      }
    }

    return _PullResult(
      pulledCount: totalPulled,
      conflictsResolvedCount: totalConflictsResolved,
    );
  }

  void _validateRemoteRecord(
    String entityType,
    Map<String, dynamic> record,
    String expectedUserId,
  ) {
    final id = record['id'];
    if (id == null || id is! String || id.trim().isEmpty) {
      throw const ValidationException('Remote record missing valid UUID id');
    }

    final userId = record['user_id'] ?? record['userId'];
    final cloudUserId = _authService?.currentUser?.id;
    if (userId != null && userId != expectedUserId && userId != cloudUserId) {
      throw ValidationException(
        'Cross-user record violation: expected $expectedUserId but got $userId',
      );
    }

    final updatedAtStr = record['updated_at_utc'] ?? record['updatedAtUtc'];
    if (updatedAtStr == null ||
        DateTime.tryParse(updatedAtStr.toString()) == null) {
      throw const ValidationException(
        'Remote record missing valid updated_at_utc timestamp',
      );
    }

    final isDeleted =
        (record['deleted_at_utc'] ?? record['deletedAtUtc']) != null;
    if (isDeleted) {
      // Tombstones only require valid id, user_id, and updated_at_utc
      return;
    }

    // Schema and money integrity validations for active records
    switch (entityType.toLowerCase()) {
      case 'transaction':
      case 'transactions':
        final amount = record['amount_minor'] ?? record['amountMinor'];
        if (amount == null || amount is! num || amount <= 0) {
          throw const ValidationException(
            'Transaction missing valid amountMinor > 0',
          );
        }
        break;
      case 'budget':
      case 'budgets':
        final amount = record['amount_minor'] ?? record['amountMinor'];
        if (amount == null || amount is! num || amount <= 0) {
          throw const ValidationException(
            'Budget missing valid amountMinor > 0',
          );
        }
        break;
      case 'goal':
      case 'savings_goals':
        final target =
            record['target_amount_minor'] ?? record['targetAmountMinor'];
        if (target == null || target is! num || target <= 0) {
          throw const ValidationException(
            'Goal missing valid targetAmountMinor > 0',
          );
        }
        break;
    }
  }

  // ===========================================================================
  // RECONCILIATION & LOCAL DRIFT ENTITY HELPERS
  // ===========================================================================

  Future<FieldConflictResult> _reconcileAndApplyRemoteRecord({
    required String userId,
    required String entityType,
    required Map<String, dynamic> remoteRecord,
    required Map<String, String> remoteFieldTimestamps,
    required DateTime remoteUpdatedAtUtc,
    required DateTime? remoteDeletedAtUtc,
  }) async {
    final entityId = remoteRecord['id'] as String;
    final localData = await _fetchLocalEntityPayload(
      entityType: entityType,
      entityId: entityId,
      userId: userId,
    );

    if (localData == null) {
      // If the remote record is already deleted and was never present locally, skip inserting a blank placeholder
      if (remoteDeletedAtUtc != null) {
        return FieldConflictResult(
          mergedPayload: remoteRecord,
          mergedFieldTimestamps: remoteFieldTimestamps,
          fieldsUpdatedFromRemote: 0,
        );
      }

      // 1. New active record from cloud -> Insert locally
      await _insertRemoteRecordToLocal(
        userId: userId,
        entityType: entityType,
        record: remoteRecord,
        fieldTimestamps: remoteFieldTimestamps,
        updatedAtUtc: remoteUpdatedAtUtc,
        deletedAtUtc: remoteDeletedAtUtc,
      );

      return FieldConflictResult(
        mergedPayload: remoteRecord,
        mergedFieldTimestamps: remoteFieldTimestamps,
        fieldsUpdatedFromRemote: 1,
      );
    }

    // 2. Existing record -> Field-level LWW reconciliation
    final conflictResult = ConflictResolver.reconcileEntityState(
      localPayload: localData.payload,
      remotePayload: remoteRecord,
      localFieldTimestamps: localData.fieldTimestamps,
      remoteFieldTimestamps: remoteFieldTimestamps,
      localUpdatedAtUtc: localData.updatedAtUtc,
      remoteUpdatedAtUtc: remoteUpdatedAtUtc,
      localDeletedAtUtc: localData.deletedAtUtc,
      remoteDeletedAtUtc: remoteDeletedAtUtc,
    );

    await _updateLocalEntityFromReconciliation(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      conflictResult: conflictResult,
    );

    // If local fields were retained (i.e. strictly newer than remote),
    // enqueue an update so cloud receives the newer local fields on next push.
    if (conflictResult.fieldsRetainedFromLocal > 0) {
      final payloadJson = jsonEncode(conflictResult.mergedPayload);
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: userId,
        entityType: _mapEntityType(entityType),
        entityId: entityId,
        payloadJson: payloadJson,
        currentSyncStatus: SyncStatus.synced,
      );
    }

    return conflictResult;
  }

  Future<_LocalEntityInfo?> _fetchLocalEntityPayload({
    required String entityType,
    required String entityId,
    required String userId,
  }) async {
    switch (entityType.toLowerCase()) {
      case 'category':
      case 'categories':
        final c = await (_db.select(
          _db.categoriesTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (c == null) return null;
        return _LocalEntityInfo(
          payload: {
            'name': c.name,
            'type': c.type,
            'iconCodePoint': c.iconCodePoint,
            'colorValue': c.colorValue,
            'isSystem': c.isSystem,
            'isArchived': c.isArchived,
          },
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            c.fieldTimestampsJson,
          ),
          updatedAtUtc: c.updatedAtUtc,
          deletedAtUtc: c.deletedAtUtc,
        );

      case 'account':
      case 'accounts':
        final a = await (_db.select(
          _db.accountsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (a == null) return null;
        return _LocalEntityInfo(
          payload: {
            'name': a.name,
            'accountType': a.accountType,
            'currency': a.currency,
            'initialBalanceMinor': a.initialBalanceMinor,
            'colorValue': a.colorValue,
            'iconCodePoint': a.iconCodePoint,
          },
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            a.fieldTimestampsJson,
          ),
          updatedAtUtc: a.updatedAtUtc,
          deletedAtUtc: a.deletedAtUtc,
        );

      case 'transaction':
      case 'transactions':
        final tx = await (_db.select(
          _db.transactionsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (tx == null) return null;
        return _LocalEntityInfo(
          payload: {
            'amountMinor': tx.amountMinor,
            'transactionType': tx.transactionType,
            'categoryId': tx.categoryId,
            'accountId': tx.accountId,
            'toAccountId': tx.toAccountId,
            'note': tx.note,
            'transactionDateUtc': tx.transactionDateUtc.toIso8601String(),
            'transactionTime': tx.transactionTime,
            'attachmentPath': tx.attachmentPath,
            'isRecurring': tx.isRecurring,
            'recurringRuleId': tx.recurringRuleId,
          },
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            tx.fieldTimestampsJson,
          ),
          updatedAtUtc: tx.updatedAtUtc,
          deletedAtUtc: tx.deletedAtUtc,
        );

      case 'budget':
      case 'budgets':
        final b = await (_db.select(
          _db.budgetsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (b == null) return null;
        return _LocalEntityInfo(
          payload: {'monthYear': b.monthYear, 'amountMinor': b.amountMinor},
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            b.fieldTimestampsJson,
          ),
          updatedAtUtc: b.updatedAtUtc,
          deletedAtUtc: b.deletedAtUtc,
        );

      case 'categorybudget':
      case 'category_budget':
      case 'categorybudgets':
      case 'category_budgets':
        final cb = await (_db.select(
          _db.categoryBudgetsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (cb == null) return null;
        return _LocalEntityInfo(
          payload: {
            'budgetId': cb.budgetId,
            'categoryId': cb.categoryId,
            'amountMinor': cb.amountMinor,
          },
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            cb.fieldTimestampsJson,
          ),
          updatedAtUtc: cb.updatedAtUtc,
          deletedAtUtc: cb.deletedAtUtc,
        );

      case 'goal':
      case 'savingsgoal':
      case 'savings_goal':
      case 'savingsgoals':
      case 'savings_goals':
        final g = await (_db.select(
          _db.savingsGoalsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (g == null) return null;
        return _LocalEntityInfo(
          payload: {
            'name': g.name,
            'targetAmountMinor': g.targetAmountMinor,
            'currentAmountMinor': g.currentAmountMinor,
            'targetDateUtc': g.targetDateUtc.toIso8601String(),
            'iconCodePoint': g.iconCodePoint,
            'colorValue': g.colorValue,
          },
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            g.fieldTimestampsJson,
          ),
          updatedAtUtc: g.updatedAtUtc,
          deletedAtUtc: g.deletedAtUtc,
        );

      case 'recurringrule':
      case 'recurring_rule':
      case 'recurringtransaction':
      case 'recurring_transaction':
      case 'recurring_transactions':
        final r = await (_db.select(
          _db.recurringTransactionsTable,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        if (r == null) return null;
        return _LocalEntityInfo(
          payload: {
            'amountMinor': r.amountMinor,
            'transactionType': r.transactionType,
            'categoryId': r.categoryId,
            'accountId': r.accountId,
            'note': r.note,
            'frequency': r.frequency,
            'startDateUtc': r.startDateUtc.toIso8601String(),
            'nextOccurrenceUtc': r.nextOccurrenceUtc.toIso8601String(),
            'lastExecutedDateUtc': r.lastExecutedDateUtc?.toIso8601String(),
            'isActive': r.isActive,
          },
          fieldTimestamps: ConflictResolver.parseFieldTimestamps(
            r.fieldTimestampsJson,
          ),
          updatedAtUtc: r.updatedAtUtc,
          deletedAtUtc: r.deletedAtUtc,
        );

      default:
        return null;
    }
  }

  Future<void> _insertRemoteRecordToLocal({
    required String userId,
    required String entityType,
    required Map<String, dynamic> record,
    required Map<String, String> fieldTimestamps,
    required DateTime updatedAtUtc,
    required DateTime? deletedAtUtc,
  }) async {
    final id = record['id'] as String;
    final timestampsJson = ConflictResolver.encodeFieldTimestamps(
      fieldTimestamps,
    );

    switch (entityType.toLowerCase()) {
      case 'category':
      case 'categories':
        await _db
            .into(_db.categoriesTable)
            .insertOnConflictUpdate(
              CategoriesTableCompanion(
                id: Value(id),
                userId: Value(userId),
                name: Value(record['name'] as String? ?? 'General'),
                type: Value(record['type'] as String? ?? 'expense'),
                iconCodePoint: Value(
                  ((record['icon_code_point'] ??
                              record['iconCodePoint'] ??
                              58988)
                          as num)
                      .toInt(),
                ),
                colorValue: Value(
                  ((record['color_value'] ?? record['colorValue'] ?? 4279548070)
                          as num)
                      .toInt()
                      .toUnsigned(32),
                ),
                isSystem: Value(
                  (record['is_system'] ?? record['isSystem'] ?? false) as bool,
                ),
                isArchived: Value(
                  (record['is_archived'] ?? record['isArchived'] ?? false)
                      as bool,
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;

      case 'account':
      case 'accounts':
        await _db
            .into(_db.accountsTable)
            .insertOnConflictUpdate(
              AccountsTableCompanion(
                id: Value(id),
                userId: Value(userId),
                name: Value(record['name'] as String? ?? 'Account'),
                accountType: Value(
                  (record['account_type'] ?? record['accountType'])
                          as String? ??
                      'cash',
                ),
                currency: Value(record['currency'] as String? ?? 'INR'),
                initialBalanceMinor: Value(
                  ((record['initial_balance_minor'] ??
                              record['initialBalanceMinor'] ??
                              0)
                          as num)
                      .toInt(),
                ),
                colorValue: Value(
                  ((record['color_value'] ?? record['colorValue'] ?? 4279548070)
                          as num)
                      .toInt()
                      .toUnsigned(32),
                ),
                iconCodePoint: Value(
                  ((record['icon_code_point'] ??
                              record['iconCodePoint'] ??
                              57408)
                          as num)
                      .toInt(),
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;

      case 'transaction':
      case 'transactions':
        await _db
            .into(_db.transactionsTable)
            .insertOnConflictUpdate(
              TransactionsTableCompanion(
                id: Value(id),
                userId: Value(userId),
                amountMinor: Value(
                  ((record['amount_minor'] ?? record['amountMinor'] ?? 0)
                          as num)
                      .toInt(),
                ),
                transactionType: Value(
                  (record['transaction_type'] ?? record['transactionType'])
                          as String? ??
                      'expense',
                ),
                categoryId: Value(
                  (record['category_id'] ?? record['categoryId']) as String? ??
                      '',
                ),
                accountId: Value(
                  (record['account_id'] ?? record['accountId']) as String? ??
                      '',
                ),
                toAccountId: Value(
                  (record['to_account_id'] ?? record['toAccountId']) as String?,
                ),
                note: Value(record['note'] as String? ?? ''),
                transactionDateUtc: Value(
                  DateTime.tryParse(
                        (record['transaction_date_utc'] ??
                                    record['transactionDateUtc'])
                                as String? ??
                            '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                transactionTime: Value(
                  (record['transaction_time'] ?? record['transactionTime'])
                      as String?,
                ),
                attachmentPath: Value(
                  (record['attachment_path'] ?? record['attachmentPath'])
                      as String?,
                ),
                isRecurring: Value(
                  (record['is_recurring'] ?? record['isRecurring'] ?? false)
                      as bool,
                ),
                recurringRuleId: Value(
                  (record['recurring_rule_id'] ?? record['recurringRuleId'])
                      as String?,
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;

      case 'budget':
      case 'budgets':
        await _db
            .into(_db.budgetsTable)
            .insertOnConflictUpdate(
              BudgetsTableCompanion(
                id: Value(id),
                userId: Value(userId),
                monthYear: Value(
                  (record['month_year'] ?? record['monthYear']) as String? ??
                      '2026-09',
                ),
                amountMinor: Value(
                  ((record['amount_minor'] ?? record['amountMinor'] ?? 0)
                          as num)
                      .toInt(),
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;

      case 'categorybudget':
      case 'category_budget':
      case 'categorybudgets':
      case 'category_budgets':
        await _db
            .into(_db.categoryBudgetsTable)
            .insertOnConflictUpdate(
              CategoryBudgetsTableCompanion(
                id: Value(id),
                userId: Value(userId),
                budgetId: Value(
                  (record['budget_id'] ?? record['budgetId']) as String? ?? '',
                ),
                categoryId: Value(
                  (record['category_id'] ?? record['categoryId']) as String? ??
                      '',
                ),
                amountMinor: Value(
                  ((record['amount_minor'] ?? record['amountMinor'] ?? 0)
                          as num)
                      .toInt(),
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;

      case 'goal':
      case 'savingsgoal':
      case 'savings_goal':
      case 'savingsgoals':
      case 'savings_goals':
        await _db
            .into(_db.savingsGoalsTable)
            .insertOnConflictUpdate(
              SavingsGoalsTableCompanion(
                id: Value(id),
                userId: Value(userId),
                name: Value(record['name'] as String? ?? 'Goal'),
                targetAmountMinor: Value(
                  ((record['target_amount_minor'] ??
                              record['targetAmountMinor'] ??
                              10000)
                          as num)
                      .toInt(),
                ),
                currentAmountMinor: Value(
                  ((record['current_amount_minor'] ??
                              record['currentAmountMinor'] ??
                              0)
                          as num)
                      .toInt(),
                ),
                targetDateUtc: Value(
                  DateTime.tryParse(
                        (record['target_date_utc'] ?? record['targetDateUtc'])
                                as String? ??
                            '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                iconCodePoint: Value(
                  ((record['icon_code_point'] ??
                              record['iconCodePoint'] ??
                              58988)
                          as num)
                      .toInt(),
                ),
                colorValue: Value(
                  ((record['color_value'] ?? record['colorValue'] ?? 4279310721)
                          as num)
                      .toInt()
                      .toUnsigned(32),
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;

      case 'recurringrule':
      case 'recurring_rule':
      case 'recurringtransaction':
      case 'recurring_transaction':
      case 'recurring_transactions':
        await _db
            .into(_db.recurringTransactionsTable)
            .insertOnConflictUpdate(
              RecurringTransactionsTableCompanion(
                id: Value(id),
                userId: Value(userId),
                amountMinor: Value(
                  ((record['amount_minor'] ?? record['amountMinor'] ?? 0)
                          as num)
                      .toInt(),
                ),
                transactionType: Value(
                  (record['transaction_type'] ?? record['transactionType'])
                          as String? ??
                      'expense',
                ),
                categoryId: Value(
                  (record['category_id'] ?? record['categoryId']) as String? ??
                      '',
                ),
                accountId: Value(
                  (record['account_id'] ?? record['accountId']) as String? ??
                      '',
                ),
                note: Value(record['note'] as String? ?? ''),
                frequency: Value(record['frequency'] as String? ?? 'monthly'),
                startDateUtc: Value(
                  DateTime.tryParse(
                        (record['start_date_utc'] ?? record['startDateUtc'])
                                as String? ??
                            '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                nextOccurrenceUtc: Value(
                  DateTime.tryParse(
                        (record['next_occurrence_utc'] ??
                                    record['nextOccurrenceUtc'])
                                as String? ??
                            '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                lastExecutedDateUtc: Value(
                  record['last_executed_date_utc'] != null ||
                          record['lastExecutedDateUtc'] != null
                      ? DateTime.tryParse(
                          (record['last_executed_date_utc'] ??
                                      record['lastExecutedDateUtc'])
                                  as String? ??
                              '',
                        )?.toUtc()
                      : null,
                ),
                isActive: Value(
                  (record['is_active'] ?? record['isActive'] ?? true) as bool,
                ),
                createdAtUtc: Value(
                  DateTime.tryParse(
                        record['created_at_utc'] as String? ?? '',
                      )?.toUtc() ??
                      updatedAtUtc,
                ),
                updatedAtUtc: Value(updatedAtUtc),
                deletedAtUtc: Value(deletedAtUtc),
                syncStatus: const Value('synced'),
                fieldTimestampsJson: Value(timestampsJson),
              ),
            );
        break;
    }
  }

  Future<void> _updateLocalEntityFromReconciliation({
    required String userId,
    required String entityType,
    required String entityId,
    required FieldConflictResult conflictResult,
  }) async {
    final payload = conflictResult.mergedPayload;
    final timestampsJson = ConflictResolver.encodeFieldTimestamps(
      conflictResult.mergedFieldTimestamps,
    );
    final updatedAtUtc =
        DateTime.tryParse(payload['updatedAtUtc'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc();
    final deletedAtUtc = payload['deletedAtUtc'] != null
        ? DateTime.tryParse(payload['deletedAtUtc'] as String)?.toUtc()
        : null;

    switch (entityType.toLowerCase()) {
      case 'category':
      case 'categories':
        await (_db.update(
          _db.categoriesTable,
        )..where((t) => t.id.equals(entityId))).write(
          CategoriesTableCompanion(
            name: Value(payload['name'] as String? ?? 'General'),
            type: Value(payload['type'] as String? ?? 'expense'),
            iconCodePoint: Value(
              ((payload['iconCodePoint'] ?? payload['icon_code_point'] ?? 58988)
                      as num)
                  .toInt(),
            ),
            colorValue: Value(
              ((payload['colorValue'] ?? payload['color_value'] ?? 4279548070)
                      as num)
                  .toInt()
                  .toUnsigned(32),
            ),
            isSystem: Value(
              (payload['isSystem'] ?? payload['is_system'] ?? false) as bool,
            ),
            isArchived: Value(
              (payload['isArchived'] ?? payload['is_archived'] ?? false)
                  as bool,
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;

      case 'account':
      case 'accounts':
        await (_db.update(
          _db.accountsTable,
        )..where((t) => t.id.equals(entityId))).write(
          AccountsTableCompanion(
            name: Value(payload['name'] as String),
            accountType: Value(
              (payload['accountType'] ?? payload['account_type']) as String,
            ),
            currency: Value(payload['currency'] as String? ?? 'INR'),
            initialBalanceMinor: Value(
              ((payload['initialBalanceMinor'] ??
                          payload['initial_balance_minor'] ??
                          0)
                      as num)
                  .toInt(),
            ),
            colorValue: Value(
              ((payload['colorValue'] ?? payload['color_value'] ?? 4279548070)
                      as num)
                  .toInt()
                  .toUnsigned(32),
            ),
            iconCodePoint: Value(
              ((payload['iconCodePoint'] ?? payload['icon_code_point'] ?? 57408)
                      as num)
                  .toInt(),
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;

      case 'transaction':
      case 'transactions':
        await (_db.update(
          _db.transactionsTable,
        )..where((t) => t.id.equals(entityId))).write(
          TransactionsTableCompanion(
            amountMinor: Value(
              ((payload['amountMinor'] ?? payload['amount_minor']) as num)
                  .toInt(),
            ),
            transactionType: Value(
              (payload['transactionType'] ?? payload['transaction_type'])
                  as String,
            ),
            categoryId: Value(
              (payload['categoryId'] ?? payload['category_id']) as String,
            ),
            accountId: Value(
              (payload['accountId'] ?? payload['account_id']) as String,
            ),
            toAccountId: Value(
              (payload['toAccountId'] ?? payload['to_account_id']) as String?,
            ),
            note: Value(payload['note'] as String? ?? ''),
            transactionDateUtc: Value(
              DateTime.tryParse(
                    (payload['transactionDateUtc'] ??
                                payload['transaction_date_utc'])
                            as String? ??
                        '',
                  )?.toUtc() ??
                  updatedAtUtc,
            ),
            transactionTime: Value(
              (payload['transactionTime'] ?? payload['transaction_time'])
                  as String?,
            ),
            attachmentPath: Value(
              (payload['attachmentPath'] ?? payload['attachment_path'])
                  as String?,
            ),
            isRecurring: Value(
              (payload['isRecurring'] ?? payload['is_recurring'] ?? false)
                  as bool,
            ),
            recurringRuleId: Value(
              (payload['recurringRuleId'] ?? payload['recurring_rule_id'])
                  as String?,
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;

      case 'budget':
      case 'budgets':
        await (_db.update(
          _db.budgetsTable,
        )..where((t) => t.id.equals(entityId))).write(
          BudgetsTableCompanion(
            monthYear: Value(
              (payload['monthYear'] ?? payload['month_year']) as String,
            ),
            amountMinor: Value(
              ((payload['amountMinor'] ?? payload['amount_minor']) as num)
                  .toInt(),
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;

      case 'categorybudget':
      case 'category_budget':
      case 'categorybudgets':
      case 'category_budgets':
        await (_db.update(
          _db.categoryBudgetsTable,
        )..where((t) => t.id.equals(entityId))).write(
          CategoryBudgetsTableCompanion(
            budgetId: Value(
              (payload['budgetId'] ?? payload['budget_id']) as String,
            ),
            categoryId: Value(
              (payload['categoryId'] ?? payload['category_id']) as String,
            ),
            amountMinor: Value(
              ((payload['amountMinor'] ?? payload['amount_minor']) as num)
                  .toInt(),
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;

      case 'goal':
      case 'savingsgoal':
      case 'savings_goal':
      case 'savingsgoals':
      case 'savings_goals':
        await (_db.update(
          _db.savingsGoalsTable,
        )..where((t) => t.id.equals(entityId))).write(
          SavingsGoalsTableCompanion(
            name: Value(payload['name'] as String),
            targetAmountMinor: Value(
              ((payload['targetAmountMinor'] ?? payload['target_amount_minor'])
                      as num)
                  .toInt(),
            ),
            currentAmountMinor: Value(
              ((payload['currentAmountMinor'] ??
                          payload['current_amount_minor'] ??
                          0)
                      as num)
                  .toInt(),
            ),
            targetDateUtc: Value(
              DateTime.tryParse(
                    (payload['targetDateUtc'] ?? payload['target_date_utc'])
                            as String? ??
                        '',
                  )?.toUtc() ??
                  updatedAtUtc,
            ),
            iconCodePoint: Value(
              ((payload['iconCodePoint'] ?? payload['icon_code_point'] ?? 58988)
                      as num)
                  .toInt(),
            ),
            colorValue: Value(
              ((payload['colorValue'] ?? payload['color_value'] ?? 4279310721)
                      as num)
                  .toInt()
                  .toUnsigned(32),
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;

      case 'recurringrule':
      case 'recurring_rule':
      case 'recurringtransaction':
      case 'recurring_transaction':
      case 'recurring_transactions':
        await (_db.update(
          _db.recurringTransactionsTable,
        )..where((t) => t.id.equals(entityId))).write(
          RecurringTransactionsTableCompanion(
            amountMinor: Value(
              ((payload['amountMinor'] ?? payload['amount_minor']) as num)
                  .toInt(),
            ),
            transactionType: Value(
              (payload['transactionType'] ?? payload['transaction_type'])
                  as String,
            ),
            categoryId: Value(
              (payload['categoryId'] ?? payload['category_id']) as String,
            ),
            accountId: Value(
              (payload['accountId'] ?? payload['account_id']) as String,
            ),
            note: Value(payload['note'] as String? ?? ''),
            frequency: Value(payload['frequency'] as String),
            startDateUtc: Value(
              DateTime.tryParse(
                    (payload['startDateUtc'] ?? payload['start_date_utc'])
                            as String? ??
                        '',
                  )?.toUtc() ??
                  updatedAtUtc,
            ),
            nextOccurrenceUtc: Value(
              DateTime.tryParse(
                    (payload['nextOccurrenceUtc'] ??
                                payload['next_occurrence_utc'])
                            as String? ??
                        '',
                  )?.toUtc() ??
                  updatedAtUtc,
            ),
            lastExecutedDateUtc: Value(
              (payload['lastExecutedDateUtc'] ??
                          payload['last_executed_date_utc']) !=
                      null
                  ? DateTime.tryParse(
                      (payload['lastExecutedDateUtc'] ??
                                  payload['last_executed_date_utc'])
                              as String? ??
                          '',
                    )?.toUtc()
                  : null,
            ),
            isActive: Value(
              (payload['isActive'] ?? payload['is_active'] ?? true) as bool,
            ),
            updatedAtUtc: Value(updatedAtUtc),
            deletedAtUtc: Value(deletedAtUtc),
            syncStatus: const Value('synced'),
            fieldTimestampsJson: Value(timestampsJson),
          ),
        );
        break;
    }
  }

  Future<void> _markLocalEntitySynced({
    required String entityType,
    required String entityId,
  }) async {
    switch (entityType.toLowerCase()) {
      case 'category':
      case 'categories':
        await (_db.update(_db.categoriesTable)
              ..where((t) => t.id.equals(entityId)))
            .write(const CategoriesTableCompanion(syncStatus: Value('synced')));
        break;
      case 'account':
      case 'accounts':
        await (_db.update(_db.accountsTable)
              ..where((t) => t.id.equals(entityId)))
            .write(const AccountsTableCompanion(syncStatus: Value('synced')));
        break;
      case 'transaction':
      case 'transactions':
        await (_db.update(
          _db.transactionsTable,
        )..where((t) => t.id.equals(entityId))).write(
          const TransactionsTableCompanion(syncStatus: Value('synced')),
        );
        break;
      case 'budget':
      case 'budgets':
        await (_db.update(_db.budgetsTable)
              ..where((t) => t.id.equals(entityId)))
            .write(const BudgetsTableCompanion(syncStatus: Value('synced')));
        break;
      case 'categorybudget':
      case 'category_budget':
      case 'categorybudgets':
      case 'category_budgets':
        await (_db.update(
          _db.categoryBudgetsTable,
        )..where((t) => t.id.equals(entityId))).write(
          const CategoryBudgetsTableCompanion(syncStatus: Value('synced')),
        );
        break;
      case 'goal':
      case 'savingsgoal':
      case 'savings_goal':
      case 'savingsgoals':
      case 'savings_goals':
        await (_db.update(
          _db.savingsGoalsTable,
        )..where((t) => t.id.equals(entityId))).write(
          const SavingsGoalsTableCompanion(syncStatus: Value('synced')),
        );
        break;
      case 'recurringrule':
      case 'recurring_rule':
      case 'recurringtransaction':
      case 'recurring_transaction':
      case 'recurring_transactions':
        await (_db.update(
          _db.recurringTransactionsTable,
        )..where((t) => t.id.equals(entityId))).write(
          const RecurringTransactionsTableCompanion(
            syncStatus: Value('synced'),
          ),
        );
        break;
    }
  }

  EntityType _mapEntityType(String entityType) {
    switch (entityType.toLowerCase()) {
      case 'category':
      case 'categories':
        return EntityType.category;
      case 'account':
      case 'accounts':
        return EntityType.account;
      case 'transaction':
      case 'transactions':
        return EntityType.transaction;
      case 'budget':
      case 'budgets':
        return EntityType.budget;
      case 'categorybudget':
      case 'category_budget':
      case 'categorybudgets':
      case 'category_budgets':
        return EntityType.categoryBudget;
      case 'goal':
      case 'savingsgoal':
      case 'savings_goal':
      case 'savingsgoals':
      case 'savings_goals':
        return EntityType.goal;
      case 'recurringrule':
      case 'recurring_rule':
      case 'recurringtransaction':
      case 'recurring_transaction':
      case 'recurring_transactions':
        return EntityType.recurringRule;
      default:
        return EntityType.transaction;
    }
  }

  // ===========================================================================
  // GUEST DATA MIGRATION
  // ===========================================================================

  @override
  Future<void> migrateGuestData({
    required String guestUserId,
    required String targetUserId,
  }) async {
    if (guestUserId == targetUserId) return;

    final nowUtc = DateTime.now().toUtc();

    await _db.transaction(() async {
      // 1. Ensure target user entry exists in users table
      await _db
          .into(_db.usersTable)
          .insertOnConflictUpdate(
            UsersTableCompanion(
              id: Value(targetUserId),
              displayName: const Value('Authenticated User'),
              createdAtUtc: Value(nowUtc),
              lastActiveAtUtc: Value(nowUtc),
            ),
          );

      // 2. Migrate Accounts
      await (_db.update(
        _db.accountsTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const AccountsTableCompanion(syncStatus: Value('pendingCreate')),
      );
      await _db.customUpdate(
        'UPDATE accounts SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.accountsTable},
      );

      // 3. Migrate Categories
      await (_db.update(
        _db.categoriesTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const CategoriesTableCompanion(syncStatus: Value('pendingCreate')),
      );
      await _db.customUpdate(
        'UPDATE categories SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.categoriesTable},
      );

      // 4. Migrate Transactions
      await (_db.update(
        _db.transactionsTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const TransactionsTableCompanion(syncStatus: Value('pendingCreate')),
      );
      await _db.customUpdate(
        'UPDATE transactions SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.transactionsTable},
      );

      // 5. Migrate Budgets
      await (_db.update(
        _db.budgetsTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const BudgetsTableCompanion(syncStatus: Value('pendingCreate')),
      );
      await _db.customUpdate(
        'UPDATE budgets SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.budgetsTable},
      );

      // 6. Migrate Category Budgets
      await (_db.update(
        _db.categoryBudgetsTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const CategoryBudgetsTableCompanion(syncStatus: Value('pendingCreate')),
      );
      await _db.customUpdate(
        'UPDATE category_budgets SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.categoryBudgetsTable},
      );

      // 7. Migrate Savings Goals
      await (_db.update(
        _db.savingsGoalsTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const SavingsGoalsTableCompanion(syncStatus: Value('pendingCreate')),
      );
      await _db.customUpdate(
        'UPDATE savings_goals SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.savingsGoalsTable},
      );

      // 8. Migrate Recurring Transactions
      await (_db.update(
        _db.recurringTransactionsTable,
      )..where((t) => t.userId.equals(guestUserId))).write(
        const RecurringTransactionsTableCompanion(
          syncStatus: Value('pendingCreate'),
        ),
      );
      await _db.customUpdate(
        'UPDATE recurring_transactions SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.recurringTransactionsTable},
      );

      // 9. Migrate Settings
      await _db.customUpdate(
        'UPDATE settings SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.settingsTable},
      );

      // 10. Migrate Sync Queue Operations
      await _db.customUpdate(
        'UPDATE sync_operations SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.syncOperationsTable},
      );

      // 11. Migrate Sync Metadata
      await _db.customUpdate(
        'UPDATE sync_metadata SET user_id = ? WHERE user_id = ?',
        variables: [
          Variable.withString(targetUserId),
          Variable.withString(guestUserId),
        ],
        updates: {_db.syncMetadataTable},
      );
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _authSub?.cancel();
    _authSub = null;
    _stateController.close();
    _progressController.close();
  }
}

class _PushResult {
  final int pushedCount;
  const _PushResult({required this.pushedCount});
}

class _PullResult {
  final int pulledCount;
  final int conflictsResolvedCount;
  const _PullResult({
    required this.pulledCount,
    required this.conflictsResolvedCount,
  });
}

class _LocalEntityInfo {
  final Map<String, dynamic> payload;
  final Map<String, String> fieldTimestamps;
  final DateTime updatedAtUtc;
  final DateTime? deletedAtUtc;

  const _LocalEntityInfo({
    required this.payload,
    required this.fieldTimestamps,
    required this.updatedAtUtc,
    this.deletedAtUtc,
  });
}
