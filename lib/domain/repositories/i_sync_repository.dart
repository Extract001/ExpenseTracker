import '../entities/sync_operation_entity.dart';

abstract class ISyncRepository {
  Future<void> enqueueOperation(SyncOperationEntity operation);
  Future<List<SyncOperationEntity>> getPendingOperations({int limit = 50});
  Future<void> markOperationCompleted(String id);
  Future<void> markOperationFailed(String id, String errorMessage);
  Future<int> getPendingCount();
  Stream<int> watchPendingCount();
  Stream<List<SyncOperationEntity>> watchPendingOperations({int limit = 50});
}
