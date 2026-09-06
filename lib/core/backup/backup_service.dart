import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../security/hashing_service.dart';
import '../utils/app_logger.dart';
import 'backup_models.dart';

/// Service providing atomic, transactional backup creation and recovery.
class BackupService {
  final AppDatabase _db;

  BackupService(this._db);

  static String? _isoUtc(DateTime? dt) => dt?.toUtc().toIso8601String();

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static void _checkUniqueIds(
    List<Map<String, dynamic>> items,
    String entityName,
  ) {
    final seen = <String>{};
    for (final item in items) {
      final id = item['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ValidationException('Missing or empty ID in $entityName.');
      }
      if (!seen.add(id)) {
        throw ValidationException('Duplicate ID "$id" found in $entityName.');
      }
    }
  }

  static DateTime _parseUtcTimestamp(
    dynamic value,
    String fieldName,
    String entityId,
  ) {
    if (value is! String) {
      throw ValidationException(
        'Malformed timestamp for field "$fieldName" in entity "$entityId": expected ISO 8601 string.',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw ValidationException(
        'Malformed timestamp "$value" for field "$fieldName" in entity "$entityId".',
      );
    }
    return parsed.toUtc();
  }

  static void _validateFieldTimestampsJson(dynamic value, String entityId) {
    if (value == null) return;
    if (value is! String) {
      throw ValidationException(
        'Malformed fieldTimestampsJson for entity "$entityId": must be a JSON string.',
      );
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '{}') return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        throw ValidationException(
          'Malformed fieldTimestampsJson for entity "$entityId": must be a JSON object.',
        );
      }
      for (final entry in decoded.entries) {
        if (entry.value is! String ||
            DateTime.tryParse(entry.value as String) == null) {
          throw ValidationException(
            'Malformed timestamp in fieldTimestampsJson for field "${entry.key}" in entity "$entityId".',
          );
        }
      }
    } catch (e) {
      if (e is ValidationException) rethrow;
      throw ValidationException(
        'Malformed fieldTimestampsJson for entity "$entityId": invalid JSON ($e).',
      );
    }
  }

  /// Creates a full transactional snapshot across all 11 database tables.
  ///
  /// Preserves all `fieldTimestampsJson` and `deletedAtUtc` tombstones.
  /// If [password] is provided, encrypts the snapshot using PBKDF2-HMAC-SHA256
  /// derived key in CTR mode with HMAC authentication tag.
  Future<String> createFullBackup({String? password, String? userId}) async {
    final effectiveUserId = userId ?? AppConstants.defaultUserId;

    // 1. Fetch data across all 11 tables inside an atomic transaction for snapshot consistency
    final (
      users,
      categories,
      accounts,
      budgets,
      categoryBudgets,
      savingsGoals,
      recurring,
      transactions,
      settings,
      syncMetadata,
      syncOperations,
    ) = await _db.transaction(() async {
      final u = await (_db.select(
        _db.usersTable,
      )..where((tbl) => tbl.id.equals(effectiveUserId))).get();

      final c = await (_db.select(
        _db.categoriesTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final a = await (_db.select(
        _db.accountsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final b = await (_db.select(
        _db.budgetsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final cb = await (_db.select(
        _db.categoryBudgetsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final sg = await (_db.select(
        _db.savingsGoalsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final r = await (_db.select(
        _db.recurringTransactionsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final t = await (_db.select(
        _db.transactionsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final s = await (_db.select(
        _db.settingsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final sm = await (_db.select(
        _db.syncMetadataTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      final so = await (_db.select(
        _db.syncOperationsTable,
      )..where((tbl) => tbl.userId.equals(effectiveUserId))).get();

      return (u, c, a, b, cb, sg, r, t, s, sm, so);
    });

    // 2. Build serializable maps
    final data = <String, dynamic>{
      'users': users
          .map(
            (u) => {
              'id': u.id,
              'email': u.email,
              'displayName': u.displayName,
              'createdAtUtc': _isoUtc(u.createdAtUtc),
              'lastActiveAtUtc': _isoUtc(u.lastActiveAtUtc),
            },
          )
          .toList(),
      'categories': categories
          .map(
            (c) => {
              'id': c.id,
              'userId': c.userId,
              'name': c.name,
              'type': c.type,
              'iconCodePoint': c.iconCodePoint,
              'colorValue': c.colorValue,
              'isSystem': c.isSystem,
              'isArchived': c.isArchived,
              'createdAtUtc': _isoUtc(c.createdAtUtc),
              'updatedAtUtc': _isoUtc(c.updatedAtUtc),
              'deletedAtUtc': _isoUtc(c.deletedAtUtc),
              'syncStatus': c.syncStatus,
              'fieldTimestampsJson': c.fieldTimestampsJson,
            },
          )
          .toList(),
      'accounts': accounts
          .map(
            (a) => {
              'id': a.id,
              'userId': a.userId,
              'name': a.name,
              'accountType': a.accountType,
              'currency': a.currency,
              'initialBalanceMinor': a.initialBalanceMinor,
              'colorValue': a.colorValue,
              'iconCodePoint': a.iconCodePoint,
              'createdAtUtc': _isoUtc(a.createdAtUtc),
              'updatedAtUtc': _isoUtc(a.updatedAtUtc),
              'deletedAtUtc': _isoUtc(a.deletedAtUtc),
              'syncStatus': a.syncStatus,
              'fieldTimestampsJson': a.fieldTimestampsJson,
            },
          )
          .toList(),
      'budgets': budgets
          .map(
            (b) => {
              'id': b.id,
              'userId': b.userId,
              'monthYear': b.monthYear,
              'amountMinor': b.amountMinor,
              'createdAtUtc': _isoUtc(b.createdAtUtc),
              'updatedAtUtc': _isoUtc(b.updatedAtUtc),
              'deletedAtUtc': _isoUtc(b.deletedAtUtc),
              'syncStatus': b.syncStatus,
              'fieldTimestampsJson': b.fieldTimestampsJson,
            },
          )
          .toList(),
      'categoryBudgets': categoryBudgets
          .map(
            (cb) => {
              'id': cb.id,
              'userId': cb.userId,
              'budgetId': cb.budgetId,
              'categoryId': cb.categoryId,
              'amountMinor': cb.amountMinor,
              'createdAtUtc': _isoUtc(cb.createdAtUtc),
              'updatedAtUtc': _isoUtc(cb.updatedAtUtc),
              'deletedAtUtc': _isoUtc(cb.deletedAtUtc),
              'syncStatus': cb.syncStatus,
              'fieldTimestampsJson': cb.fieldTimestampsJson,
            },
          )
          .toList(),
      'savingsGoals': savingsGoals
          .map(
            (g) => {
              'id': g.id,
              'userId': g.userId,
              'name': g.name,
              'targetAmountMinor': g.targetAmountMinor,
              'currentAmountMinor': g.currentAmountMinor,
              'targetDateUtc': _isoUtc(g.targetDateUtc),
              'iconCodePoint': g.iconCodePoint,
              'colorValue': g.colorValue,
              'createdAtUtc': _isoUtc(g.createdAtUtc),
              'updatedAtUtc': _isoUtc(g.updatedAtUtc),
              'deletedAtUtc': _isoUtc(g.deletedAtUtc),
              'syncStatus': g.syncStatus,
              'fieldTimestampsJson': g.fieldTimestampsJson,
            },
          )
          .toList(),
      'recurringTransactions': recurring
          .map(
            (r) => {
              'id': r.id,
              'userId': r.userId,
              'amountMinor': r.amountMinor,
              'transactionType': r.transactionType,
              'categoryId': r.categoryId,
              'accountId': r.accountId,
              'note': r.note,
              'frequency': r.frequency,
              'startDateUtc': _isoUtc(r.startDateUtc),
              'nextOccurrenceUtc': _isoUtc(r.nextOccurrenceUtc),
              'lastExecutedDateUtc': _isoUtc(r.lastExecutedDateUtc),
              'isActive': r.isActive,
              'createdAtUtc': _isoUtc(r.createdAtUtc),
              'updatedAtUtc': _isoUtc(r.updatedAtUtc),
              'deletedAtUtc': _isoUtc(r.deletedAtUtc),
              'syncStatus': r.syncStatus,
              'fieldTimestampsJson': r.fieldTimestampsJson,
            },
          )
          .toList(),
      'transactions': transactions
          .map(
            (t) => {
              'id': t.id,
              'userId': t.userId,
              'amountMinor': t.amountMinor,
              'transactionType': t.transactionType,
              'categoryId': t.categoryId,
              'accountId': t.accountId,
              'toAccountId': t.toAccountId,
              'note': t.note,
              'transactionDateUtc': _isoUtc(t.transactionDateUtc),
              'transactionTime': t.transactionTime,
              'attachmentPath': t.attachmentPath,
              'isRecurring': t.isRecurring,
              'recurringRuleId': t.recurringRuleId,
              'createdAtUtc': _isoUtc(t.createdAtUtc),
              'updatedAtUtc': _isoUtc(t.updatedAtUtc),
              'deletedAtUtc': _isoUtc(t.deletedAtUtc),
              'syncStatus': t.syncStatus,
              'fieldTimestampsJson': t.fieldTimestampsJson,
            },
          )
          .toList(),
      'settings': settings
          .map(
            (s) => {
              'key': s.key,
              'userId': s.userId,
              'value': s.value,
              'updatedAtUtc': _isoUtc(s.updatedAtUtc),
            },
          )
          .toList(),
      'syncMetadata': syncMetadata
          .map(
            (m) => {
              'id': m.id,
              'userId': m.userId,
              'lastSyncTimestampUtc': _isoUtc(m.lastSyncTimestampUtc),
              'syncCursor': m.syncCursor,
              'updatedAtUtc': _isoUtc(m.updatedAtUtc),
            },
          )
          .toList(),
      'syncOperations': syncOperations
          .map(
            (o) => {
              'id': o.id,
              'userId': o.userId,
              'entityType': o.entityType,
              'entityId': o.entityId,
              'operationType': o.operationType,
              'payloadJson': o.payloadJson,
              'createdAtUtc': _isoUtc(o.createdAtUtc),
              'retryCount': o.retryCount,
              'lastAttemptAtUtc': _isoUtc(o.lastAttemptAtUtc),
              'errorMessage': o.errorMessage,
            },
          )
          .toList(),
    };

    final entityCounts = <String, int>{
      'categories': categories.length,
      'accounts': accounts.length,
      'budgets': budgets.length,
      'categoryBudgets': categoryBudgets.length,
      'savingsGoals': savingsGoals.length,
      'recurringTransactions': recurring.length,
      'transactions': transactions.length,
      'settings': settings.length,
      'syncMetadata': syncMetadata.length,
      'syncOperations': syncOperations.length,
    };

    final nowUtc = DateTime.now().toUtc();

    if (password != null && password.isNotEmpty) {
      // 1. Generate 16 cryptographically secure random bytes for salt
      final saltBytes = HashingService.generateRandomBytes(16);
      final saltHex = _bytesToHex(saltBytes);

      // 2. Derive 256-bit AES key using PBKDF2-HMAC-SHA256 with 100,000 iterations
      const kdfParams = BackupKdfParams(iterations: 100000);
      final pbkdf2 = crypt.Pbkdf2(
        macAlgorithm: crypt.Hmac.sha256(),
        iterations: kdfParams.iterations,
        bits: kdfParams.keyBitsLength,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: saltBytes,
      );

      // 3. Generate 12-byte (96-bit) cryptographically random nonce for AES-GCM
      final aesGcm = crypt.AesGcm.with256bits();
      final nonceBytes = aesGcm.newNonce();
      final nonceHex = _bytesToHex(nonceBytes);

      // 4. Build draft metadata to compute Additional Authenticated Data (AAD)
      final draftMetadata = BackupMetadata(
        formatVersion: kCurrentBackupFormatVersion,
        appVersion: AppConstants.appVersion,
        schemaVersion: AppConstants.databaseSchemaVersion,
        createdAtUtc: nowUtc,
        userId: effectiveUserId,
        databaseId: 'db_${effectiveUserId.hashCode}',
        checksum: '', // Placeholder populated with MAC tag below
        isEncrypted: true,
        encryptionAlgorithm: 'AES-256-GCM',
        kdfParams: kdfParams,
        encryptionSalt: saltHex,
        nonce: nonceHex,
        entityCounts: entityCounts,
      );

      // 5. Compute exact Additional Authenticated Data (AAD) bytes
      final aadBytes = draftMetadata.computeAadBytes();

      // 6. Encrypt canonical JSON representation of database snapshot
      final rawDataBytes = utf8.encode(
        jsonEncode(BackupArchive.canonicalize(data)),
      );
      final secretBox = await aesGcm.encrypt(
        rawDataBytes,
        secretKey: secretKey,
        nonce: nonceBytes,
        aad: aadBytes,
      );

      final macTagHex = _bytesToHex(secretBox.mac.bytes);
      final finalMetadata = BackupMetadata(
        formatVersion: draftMetadata.formatVersion,
        appVersion: draftMetadata.appVersion,
        schemaVersion: draftMetadata.schemaVersion,
        createdAtUtc: draftMetadata.createdAtUtc,
        userId: draftMetadata.userId,
        databaseId: draftMetadata.databaseId,
        checksum: macTagHex,
        isEncrypted: true,
        encryptionAlgorithm: draftMetadata.encryptionAlgorithm,
        kdfParams: draftMetadata.kdfParams,
        encryptionSalt: draftMetadata.encryptionSalt,
        nonce: draftMetadata.nonce,
        entityCounts: draftMetadata.entityCounts,
      );

      final archive = BackupArchive(
        metadata: finalMetadata,
        ciphertext: base64Encode(secretBox.cipherText),
      );

      AppLogger.info(
        'BACKUP_CREATED',
        metadata: {'isEncrypted': true, 'counts': entityCounts},
      );
      return jsonEncode(archive.toJson());
    } else {
      // Unencrypted backup with canonical SHA-256 checksum
      final canonicalStr = jsonEncode(BackupArchive.canonicalize(data));
      final checksum = crypto.sha256
          .convert(utf8.encode(canonicalStr))
          .toString();

      final metadata = BackupMetadata(
        formatVersion: kCurrentBackupFormatVersion,
        appVersion: AppConstants.appVersion,
        schemaVersion: AppConstants.databaseSchemaVersion,
        createdAtUtc: nowUtc,
        userId: effectiveUserId,
        databaseId: 'db_${effectiveUserId.hashCode}',
        checksum: checksum,
        isEncrypted: false,
        entityCounts: entityCounts,
      );

      final archive = BackupArchive(metadata: metadata, data: data);

      AppLogger.info(
        'BACKUP_CREATED',
        metadata: {'isEncrypted': false, 'counts': entityCounts},
      );
      return jsonEncode(archive.toJson());
    }
  }

  /// Transactionally restores a backup into the database.
  ///
  /// If ANY record fails validation or an error occurs during restore,
  /// the database transaction rolls back completely, leaving existing data untouched.
  Future<void> restoreFromBackup(
    String backupJson, {
    String? password,
    required String targetUserId,
    bool allowCrossUserRestore = false,
    bool restoreSyncQueue = false,
  }) async {
    // 1. Parse JSON
    final Map<String, dynamic> rawJson;
    try {
      rawJson = jsonDecode(backupJson) as Map<String, dynamic>;
    } catch (e) {
      throw BackupRestoreException(
        'Corrupted backup file: invalid JSON format ($e).',
      );
    }

    final archive = BackupArchive.fromJson(rawJson);

    // 2. Validate format version
    if (archive.metadata.formatVersion > kCurrentBackupFormatVersion) {
      throw BackupRestoreException(
        'Unsupported backup format version: ${archive.metadata.formatVersion} (current: $kCurrentBackupFormatVersion).',
      );
    }

    // 3. Validate schema version
    if (archive.metadata.schemaVersion > kCurrentSchemaVersion) {
      throw BackupRestoreException(
        'Unsupported database schema version: ${archive.metadata.schemaVersion} (current: $kCurrentSchemaVersion).',
      );
    }

    // 4. Cross-user isolation check
    if (archive.metadata.userId != targetUserId && !allowCrossUserRestore) {
      throw SecurityException(
        'Backup belongs to user "${archive.metadata.userId}", but active user is "$targetUserId". '
        'Cross-user restore rejected to prevent account collision.',
      );
    }

    // 5. Decrypt or verify checksum
    final Map<String, dynamic> data;
    if (archive.metadata.isEncrypted) {
      if (password == null || password.isEmpty) {
        throw const BackupRestoreException(
          'This backup is encrypted. Please provide the decryption password.',
        );
      }
      if (archive.ciphertext == null ||
          archive.metadata.encryptionSalt == null ||
          archive.metadata.nonce == null) {
        throw const BackupRestoreException(
          'Corrupted encrypted backup: missing ciphertext, salt, or nonce.',
        );
      }

      final Uint8List saltBytes;
      final Uint8List nonceBytes;
      final Uint8List ciphertextBytes;
      final Uint8List macBytes;

      try {
        saltBytes = _hexToBytes(archive.metadata.encryptionSalt!);
        nonceBytes = _hexToBytes(archive.metadata.nonce!);
        ciphertextBytes = base64Decode(archive.ciphertext!);
        macBytes = _hexToBytes(archive.metadata.checksum);
      } catch (e) {
        throw BackupRestoreException(
          'Corrupted encrypted backup: malformed encoding ($e).',
        );
      }

      if (ciphertextBytes.isEmpty) {
        throw const BackupRestoreException(
          'Corrupted encrypted backup: ciphertext is empty.',
        );
      }

      final kdfParams = archive.metadata.kdfParams ?? const BackupKdfParams();
      final pbkdf2 = crypt.Pbkdf2(
        macAlgorithm: crypt.Hmac.sha256(),
        iterations: kdfParams.iterations,
        bits: kdfParams.keyBitsLength,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: saltBytes,
      );

      final aadBytes = archive.metadata.computeAadBytes();
      final aesGcm = crypt.AesGcm.with256bits();
      final secretBox = crypt.SecretBox(
        ciphertextBytes,
        nonce: nonceBytes,
        mac: crypt.Mac(macBytes),
      );

      final List<int> decryptedBytes;
      try {
        decryptedBytes = await aesGcm.decrypt(
          secretBox,
          secretKey: secretKey,
          aad: aadBytes,
        );
      } catch (e) {
        throw const BackupRestoreException(
          'Invalid backup password or tampered encrypted archive.',
        );
      }

      try {
        data = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
      } catch (e) {
        throw BackupRestoreException(
          'Decrypted data corrupted: invalid JSON ($e).',
        );
      }
    } else {
      if (archive.data == null) {
        throw const BackupRestoreException(
          'Corrupted backup: missing data payload.',
        );
      }
      if (!archive.verifyChecksum()) {
        throw const BackupRestoreException(
          'Backup checksum verification failed: archive data has been modified or corrupted.',
        );
      }
      data = archive.data!;
    }

    // 6. Pre-validate business rules & domain constraints
    final rawTransactions = (data['transactions'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rawAccounts = (data['accounts'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rawCategories = (data['categories'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rawBudgets = (data['budgets'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rawCategoryBudgets = (data['categoryBudgets'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rawRecurring = (data['recurringTransactions'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final rawSavingsGoals = (data['savingsGoals'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final accountIds = rawAccounts.map((a) => a['id'] as String).toSet();
    final categoryIds = rawCategories.map((c) => c['id'] as String).toSet();
    final budgetIds = rawBudgets.map((b) => b['id'] as String).toSet();

    _checkUniqueIds(rawAccounts, 'accounts');
    _checkUniqueIds(rawCategories, 'categories');
    _checkUniqueIds(rawBudgets, 'budgets');
    _checkUniqueIds(rawCategoryBudgets, 'categoryBudgets');
    _checkUniqueIds(rawSavingsGoals, 'savingsGoals');
    _checkUniqueIds(rawRecurring, 'recurringTransactions');
    _checkUniqueIds(rawTransactions, 'transactions');

    const validAccountTypes = {
      'cash',
      'bank',
      'creditCard',
      'wallet',
      'savings',
    };
    for (final acc in rawAccounts) {
      final accType = acc['accountType'] as String?;
      if (accType == null || !validAccountTypes.contains(accType)) {
        throw ValidationException(
          'Invalid account type "$accType" for account ID ${acc['id']}.',
        );
      }
      _parseUtcTimestamp(acc['createdAtUtc'], 'createdAtUtc', acc['id']);
      _parseUtcTimestamp(acc['updatedAtUtc'], 'updatedAtUtc', acc['id']);
      if (acc['deletedAtUtc'] != null) {
        _parseUtcTimestamp(acc['deletedAtUtc'], 'deletedAtUtc', acc['id']);
      }
      _validateFieldTimestampsJson(acc['fieldTimestampsJson'], acc['id']);
    }

    const validCategoryTypes = {'income', 'expense'};
    for (final cat in rawCategories) {
      final catType = cat['type'] as String?;
      if (catType == null || !validCategoryTypes.contains(catType)) {
        throw ValidationException(
          'Invalid category type "$catType" for category ID ${cat['id']}.',
        );
      }
      _parseUtcTimestamp(cat['createdAtUtc'], 'createdAtUtc', cat['id']);
      _parseUtcTimestamp(cat['updatedAtUtc'], 'updatedAtUtc', cat['id']);
      if (cat['deletedAtUtc'] != null) {
        _parseUtcTimestamp(cat['deletedAtUtc'], 'deletedAtUtc', cat['id']);
      }
      _validateFieldTimestampsJson(cat['fieldTimestampsJson'], cat['id']);
    }

    for (final b in rawBudgets) {
      final amount = b['amountMinor'] as int?;
      if (amount == null || amount <= 0) {
        throw ValidationException(
          'Invalid budget amount: $amount for ID ${b['id']}.',
        );
      }
      _parseUtcTimestamp(b['createdAtUtc'], 'createdAtUtc', b['id']);
      _parseUtcTimestamp(b['updatedAtUtc'], 'updatedAtUtc', b['id']);
      if (b['deletedAtUtc'] != null) {
        _parseUtcTimestamp(b['deletedAtUtc'], 'deletedAtUtc', b['id']);
      }
      _validateFieldTimestampsJson(b['fieldTimestampsJson'], b['id']);
    }

    // Validate category budgets
    for (final cb in rawCategoryBudgets) {
      final amount = cb['amountMinor'] as int?;
      if (amount == null || amount <= 0) {
        throw ValidationException(
          'Invalid category budget amount: $amount for ID ${cb['id']}.',
        );
      }
      final bId = cb['budgetId'] as String?;
      if (bId == null || !budgetIds.contains(bId)) {
        throw ValidationException(
          'Category budget references non-existent budget "$bId".',
        );
      }
      final cId = cb['categoryId'] as String?;
      if (cId == null || !categoryIds.contains(cId)) {
        throw ValidationException(
          'Category budget references non-existent category "$cId".',
        );
      }
      _parseUtcTimestamp(cb['createdAtUtc'], 'createdAtUtc', cb['id']);
      _parseUtcTimestamp(cb['updatedAtUtc'], 'updatedAtUtc', cb['id']);
      if (cb['deletedAtUtc'] != null) {
        _parseUtcTimestamp(cb['deletedAtUtc'], 'deletedAtUtc', cb['id']);
      }
      _validateFieldTimestampsJson(cb['fieldTimestampsJson'], cb['id']);
    }

    // Validate recurring transactions
    const validRecurringFrequencies = {'daily', 'weekly', 'monthly', 'yearly'};
    for (final rt in rawRecurring) {
      final amount = rt['amountMinor'] as int?;
      if (amount == null || amount <= 0) {
        throw ValidationException(
          'Invalid recurring amount: $amount for ID ${rt['id']}.',
        );
      }
      final freq = rt['frequency'] as String?;
      if (freq == null || !validRecurringFrequencies.contains(freq)) {
        throw ValidationException(
          'Invalid recurring frequency "$freq" for recurring ID ${rt['id']}.',
        );
      }
      final rType = rt['transactionType'] as String?;
      if (rType == null || !validCategoryTypes.contains(rType)) {
        throw ValidationException(
          'Invalid recurring transactionType "$rType" for recurring ID ${rt['id']}.',
        );
      }
      final accId = rt['accountId'] as String?;
      if (accId == null || !accountIds.contains(accId)) {
        throw ValidationException(
          'Recurring transaction references non-existent account "$accId".',
        );
      }
      final catId = rt['categoryId'] as String?;
      if (catId == null || !categoryIds.contains(catId)) {
        throw ValidationException(
          'Recurring transaction references non-existent category "$catId".',
        );
      }
      _parseUtcTimestamp(rt['createdAtUtc'], 'createdAtUtc', rt['id']);
      _parseUtcTimestamp(rt['updatedAtUtc'], 'updatedAtUtc', rt['id']);
      _parseUtcTimestamp(rt['startDateUtc'], 'startDateUtc', rt['id']);
      _parseUtcTimestamp(
        rt['nextOccurrenceUtc'],
        'nextOccurrenceUtc',
        rt['id'],
      );
      if (rt['lastExecutedDateUtc'] != null) {
        _parseUtcTimestamp(
          rt['lastExecutedDateUtc'],
          'lastExecutedDateUtc',
          rt['id'],
        );
      }
      if (rt['deletedAtUtc'] != null) {
        _parseUtcTimestamp(rt['deletedAtUtc'], 'deletedAtUtc', rt['id']);
      }
      _validateFieldTimestampsJson(rt['fieldTimestampsJson'], rt['id']);
    }

    // Validate savings goals
    for (final g in rawSavingsGoals) {
      final target = g['targetAmountMinor'] as int?;
      if (target == null || target <= 0) {
        throw ValidationException(
          'Invalid savings goal target: $target for ID ${g['id']}.',
        );
      }
      _parseUtcTimestamp(g['createdAtUtc'], 'createdAtUtc', g['id']);
      _parseUtcTimestamp(g['updatedAtUtc'], 'updatedAtUtc', g['id']);
      _parseUtcTimestamp(g['targetDateUtc'], 'targetDateUtc', g['id']);
      if (g['deletedAtUtc'] != null) {
        _parseUtcTimestamp(g['deletedAtUtc'], 'deletedAtUtc', g['id']);
      }
      _validateFieldTimestampsJson(g['fieldTimestampsJson'], g['id']);
    }

    // Validate transactions
    for (final tx in rawTransactions) {
      final amountMinor = tx['amountMinor'] as int?;
      if (amountMinor == null || amountMinor <= 0) {
        throw ValidationException(
          'Invalid transaction amount: $amountMinor for ID ${tx['id']}. Amounts must be strictly positive minor units.',
        );
      }

      final type = tx['transactionType'] as String?;
      if (type == null || !['income', 'expense', 'transfer'].contains(type)) {
        throw ValidationException(
          'Invalid transaction type "$type" for transaction ID ${tx['id']}.',
        );
      }

      final accId = tx['accountId'] as String?;
      if (accId == null || !accountIds.contains(accId)) {
        throw ValidationException(
          'Foreign key violation: Account ID "$accId" referenced by transaction ${tx['id']} does not exist in backup accounts.',
        );
      }

      final catId = tx['categoryId'] as String?;
      if (catId == null || !categoryIds.contains(catId)) {
        throw ValidationException(
          'Foreign key violation: Category ID "$catId" referenced by transaction ${tx['id']} does not exist in backup categories.',
        );
      }

      if (type == 'transfer') {
        final toAccId = tx['toAccountId'] as String?;
        if (toAccId != null && !accountIds.contains(toAccId)) {
          throw ValidationException(
            'Foreign key violation: Transfer destination account "$toAccId" does not exist in backup accounts.',
          );
        }
      }
      _parseUtcTimestamp(tx['createdAtUtc'], 'createdAtUtc', tx['id']);
      _parseUtcTimestamp(tx['updatedAtUtc'], 'updatedAtUtc', tx['id']);
      _parseUtcTimestamp(
        tx['transactionDateUtc'],
        'transactionDateUtc',
        tx['id'],
      );
      if (tx['deletedAtUtc'] != null) {
        _parseUtcTimestamp(tx['deletedAtUtc'], 'deletedAtUtc', tx['id']);
      }
      _validateFieldTimestampsJson(tx['fieldTimestampsJson'], tx['id']);
    }

    if (restoreSyncQueue) {
      final rawOps = (data['syncOperations'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      _checkUniqueIds(rawOps, 'syncOperations');
      const validSyncOpTypes = {'create', 'update', 'delete'};
      for (final op in rawOps) {
        final opType = op['operationType'] as String?;
        if (opType == null || !validSyncOpTypes.contains(opType)) {
          throw ValidationException(
            'Invalid sync operation type "$opType" for operation ${op['id']}.',
          );
        }
        final payload = op['payloadJson'] as String?;
        if (payload != null) {
          try {
            jsonDecode(payload);
          } catch (e) {
            throw ValidationException(
              'Malformed sync operation payloadJson for operation ${op['id']}: invalid JSON ($e).',
            );
          }
        }
        _parseUtcTimestamp(
          op['createdAtUtc'],
          'createdAtUtc',
          op['id'] ?? 'unknown_sync_op',
        );
        if (op['lastAttemptAtUtc'] != null) {
          _parseUtcTimestamp(
            op['lastAttemptAtUtc'],
            'lastAttemptAtUtc',
            op['id'] ?? 'unknown_sync_op',
          );
        }
      }
    }

    // 7. Atomic SQLite Transaction: Rollback completely on ANY error
    await _db.transaction(() async {
      // A. Delete existing data for targetUserId in reverse FK order
      await (_db.delete(
        _db.transactionsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.recurringTransactionsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.categoryBudgetsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.budgetsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.savingsGoalsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.accountsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(_db.categoriesTable)..where(
            (t) => t.userId.equals(targetUserId) & t.isSystem.equals(false),
          ))
          .go();
      await (_db.delete(
        _db.settingsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.syncOperationsTable,
      )..where((t) => t.userId.equals(targetUserId))).go();
      await (_db.delete(
        _db.syncMetadataTable,
      )..where((t) => t.userId.equals(targetUserId))).go();

      // B. Insert categories (preserve system categories or insert custom)
      for (final cat in rawCategories) {
        await _db
            .into(_db.categoriesTable)
            .insertOnConflictUpdate(
              CategoriesTableCompanion(
                id: Value(cat['id'] as String),
                userId: Value(targetUserId),
                name: Value(cat['name'] as String),
                type: Value(cat['type'] as String),
                iconCodePoint: Value(cat['iconCodePoint'] as int),
                colorValue: Value(cat['colorValue'] as int),
                isSystem: Value(cat['isSystem'] as bool? ?? false),
                isArchived: Value(cat['isArchived'] as bool? ?? false),
                createdAtUtc: Value(
                  DateTime.parse(cat['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(cat['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  cat['deletedAtUtc'] != null
                      ? DateTime.parse(cat['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (cat['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  cat['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // C. Insert accounts
      for (final acc in rawAccounts) {
        await _db
            .into(_db.accountsTable)
            .insertOnConflictUpdate(
              AccountsTableCompanion(
                id: Value(acc['id'] as String),
                userId: Value(targetUserId),
                name: Value(acc['name'] as String),
                accountType: Value(acc['accountType'] as String),
                currency: Value(acc['currency'] as String? ?? 'INR'),
                initialBalanceMinor: Value(
                  acc['initialBalanceMinor'] as int? ?? 0,
                ),
                colorValue: Value(acc['colorValue'] as int? ?? 0xFF14B8A6),
                iconCodePoint: Value(acc['iconCodePoint'] as int? ?? 0xe040),
                createdAtUtc: Value(
                  DateTime.parse(acc['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(acc['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  acc['deletedAtUtc'] != null
                      ? DateTime.parse(acc['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (acc['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  acc['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // D. Insert budgets
      for (final b in rawBudgets) {
        await _db
            .into(_db.budgetsTable)
            .insertOnConflictUpdate(
              BudgetsTableCompanion(
                id: Value(b['id'] as String),
                userId: Value(targetUserId),
                monthYear: Value(b['monthYear'] as String),
                amountMinor: Value(b['amountMinor'] as int),
                createdAtUtc: Value(
                  DateTime.parse(b['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(b['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  b['deletedAtUtc'] != null
                      ? DateTime.parse(b['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (b['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  b['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // E. Insert category budgets
      for (final cb in rawCategoryBudgets) {
        await _db
            .into(_db.categoryBudgetsTable)
            .insertOnConflictUpdate(
              CategoryBudgetsTableCompanion(
                id: Value(cb['id'] as String),
                userId: Value(targetUserId),
                budgetId: Value(cb['budgetId'] as String),
                categoryId: Value(cb['categoryId'] as String),
                amountMinor: Value(cb['amountMinor'] as int),
                createdAtUtc: Value(
                  DateTime.parse(cb['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(cb['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  cb['deletedAtUtc'] != null
                      ? DateTime.parse(cb['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (cb['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  cb['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // F. Insert savings goals
      for (final g in rawSavingsGoals) {
        await _db
            .into(_db.savingsGoalsTable)
            .insertOnConflictUpdate(
              SavingsGoalsTableCompanion(
                id: Value(g['id'] as String),
                userId: Value(targetUserId),
                name: Value(g['name'] as String),
                targetAmountMinor: Value(g['targetAmountMinor'] as int),
                currentAmountMinor: Value(g['currentAmountMinor'] as int? ?? 0),
                targetDateUtc: Value(
                  DateTime.parse(g['targetDateUtc'] as String).toUtc(),
                ),
                iconCodePoint: Value(g['iconCodePoint'] as int? ?? 0xe66c),
                colorValue: Value(g['colorValue'] as int? ?? 0xFF10B981),
                createdAtUtc: Value(
                  DateTime.parse(g['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(g['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  g['deletedAtUtc'] != null
                      ? DateTime.parse(g['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (g['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  g['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // G. Insert recurring transactions
      for (final rt in rawRecurring) {
        await _db
            .into(_db.recurringTransactionsTable)
            .insertOnConflictUpdate(
              RecurringTransactionsTableCompanion(
                id: Value(rt['id'] as String),
                userId: Value(targetUserId),
                amountMinor: Value(rt['amountMinor'] as int),
                transactionType: Value(rt['transactionType'] as String),
                categoryId: Value(rt['categoryId'] as String),
                accountId: Value(rt['accountId'] as String),
                note: Value(rt['note'] as String? ?? ''),
                frequency: Value(rt['frequency'] as String),
                startDateUtc: Value(
                  DateTime.parse(rt['startDateUtc'] as String).toUtc(),
                ),
                nextOccurrenceUtc: Value(
                  DateTime.parse(rt['nextOccurrenceUtc'] as String).toUtc(),
                ),
                lastExecutedDateUtc: Value(
                  rt['lastExecutedDateUtc'] != null
                      ? DateTime.parse(
                          rt['lastExecutedDateUtc'] as String,
                        ).toUtc()
                      : null,
                ),
                isActive: Value(rt['isActive'] as bool? ?? true),
                createdAtUtc: Value(
                  DateTime.parse(rt['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(rt['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  rt['deletedAtUtc'] != null
                      ? DateTime.parse(rt['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (rt['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  rt['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // H. Insert transactions (preserving exact timestamps, field timestamps, and tombstones)
      for (final t in rawTransactions) {
        await _db
            .into(_db.transactionsTable)
            .insertOnConflictUpdate(
              TransactionsTableCompanion(
                id: Value(t['id'] as String),
                userId: Value(targetUserId),
                amountMinor: Value(t['amountMinor'] as int),
                transactionType: Value(t['transactionType'] as String),
                categoryId: Value(t['categoryId'] as String),
                accountId: Value(t['accountId'] as String),
                toAccountId: Value(t['toAccountId'] as String?),
                note: Value(t['note'] as String? ?? ''),
                transactionDateUtc: Value(
                  DateTime.parse(t['transactionDateUtc'] as String).toUtc(),
                ),
                transactionTime: Value(t['transactionTime'] as String?),
                attachmentPath: Value(t['attachmentPath'] as String?),
                isRecurring: Value(t['isRecurring'] as bool? ?? false),
                recurringRuleId: Value(t['recurringRuleId'] as String?),
                createdAtUtc: Value(
                  DateTime.parse(t['createdAtUtc'] as String).toUtc(),
                ),
                updatedAtUtc: Value(
                  DateTime.parse(t['updatedAtUtc'] as String).toUtc(),
                ),
                deletedAtUtc: Value(
                  t['deletedAtUtc'] != null
                      ? DateTime.parse(t['deletedAtUtc'] as String).toUtc()
                      : null,
                ),
                syncStatus: Value(
                  restoreSyncQueue
                      ? (t['syncStatus'] as String? ?? 'synced')
                      : 'synced',
                ),
                fieldTimestampsJson: Value(
                  t['fieldTimestampsJson'] as String? ?? '{}',
                ),
              ),
            );
      }

      // I. Insert settings
      final rawSettings = (data['settings'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      for (final s in rawSettings) {
        await _db
            .into(_db.settingsTable)
            .insertOnConflictUpdate(
              SettingsTableCompanion(
                key: Value(s['key'] as String),
                userId: Value(targetUserId),
                value: Value(s['value'] as String),
                updatedAtUtc: Value(
                  DateTime.parse(s['updatedAtUtc'] as String).toUtc(),
                ),
              ),
            );
      }

      // J. Reconcile Sync Metadata & Cursors
      // Restoring the backup's sync cursors ensures that subsequent pull requests
      // fetch all remote changes that happened AFTER the backup snapshot was taken.
      final rawMeta = (data['syncMetadata'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      for (final m in rawMeta) {
        await _db
            .into(_db.syncMetadataTable)
            .insertOnConflictUpdate(
              SyncMetadataTableCompanion(
                id: Value(m['id'] as String),
                userId: Value(targetUserId),
                lastSyncTimestampUtc: Value(
                  m['lastSyncTimestampUtc'] != null
                      ? DateTime.parse(
                          m['lastSyncTimestampUtc'] as String,
                        ).toUtc()
                      : null,
                ),
                syncCursor: Value(m['syncCursor'] as String?),
                updatedAtUtc: Value(
                  DateTime.parse(m['updatedAtUtc'] as String).toUtc(),
                ),
              ),
            );
      }

      // K. Reconcile Sync Operations Queue
      // If restoreSyncQueue is true, restored pending operations are inserted;
      // otherwise, pending operations are cleared so stale operations don't collide.
      if (restoreSyncQueue) {
        final rawOps = (data['syncOperations'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        for (final o in rawOps) {
          await _db
              .into(_db.syncOperationsTable)
              .insertOnConflictUpdate(
                SyncOperationsTableCompanion(
                  id: Value(o['id'] as String),
                  userId: Value(targetUserId),
                  entityType: Value(o['entityType'] as String),
                  entityId: Value(o['entityId'] as String),
                  operationType: Value(o['operationType'] as String),
                  payloadJson: Value(o['payloadJson'] as String),
                  createdAtUtc: Value(
                    DateTime.parse(o['createdAtUtc'] as String).toUtc(),
                  ),
                  retryCount: Value(o['retryCount'] as int? ?? 0),
                  lastAttemptAtUtc: Value(
                    o['lastAttemptAtUtc'] != null
                        ? DateTime.parse(
                            o['lastAttemptAtUtc'] as String,
                          ).toUtc()
                        : null,
                  ),
                  errorMessage: Value(o['errorMessage'] as String?),
                ),
              );
        }
      }
    });

    AppLogger.info(
      'BACKUP_RESTORE_SUCCESS',
      metadata: archive.metadata.entityCounts,
    );
  }
}
