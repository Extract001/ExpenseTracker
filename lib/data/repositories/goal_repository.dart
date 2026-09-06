import 'dart:convert';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/goal_entity.dart';
import '../../domain/repositories/i_goal_repository.dart';
import '../database/app_database.dart';
import '../models/goal_mapper.dart';
import 'sync_queue_helper.dart';

/// Repository for Savings Goals.
///
/// SOURCE OF TRUTH ARCHITECTURAL DECISION:
/// - currentAmountMinor in the database (savings_goals table) is the AUTHORITATIVE PERSISTED STATE
///   for the goal's accumulated savings.
/// - It is modified exclusively through:
///   1. [addProgress] (atomic increments/decrements from user deposits/contributions)
///   2. [updateGoal] (explicit administrative/target adjustments)
///   3. Field-level cloud synchronization via fieldTimestamps['currentAmountMinor'].
/// - progressPercentage and remainingAmount are pure computed getter projections on [GoalEntity].
class GoalRepository implements IGoalRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  GoalRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Stream<List<GoalEntity>> watchAllGoals() {
    return _db.goalDao
        .watchAllGoals(_userId)
        .map((list) => list.map(GoalMapper.fromData).toList());
  }

  @override
  Future<List<GoalEntity>> getAllGoals() async {
    final list = await _db.goalDao.getAllGoals(_userId);
    return list.map(GoalMapper.fromData).toList();
  }

  @override
  Future<GoalEntity?> getGoalById(String id) async {
    final g = await _db.goalDao.getGoalById(id);
    if (g == null || g.userId != _userId || g.deletedAtUtc != null) {
      return null;
    }
    return GoalMapper.fromData(g);
  }

  @override
  Future<void> createGoal(GoalEntity goal) async {
    if (goal.name.trim().isEmpty) {
      throw const ValidationException('Goal name cannot be empty');
    }
    if (goal.targetAmount <= 0) {
      throw const ValidationException('Goal target amount must be positive');
    }

    final nowUtc = DateTime.now().toUtc();
    final effectiveId = goal.id.isEmpty ? IdGenerator.uuid() : goal.id;

    final initialTimestamps = Map<String, String>.from(goal.fieldTimestamps);
    final isoNow = nowUtc.toIso8601String();
    for (final f in [
      'name',
      'targetAmountMinor',
      'currentAmountMinor',
      'targetDateUtc',
      'iconCodePoint',
      'colorValue',
    ]) {
      initialTimestamps.putIfAbsent(f, () => isoNow);
    }

    final entityToSave = goal.copyWith(
      id: effectiveId,
      userId: _userId,
      createdAt: goal.createdAt.year == 0 ? nowUtc : goal.createdAt.toUtc(),
      updatedAt: nowUtc,
      syncStatus: SyncStatus.pendingCreate,
      fieldTimestamps: initialTimestamps,
    );

    await _db.transaction(() async {
      await _db.goalDao.insertGoal(GoalMapper.toCompanion(entityToSave));
      await SyncQueueHelper.enqueueCreate(
        _db,
        userId: _userId,
        entityType: EntityType.goal,
        entityId: effectiveId,
        payloadJson: jsonEncode({
          'id': entityToSave.id,
          'userId': entityToSave.userId,
          'name': entityToSave.name,
          'targetAmountMinor': entityToSave.targetAmount,
          'currentAmountMinor': entityToSave.currentAmount,
          'targetDateUtc': entityToSave.targetDate.toUtc().toIso8601String(),
          'iconCodePoint': entityToSave.iconCodePoint,
          'colorValue': entityToSave.colorValue,
          'createdAtUtc': entityToSave.createdAt.toUtc().toIso8601String(),
          'updatedAtUtc': entityToSave.updatedAt.toUtc().toIso8601String(),
          'syncStatus': entityToSave.syncStatus.name,
          'fieldTimestamps': entityToSave.fieldTimestamps,
        }),
      );
    });
  }

  @override
  Future<void> updateGoal(GoalEntity goal) async {
    final existing = await _db.goalDao.getGoalById(goal.id);
    if (existing == null || existing.userId != _userId) {
      throw NotFoundException('Goal not found or unauthorized: ');
    }

    final nowUtc = DateTime.now().toUtc();
    final isoNow = nowUtc.toIso8601String();

    Map<String, String> existingTimestamps = {};
    try {
      if (existing.fieldTimestampsJson.isNotEmpty) {
        final decoded = jsonDecode(existing.fieldTimestampsJson);
        if (decoded is Map) {
          existingTimestamps = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      }
    } catch (_) {}

    final updatedTimestamps = Map<String, String>.from(existingTimestamps);
    if (existing.name != goal.name) updatedTimestamps['name'] = isoNow;
    if (existing.targetAmountMinor != goal.targetAmount) {
      updatedTimestamps['targetAmountMinor'] = isoNow;
    }
    if (existing.currentAmountMinor != goal.currentAmount) {
      updatedTimestamps['currentAmountMinor'] = isoNow;
    }
    if (existing.targetDateUtc.toUtc() != goal.targetDate.toUtc()) {
      updatedTimestamps['targetDateUtc'] = isoNow;
    }
    if (existing.iconCodePoint != goal.iconCodePoint) {
      updatedTimestamps['iconCodePoint'] = isoNow;
    }
    if (existing.colorValue != goal.colorValue) {
      updatedTimestamps['colorValue'] = isoNow;
    }

    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    final newSyncStatus = currentSyncStatus == SyncStatus.pendingCreate
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    final updatedEntity = goal.copyWith(
      userId: _userId,
      updatedAt: nowUtc,
      syncStatus: newSyncStatus,
      fieldTimestamps: updatedTimestamps,
    );

    await _db.transaction(() async {
      await _db.goalDao.updateGoal(GoalMapper.toCompanion(updatedEntity));
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.goal,
        entityId: goal.id,
        payloadJson: jsonEncode({
          'id': updatedEntity.id,
          'userId': updatedEntity.userId,
          'name': updatedEntity.name,
          'targetAmountMinor': updatedEntity.targetAmount,
          'currentAmountMinor': updatedEntity.currentAmount,
          'targetDateUtc': updatedEntity.targetDate.toUtc().toIso8601String(),
          'iconCodePoint': updatedEntity.iconCodePoint,
          'colorValue': updatedEntity.colorValue,
          'createdAtUtc': updatedEntity.createdAt.toUtc().toIso8601String(),
          'updatedAtUtc': updatedEntity.updatedAt.toUtc().toIso8601String(),
          'syncStatus': updatedEntity.syncStatus.name,
          'fieldTimestamps': updatedEntity.fieldTimestamps,
        }),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> addProgress(String id, int amount) async {
    final existing = await _db.goalDao.getGoalById(id);
    if (existing == null || existing.userId != _userId) {
      throw NotFoundException('Goal not found or unauthorized: ');
    }

    final newAmount = existing.currentAmountMinor + amount;
    final nowUtc = DateTime.now().toUtc();
    final isoNow = nowUtc.toIso8601String();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    Map<String, String> existingTimestamps = {};
    try {
      if (existing.fieldTimestampsJson.isNotEmpty) {
        final decoded = jsonDecode(existing.fieldTimestampsJson);
        if (decoded is Map) {
          existingTimestamps = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      }
    } catch (_) {}

    final updatedTimestamps = Map<String, String>.from(existingTimestamps);
    updatedTimestamps['currentAmountMinor'] = isoNow;

    await _db.transaction(() async {
      await _db.goalDao.updateGoalProgress(
        id: id,
        newCurrentAmountMinor: newAmount,
        updatedAtUtc: nowUtc,
        syncStatus: currentSyncStatus == SyncStatus.pendingCreate
            ? SyncStatus.pendingCreate.name
            : SyncStatus.pendingUpdate.name,
      );
      final updatedGoal = GoalMapper.fromData(existing).copyWith(
        currentAmount: newAmount,
        updatedAt: nowUtc,
        fieldTimestamps: updatedTimestamps,
      );
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.goal,
        entityId: id,
        payloadJson: jsonEncode({
          'id': updatedGoal.id,
          'userId': updatedGoal.userId,
          'name': updatedGoal.name,
          'targetAmountMinor': updatedGoal.targetAmount,
          'currentAmountMinor': updatedGoal.currentAmount,
          'targetDateUtc': updatedGoal.targetDate.toUtc().toIso8601String(),
          'iconCodePoint': updatedGoal.iconCodePoint,
          'colorValue': updatedGoal.colorValue,
          'createdAtUtc': updatedGoal.createdAt.toUtc().toIso8601String(),
          'updatedAtUtc': updatedGoal.updatedAt.toUtc().toIso8601String(),
          'syncStatus': updatedGoal.syncStatus.name,
          'fieldTimestamps': updatedGoal.fieldTimestamps,
        }),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> softDeleteGoal(String id) async {
    final existing = await _db.goalDao.getGoalById(id);
    if (existing == null || existing.userId != _userId) return;

    final nowUtc = DateTime.now().toUtc();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.goalDao.softDeleteGoal(
        id: id,
        deletedAtUtc: nowUtc,
        syncStatus: currentSyncStatus == SyncStatus.pendingCreate
            ? SyncStatus.pendingCreate.name
            : SyncStatus.pendingDelete.name,
      );
      await SyncQueueHelper.enqueueDelete(
        _db,
        userId: _userId,
        entityType: EntityType.goal,
        entityId: id,
        currentSyncStatus: currentSyncStatus,
      );
    });
  }
}
