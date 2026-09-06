import '../../core/constants/app_constants.dart';
import '../../domain/entities/sync_operation_entity.dart';
import '../../domain/repositories/i_sync_repository.dart';
import '../database/app_database.dart';
import '../models/sync_operation_mapper.dart';

class SyncRepository implements ISyncRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  SyncRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Future<void> enqueueOperation(SyncOperationEntity operation) {
    return _db.syncQueueDao.enqueueOperation(
      SyncOperationMapper.toCompanion(operation, userId: _userId),
    );
  }

  @override
  Future<List<SyncOperationEntity>> getPendingOperations({
    int limit = 50,
  }) async {
    final list = await _db.syncQueueDao.getPendingOperations(
      userId: _userId,
      limit: limit,
    );
    return list.map(SyncOperationMapper.fromData).toList();
  }

  @override
  Future<void> markOperationCompleted(String id) {
    return _db.syncQueueDao.deleteOperation(id);
  }

  @override
  Future<void> markOperationFailed(String id, String errorMessage) {
    return _db.syncQueueDao.recordOperationFailure(
      id: id,
      errorMessage: errorMessage,
      attemptTimeUtc: DateTime.now().toUtc(),
    );
  }

  @override
  Future<int> getPendingCount() {
    return _db.syncQueueDao.getPendingCount(_userId);
  }

  @override
  Stream<int> watchPendingCount() {
    return _db.syncQueueDao.watchPendingCount(_userId);
  }

  @override
  Stream<List<SyncOperationEntity>> watchPendingOperations({int limit = 50}) {
    return _db.syncQueueDao
        .watchPendingOperations(userId: _userId, limit: limit)
        .map((list) => list.map(SyncOperationMapper.fromData).toList());
  }
}
