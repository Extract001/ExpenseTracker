import 'enums.dart';

class SyncOperationEntity {
  final String id;
  final EntityType entityType;
  final String entityId;
  final SyncOperationType operationType;
  final String payloadJson;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final String? errorMessage;

  const SyncOperationEntity({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.payloadJson,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.errorMessage,
  });

  SyncOperationEntity copyWith({
    String? id,
    EntityType? entityType,
    String? entityId,
    SyncOperationType? operationType,
    String? payloadJson,
    DateTime? createdAt,
    int? retryCount,
    DateTime? lastAttemptAt,
    String? errorMessage,
  }) {
    return SyncOperationEntity(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
