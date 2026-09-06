import 'dart:convert';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/enums.dart';
import '../../domain/repositories/i_category_repository.dart';
import '../database/app_database.dart';
import '../models/category_mapper.dart';
import 'sync_queue_helper.dart';

class CategoryRepository implements ICategoryRepository {
  final AppDatabase _db;
  final String Function()? _getUserId;

  CategoryRepository(this._db, [this._getUserId]);

  String get _userId => _getUserId?.call() ?? AppConstants.defaultUserId;

  @override
  Stream<List<CategoryEntity>> watchCategories({TransactionType? type}) {
    return _db.categoryDao
        .watchCategories(userId: _userId, type: type?.name)
        .map((list) => list.map(CategoryMapper.fromData).toList());
  }

  @override
  Future<List<CategoryEntity>> getAllCategories({TransactionType? type}) async {
    final list = await _db.categoryDao.getAllCategories(
      userId: _userId,
      type: type?.name,
    );
    return list.map(CategoryMapper.fromData).toList();
  }

  @override
  Future<CategoryEntity?> getCategoryById(String id) async {
    final cat = await _db.categoryDao.getCategoryById(id);
    if (cat == null || cat.userId != _userId || cat.deletedAtUtc != null) {
      return null;
    }
    return CategoryMapper.fromData(cat);
  }

  @override
  Future<void> createCategory(CategoryEntity category) async {
    if (category.name.trim().isEmpty) {
      throw const ValidationException('Category name cannot be empty');
    }

    final nowUtc = DateTime.now().toUtc();
    final effectiveId = category.id.isEmpty ? IdGenerator.uuid() : category.id;

    final initialTimestamps = Map<String, String>.from(
      category.fieldTimestamps,
    );
    final isoNow = nowUtc.toIso8601String();
    for (final f in [
      'name',
      'type',
      'iconCodePoint',
      'colorValue',
      'isArchived',
    ]) {
      initialTimestamps.putIfAbsent(f, () => isoNow);
    }

    final entityToSave = category.copyWith(
      id: effectiveId,
      userId: _userId,
      createdAt: category.createdAt.year == 0
          ? nowUtc
          : category.createdAt.toUtc(),
      updatedAt: nowUtc,
      syncStatus: SyncStatus.pendingCreate,
      fieldTimestamps: initialTimestamps,
    );

    await _db.transaction(() async {
      await _db.categoryDao.insertCategory(
        CategoryMapper.toCompanion(entityToSave),
      );
      await SyncQueueHelper.enqueueCreate(
        _db,
        userId: _userId,
        entityType: EntityType.category,
        entityId: effectiveId,
        payloadJson: CategoryMapper.toJsonPayload(entityToSave),
      );
    });
  }

  @override
  Future<void> updateCategory(CategoryEntity category) async {
    final existing = await _db.categoryDao.getCategoryById(category.id);
    if (existing == null || existing.userId != _userId) {
      throw NotFoundException('Category not found or unauthorized: ');
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
    if (existing.name != category.name) updatedTimestamps['name'] = isoNow;
    if (existing.type != category.type.name) {
      updatedTimestamps['type'] = isoNow;
    }
    if (existing.iconCodePoint != category.iconCodePoint) {
      updatedTimestamps['iconCodePoint'] = isoNow;
    }
    if (existing.colorValue != category.colorValue) {
      updatedTimestamps['colorValue'] = isoNow;
    }
    if (existing.isArchived != category.isArchived) {
      updatedTimestamps['isArchived'] = isoNow;
    }

    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    final newSyncStatus = currentSyncStatus == SyncStatus.pendingCreate
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    final updatedEntity = category.copyWith(
      userId: _userId,
      isSystem: existing.isSystem,
      updatedAt: nowUtc,
      syncStatus: newSyncStatus,
      fieldTimestamps: updatedTimestamps,
    );

    await _db.transaction(() async {
      await _db.categoryDao.updateCategory(
        CategoryMapper.toCompanion(updatedEntity),
      );
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.category,
        entityId: category.id,
        payloadJson: CategoryMapper.toJsonPayload(updatedEntity),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> archiveCategory(String id) async {
    final existing = await _db.categoryDao.getCategoryById(id);
    if (existing == null || existing.userId != _userId) return;

    final nowUtc = DateTime.now().toUtc();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.categoryDao.archiveCategory(
        id: id,
        isArchived: true,
        updatedAtUtc: nowUtc,
        syncStatus: currentSyncStatus == SyncStatus.pendingCreate
            ? SyncStatus.pendingCreate.name
            : SyncStatus.pendingUpdate.name,
      );
      final updatedCat = CategoryMapper.fromData(
        existing,
      ).copyWith(isArchived: true, updatedAt: nowUtc);
      await SyncQueueHelper.enqueueUpdate(
        _db,
        userId: _userId,
        entityType: EntityType.category,
        entityId: id,
        payloadJson: CategoryMapper.toJsonPayload(updatedCat),
        currentSyncStatus: currentSyncStatus,
      );
    });
  }

  @override
  Future<void> softDeleteCategory(String id) async {
    final existing = await _db.categoryDao.getCategoryById(id);
    if (existing == null || existing.userId != _userId) return;

    if (existing.isSystem) {
      throw UnsupportedError(
        'System default categories cannot be deleted. Archive them instead.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final currentSyncStatus = SyncStatus.values.firstWhere(
      (s) => s.name == existing.syncStatus,
      orElse: () => SyncStatus.pendingCreate,
    );

    await _db.transaction(() async {
      await _db.categoryDao.softDeleteCategory(
        id: id,
        deletedAtUtc: nowUtc,
        syncStatus: currentSyncStatus == SyncStatus.pendingCreate
            ? SyncStatus.pendingCreate.name
            : SyncStatus.pendingDelete.name,
      );
      await SyncQueueHelper.enqueueDelete(
        _db,
        userId: _userId,
        entityType: EntityType.category,
        entityId: id,
        currentSyncStatus: currentSyncStatus,
      );
    });
  }
}
