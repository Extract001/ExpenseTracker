import 'dart:convert';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/enums.dart';
import '../../domain/repositories/i_budget_repository.dart';
import '../database/app_database.dart';
import '../models/budget_mapper.dart';
import 'sync_queue_helper.dart';

class BudgetRepository implements IBudgetRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  BudgetRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Stream<BudgetEntity?> watchMonthlyBudget(String monthYear) {
    return _db.budgetDao
        .watchMonthlyBudget(userId: _userId, monthYear: monthYear)
        .map((b) => b != null ? BudgetMapper.fromData(b) : null);
  }

  @override
  Stream<List<CategoryBudgetEntity>> watchCategoryBudgets(String budgetId) {
    return _db.budgetDao
        .watchCategoryBudgets(userId: _userId, budgetId: budgetId)
        .map((list) => list.map(BudgetMapper.fromCategoryData).toList());
  }

  @override
  Future<BudgetEntity?> getMonthlyBudget(String monthYear) async {
    final b = await _db.budgetDao.getMonthlyBudget(
      userId: _userId,
      monthYear: monthYear,
    );
    return b != null ? BudgetMapper.fromData(b) : null;
  }

  @override
  Future<void> setMonthlyBudget(BudgetEntity budget) async {
    final nowUtc = DateTime.now().toUtc();
    final effectiveId = budget.id.isEmpty ? IdGenerator.uuid() : budget.id;

    final existing = await _db.budgetDao.getMonthlyBudget(
      userId: _userId,
      monthYear: budget.monthYear,
    );

    final currentSyncStatus = existing != null
        ? SyncStatus.values.firstWhere(
            (s) => s.name == existing.syncStatus,
            orElse: () => SyncStatus.pendingCreate,
          )
        : SyncStatus.pendingCreate;

    final entityToSave = budget.copyWith(
      id: existing?.id ?? effectiveId,
      userId: _userId,
      createdAt: existing?.createdAtUtc.toUtc() ?? nowUtc,
      updatedAt: nowUtc,
      syncStatus: currentSyncStatus == SyncStatus.pendingCreate
          ? SyncStatus.pendingCreate
          : SyncStatus.pendingUpdate,
    );

    await _db.transaction(() async {
      await _db.budgetDao.upsertMonthlyBudget(
        BudgetMapper.toCompanion(entityToSave),
      );
      if (existing == null) {
        await SyncQueueHelper.enqueueCreate(
          _db,
          userId: _userId,
          entityType: EntityType.budget,
          entityId: entityToSave.id,
          payloadJson: jsonEncode({
            'id': entityToSave.id,
            'userId': entityToSave.userId,
            'monthYear': entityToSave.monthYear,
            'amountMinor': entityToSave.amount,
            'createdAtUtc': entityToSave.createdAt.toIso8601String(),
            'updatedAtUtc': entityToSave.updatedAt.toIso8601String(),
            'syncStatus': entityToSave.syncStatus.name,
          }),
        );
      } else {
        await SyncQueueHelper.enqueueUpdate(
          _db,
          userId: _userId,
          entityType: EntityType.budget,
          entityId: entityToSave.id,
          payloadJson: jsonEncode({
            'id': entityToSave.id,
            'userId': entityToSave.userId,
            'monthYear': entityToSave.monthYear,
            'amountMinor': entityToSave.amount,
            'createdAtUtc': entityToSave.createdAt.toIso8601String(),
            'updatedAtUtc': entityToSave.updatedAt.toIso8601String(),
            'syncStatus': entityToSave.syncStatus.name,
          }),
          currentSyncStatus: currentSyncStatus,
        );
      }
    });
  }

  @override
  Future<void> setCategoryBudget(CategoryBudgetEntity categoryBudget) async {
    final nowUtc = DateTime.now().toUtc();
    final effectiveId = categoryBudget.id.isEmpty
        ? IdGenerator.uuid()
        : categoryBudget.id;

    final existingList = await _db.budgetDao.getCategoryBudgets(
      userId: _userId,
      budgetId: categoryBudget.budgetId,
    );
    final existing = existingList
        .where((cb) => cb.categoryId == categoryBudget.categoryId)
        .firstOrNull;

    final currentSyncStatus = existing != null
        ? SyncStatus.values.firstWhere(
            (s) => s.name == existing.syncStatus,
            orElse: () => SyncStatus.pendingCreate,
          )
        : SyncStatus.pendingCreate;

    final entityToSave = categoryBudget.copyWith(
      id: existing?.id ?? effectiveId,
      userId: _userId,
      createdAt: existing?.createdAtUtc.toUtc() ?? nowUtc,
      updatedAt: nowUtc,
      syncStatus: currentSyncStatus == SyncStatus.pendingCreate
          ? SyncStatus.pendingCreate
          : SyncStatus.pendingUpdate,
    );

    await _db.transaction(() async {
      await _db.budgetDao.upsertCategoryBudget(
        BudgetMapper.toCategoryCompanion(entityToSave),
      );
      if (existing == null) {
        await SyncQueueHelper.enqueueCreate(
          _db,
          userId: _userId,
          entityType: EntityType.categoryBudget,
          entityId: entityToSave.id,
          payloadJson: jsonEncode({
            'id': entityToSave.id,
            'userId': entityToSave.userId,
            'budgetId': entityToSave.budgetId,
            'categoryId': entityToSave.categoryId,
            'amountMinor': entityToSave.amount,
            'createdAtUtc': entityToSave.createdAt.toIso8601String(),
            'updatedAtUtc': entityToSave.updatedAt.toIso8601String(),
            'syncStatus': entityToSave.syncStatus.name,
          }),
        );
      } else {
        await SyncQueueHelper.enqueueUpdate(
          _db,
          userId: _userId,
          entityType: EntityType.categoryBudget,
          entityId: entityToSave.id,
          payloadJson: jsonEncode({
            'id': entityToSave.id,
            'userId': entityToSave.userId,
            'budgetId': entityToSave.budgetId,
            'categoryId': entityToSave.categoryId,
            'amountMinor': entityToSave.amount,
            'createdAtUtc': entityToSave.createdAt.toIso8601String(),
            'updatedAtUtc': entityToSave.updatedAt.toIso8601String(),
            'syncStatus': entityToSave.syncStatus.name,
          }),
          currentSyncStatus: currentSyncStatus,
        );
      }
    });
  }

  @override
  Future<int> getSpentAmountForMonth(String monthYear) {
    final parts = monthYear.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = parts.length > 1
        ? (int.tryParse(parts[1]) ?? DateTime.now().month)
        : 1;
    final dt = DateTime(year, month, 1);
    final start = DateTimeUtils.startOfMonthUtc(dt);
    final end = DateTimeUtils.endOfMonthUtc(dt);

    return _db.transactionDao.getTotalExpense(
      userId: _userId,
      startDateUtc: start,
      endDateUtc: end,
    );
  }

  @override
  Future<int> getSpentAmountForCategory(String categoryId, String monthYear) {
    final parts = monthYear.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = parts.length > 1
        ? (int.tryParse(parts[1]) ?? DateTime.now().month)
        : 1;
    final dt = DateTime(year, month, 1);
    final start = DateTimeUtils.startOfMonthUtc(dt);
    final end = DateTimeUtils.endOfMonthUtc(dt);

    return _db.budgetDao.getSpentAmountForCategory(
      userId: _userId,
      categoryId: categoryId,
      startDateUtc: start,
      endDateUtc: end,
    );
  }
}
