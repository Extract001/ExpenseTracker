import 'package:drift/drift.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/enums.dart';
import '../database/app_database.dart';

class SyncQueueHelper {
  /// Enqueues a CREATE operation into the sync queue.
  static Future<void> enqueueCreate(
    AppDatabase db, {
    required String userId,
    required EntityType entityType,
    required String entityId,
    required String payloadJson,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    await db.syncQueueDao.enqueueOperation(
      SyncOperationsTableCompanion(
        id: Value(IdGenerator.uuid()),
        userId: Value(userId),
        entityType: Value(entityType.name),
        entityId: Value(entityId),
        operationType: Value(SyncOperationType.create.name),
        payloadJson: Value(payloadJson),
        createdAtUtc: Value(nowUtc),
        retryCount: const Value(0),
      ),
    );
  }

  /// Handles mutation updates with queue coalescing:
  /// - If entity was pendingCreate, updates the existing CREATE payload in queue.
  /// - If entity was synced or pendingUpdate, updates existing UPDATE or creates new UPDATE payload.
  static Future<void> enqueueUpdate(
    AppDatabase db, {
    required String userId,
    required EntityType entityType,
    required String entityId,
    required String payloadJson,
    required SyncStatus currentSyncStatus,
  }) async {
    final nowUtc = DateTime.now().toUtc();

    if (currentSyncStatus == SyncStatus.pendingCreate) {
      final pendingOps =
          await (db.select(db.syncOperationsTable)..where(
                (op) =>
                    op.userId.equals(userId) &
                    op.entityId.equals(entityId) &
                    op.operationType.equals(SyncOperationType.create.name),
              ))
              .get();

      if (pendingOps.isNotEmpty) {
        final existingOp = pendingOps.first;
        await (db.update(
          db.syncOperationsTable,
        )..where((op) => op.id.equals(existingOp.id))).write(
          SyncOperationsTableCompanion(
            payloadJson: Value(payloadJson),
            createdAtUtc: Value(nowUtc),
          ),
        );
        return;
      }
    }

    final pendingUpdates =
        await (db.select(db.syncOperationsTable)..where(
              (op) =>
                  op.userId.equals(userId) &
                  op.entityId.equals(entityId) &
                  op.operationType.equals(SyncOperationType.update.name),
            ))
            .get();

    if (pendingUpdates.isNotEmpty) {
      final existingOp = pendingUpdates.first;
      await (db.update(
        db.syncOperationsTable,
      )..where((op) => op.id.equals(existingOp.id))).write(
        SyncOperationsTableCompanion(
          payloadJson: Value(payloadJson),
          createdAtUtc: Value(nowUtc),
        ),
      );
    } else {
      await db.syncQueueDao.enqueueOperation(
        SyncOperationsTableCompanion(
          id: Value(IdGenerator.uuid()),
          userId: Value(userId),
          entityType: Value(entityType.name),
          entityId: Value(entityId),
          operationType: Value(SyncOperationType.update.name),
          payloadJson: Value(payloadJson),
          createdAtUtc: Value(nowUtc),
          retryCount: const Value(0),
        ),
      );
    }
  }

  /// Handles entity deletion with queue coalescing:
  /// - If entity was pendingCreate, remove from sync queue entirely (never sent to cloud).
  /// - If entity was synced or pendingUpdate, delete any pending UPDATE and enqueue a DELETE operation.
  static Future<void> enqueueDelete(
    AppDatabase db, {
    required String userId,
    required EntityType entityType,
    required String entityId,
    required SyncStatus currentSyncStatus,
  }) async {
    final nowUtc = DateTime.now().toUtc();

    if (currentSyncStatus == SyncStatus.pendingCreate) {
      await (db.delete(db.syncOperationsTable)..where(
            (op) => op.userId.equals(userId) & op.entityId.equals(entityId),
          ))
          .go();
      return;
    }

    await (db.delete(db.syncOperationsTable)..where(
          (op) =>
              op.userId.equals(userId) &
              op.entityId.equals(entityId) &
              op.operationType.equals(SyncOperationType.update.name),
        ))
        .go();

    final existingDelete =
        await (db.select(db.syncOperationsTable)..where(
              (op) =>
                  op.userId.equals(userId) &
                  op.entityId.equals(entityId) &
                  op.operationType.equals(SyncOperationType.delete.name),
            ))
            .getSingleOrNull();

    if (existingDelete == null) {
      await db.syncQueueDao.enqueueOperation(
        SyncOperationsTableCompanion(
          id: Value(IdGenerator.uuid()),
          userId: Value(userId),
          entityType: Value(entityType.name),
          entityId: Value(entityId),
          operationType: Value(SyncOperationType.delete.name),
          payloadJson: const Value('{}'),
          createdAtUtc: Value(nowUtc),
          retryCount: const Value(0),
        ),
      );
    }
  }
}
