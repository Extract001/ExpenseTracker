import 'package:drift/drift.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/sync_operation_entity.dart';
import '../database/app_database.dart';

class SyncOperationMapper {
  static SyncOperationEntity fromData(SyncOperationData data) {
    return SyncOperationEntity(
      id: data.id,
      entityType: EntityType.values.firstWhere(
        (e) => e.name == data.entityType,
        orElse: () => EntityType.transaction,
      ),
      entityId: data.entityId,
      operationType: SyncOperationType.values.firstWhere(
        (op) => op.name == data.operationType,
        orElse: () => SyncOperationType.create,
      ),
      payloadJson: data.payloadJson,
      createdAt: data.createdAtUtc.toUtc(),
      retryCount: data.retryCount,
      lastAttemptAt: data.lastAttemptAtUtc?.toUtc(),
      errorMessage: data.errorMessage,
    );
  }

  static SyncOperationsTableCompanion toCompanion(
    SyncOperationEntity entity, {
    required String userId,
  }) {
    return SyncOperationsTableCompanion(
      id: Value(entity.id),
      userId: Value(userId),
      entityType: Value(entity.entityType.name),
      entityId: Value(entity.entityId),
      operationType: Value(entity.operationType.name),
      payloadJson: Value(entity.payloadJson),
      createdAtUtc: Value(entity.createdAt.toUtc()),
      retryCount: Value(entity.retryCount),
      lastAttemptAtUtc: Value(entity.lastAttemptAt?.toUtc()),
      errorMessage: Value(entity.errorMessage),
    );
  }
}
