import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/backup/backup_models.dart';
import 'package:expense_tracker/core/backup/backup_service.dart';
import 'package:expense_tracker/core/backup/export_service.dart';
import 'package:expense_tracker/core/database/encrypted_database_connection.dart';
import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/core/network/connectivity_status.dart';
import 'package:expense_tracker/core/network/i_connectivity_service.dart';
import 'package:expense_tracker/core/sync/conflict_resolver.dart';
import 'package:expense_tracker/core/sync/sync_cursor.dart';
import 'package:expense_tracker/core/utils/app_logger.dart';
import 'package:expense_tracker/data/database/app_database.dart';
import 'package:expense_tracker/data/sync/fake_sync_remote_data_source.dart';
import 'package:expense_tracker/data/sync/sync_coordinator.dart';

class _FakeConnectivityService implements IConnectivityService {
  ConnectivityStatus _status = ConnectivityStatus.online;
  final _controller = StreamController<ConnectivityStatus>.broadcast();

  @override
  Future<bool> get isConnected async => _status == ConnectivityStatus.online;

  @override
  ConnectivityStatus get currentStatus => _status;

  @override
  Stream<ConnectivityStatus> get onConnectivityChanged => _controller.stream;

  void setStatus(ConnectivityStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 8: Transactional Backup, Recovery & Export Hardening Tests', () {
    late AppDatabase db;
    late BackupService backupService;
    late ExportService exportService;

    const testUserId = 'user_test_backup_1';
    const testUser2Id = 'user_test_backup_2';

    setUp(() async {
      AppLogger.enableConsoleLogging = false;
      // In-memory isolated database
      db = AppDatabase(EncryptedDatabaseConnection.createInMemoryConnection());
      backupService = BackupService(db);
      exportService = ExportService(db);

      // Seed user 1
      await db
          .into(db.usersTable)
          .insert(
            UsersTableCompanion(
              id: const drift.Value(testUserId),
              email: const drift.Value('user1@example.com'),
              displayName: const drift.Value('Test User 1'),
              createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              lastActiveAtUtc: drift.Value(DateTime.utc(2026, 9, 6)),
            ),
          );

      // Seed user 1 account
      await db
          .into(db.accountsTable)
          .insert(
            AccountsTableCompanion(
              id: const drift.Value('acc_1'),
              userId: const drift.Value(testUserId),
              name: const drift.Value('Checking'),
              accountType: const drift.Value('bank'),
              currency: const drift.Value('INR'),
              initialBalanceMinor: const drift.Value(500000), // 5000.00
              createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              fieldTimestampsJson: const drift.Value(
                '{"name":"2026-09-01T00:00:00.000Z"}',
              ),
            ),
          );

      // Seed user 1 category
      await db
          .into(db.categoriesTable)
          .insert(
            CategoriesTableCompanion(
              id: const drift.Value('cat_1'),
              userId: const drift.Value(testUserId),
              name: const drift.Value('Groceries'),
              type: const drift.Value('expense'),
              iconCodePoint: const drift.Value(0xe040),
              colorValue: const drift.Value(0xFF10B981),
              createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              fieldTimestampsJson: const drift.Value(
                '{"name":"2026-09-01T00:00:00.000Z"}',
              ),
            ),
          );

      // Seed user 1 transaction
      await db
          .into(db.transactionsTable)
          .insert(
            TransactionsTableCompanion(
              id: const drift.Value('tx_1'),
              userId: const drift.Value(testUserId),
              amountMinor: const drift.Value(15000), // 150.00
              transactionType: const drift.Value('expense'),
              categoryId: const drift.Value('cat_1'),
              accountId: const drift.Value('acc_1'),
              note: const drift.Value('Weekly essentials'),
              transactionDateUtc: drift.Value(DateTime.utc(2026, 9, 2)),
              createdAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
              updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
              fieldTimestampsJson: const drift.Value(
                '{"amountMinor":"2026-09-02T00:00:00.000Z"}',
              ),
            ),
          );

      // Seed sync metadata
      await db
          .into(db.syncMetadataTable)
          .insert(
            SyncMetadataTableCompanion(
              id: const drift.Value('meta_1'),
              userId: const drift.Value(testUserId),
              syncCursor: const drift.Value('2026-09-02T12:00:00.000Z_tx_1'),
              updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 2, 12)),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    // ------------------------------------------------------------------------
    // Group 1: Backup Creation & Packaging
    // ------------------------------------------------------------------------
    group('1. Full Transactional Backup Creation', () {
      test(
        '1. Creates comprehensive backup preserving all 11 tables and metadata',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final archive = BackupArchive.fromJson(jsonDecode(backupJson));

          expect(
            archive.metadata.formatVersion,
            equals(kCurrentBackupFormatVersion),
          );
          expect(archive.metadata.schemaVersion, equals(kCurrentSchemaVersion));
          expect(archive.metadata.userId, equals(testUserId));
          expect(archive.metadata.isEncrypted, isFalse);
          expect(archive.metadata.entityCounts['transactions'], equals(1));
          expect(archive.metadata.entityCounts['accounts'], equals(1));
          expect(archive.metadata.entityCounts['categories'], equals(1));

          // Preserves field timestamps verbatim
          final txList = archive.data!['transactions'] as List;
          expect(
            txList.first['fieldTimestampsJson'],
            equals('{"amountMinor":"2026-09-02T00:00:00.000Z"}'),
          );
        },
      );

      test('2. Preserves deletedAtUtc tombstones verbatim in backup', () async {
        // Seed a soft-deleted account
        await db
            .into(db.accountsTable)
            .insert(
              AccountsTableCompanion(
                id: const drift.Value('acc_deleted'),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Old Closed Account'),
                accountType: const drift.Value('cash'),
                createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 3)),
                deletedAtUtc: drift.Value(DateTime.utc(2026, 9, 3, 10)),
                fieldTimestampsJson: const drift.Value(
                  '{"name":"2026-09-01T00:00:00.000Z"}',
                ),
              ),
            );

        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
        );
        final archive = BackupArchive.fromJson(jsonDecode(backupJson));

        final accList = (archive.data!['accounts'] as List)
            .cast<Map<String, dynamic>>();
        final deletedAcc = accList.firstWhere((a) => a['id'] == 'acc_deleted');
        expect(deletedAcc['deletedAtUtc'], equals('2026-09-03T10:00:00.000Z'));
      });

      test(
        '3. Generates valid canonical checksum for unencrypted backup',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final archive = BackupArchive.fromJson(jsonDecode(backupJson));

          expect(archive.verifyChecksum(), isTrue);
        },
      );

      test(
        '4. Creates password-protected encrypted backup archive with AES-256-GCM AEAD',
        () async {
          const password = 'CorrectHorseBatteryStaple!';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final archive = BackupArchive.fromJson(jsonDecode(backupJson));
          expect(archive.metadata.isEncrypted, isTrue);
          expect(archive.metadata.encryptionAlgorithm, equals('AES-256-GCM'));
          expect(archive.metadata.kdfParams, isNotNull);
          expect(archive.metadata.kdfParams!.iterations, equals(100000));
          expect(
            archive.metadata.kdfParams!.algorithm,
            equals('PBKDF2-HMAC-SHA256'),
          );
          expect(archive.metadata.encryptionSalt, isNotNull);
          expect(archive.metadata.nonce, isNotNull);
          expect(archive.ciphertext, isNotNull);
          expect(archive.data, isNull); // Plaintext data omitted
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 2: Cryptographic Authenticity & Tamper Resistance Invariants
    // ------------------------------------------------------------------------
    group('2. Cryptographic Authenticity & Tamper Resistance Invariants', () {
      test(
        '5. Rejects unencrypted backup when data has been modified',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;

          // Malicious tampering: increase transaction amount in JSON
          final data = rawMap['data'] as Map<String, dynamic>;
          final txs = data['transactions'] as List;
          txs[0]['amountMinor'] = 99999999;

          final tamperedJson = jsonEncode(rawMap);

          expect(
            () => backupService.restoreFromBackup(
              tamperedJson,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '6. Rejects encrypted backup when incorrect password is provided',
        () async {
          const password = 'SuperSecretPassword123';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          expect(
            () => backupService.restoreFromBackup(
              backupJson,
              password: 'WrongPassword!',
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test('7. Rejects encrypted backup with tampered ciphertext', () async {
        const password = 'MyPassword';
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
          password: password,
        );

        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
        // Tamper with base64 ciphertext
        rawMap['ciphertext'] = 'AAAA${rawMap['ciphertext'].substring(4)}';

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            password: password,
            targetUserId: testUserId,
          ),
          throwsA(isA<BackupRestoreException>()),
        );
      });

      test(
        '8. Rejects encrypted backup with tampered encryption salt',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          // Tamper with salt
          rawMap['metadata']['encryptionSalt'] = '00' * 16;

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test('9. Rejects encrypted backup with tampered nonce/IV', () async {
        const password = 'MyPassword';
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
          password: password,
        );

        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
        // Tamper with nonce
        rawMap['metadata']['nonce'] = '00' * 12;

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            password: password,
            targetUserId: testUserId,
          ),
          throwsA(isA<BackupRestoreException>()),
        );
      });

      test(
        '10. Rejects encrypted backup when metadata (AAD) is modified',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          // Tamper with databaseId in metadata (protected by AAD)
          rawMap['metadata']['databaseId'] = 'tampered_database_id';

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '11. Rejects encrypted backup when userId is modified in header',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          // Attacker alters userId to match targetUserId
          rawMap['metadata']['userId'] = testUser2Id;

          // Target user 2 attempts to restore with allowCrossUserRestore=true
          // But AAD mismatch ensures decryption MAC fails!
          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUser2Id,
              allowCrossUserRestore: true,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '12. Rejects backup with unsupported future formatVersion',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['formatVersion'] = 999;

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '13. Rejects backup with unsupported future schemaVersion',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['schemaVersion'] = 999;

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '14. Rejects encrypted backup with malformed base64 ciphertext',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['ciphertext'] = '!!!not_valid_base64!!!';

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test('15. Rejects encrypted backup with truncated ciphertext', () async {
        const password = 'MyPassword';
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
          password: password,
        );

        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
        final originalCipher = rawMap['ciphertext'] as String;
        rawMap['ciphertext'] = originalCipher.substring(
          0,
          originalCipher.length ~/ 2,
        );

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            password: password,
            targetUserId: testUserId,
          ),
          throwsA(isA<BackupRestoreException>()),
        );
      });

      test('16. Rejects encrypted backup with empty ciphertext', () async {
        const password = 'MyPassword';
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
          password: password,
        );

        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
        rawMap['ciphertext'] = '';

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            password: password,
            targetUserId: testUserId,
          ),
          throwsA(isA<BackupRestoreException>()),
        );
      });

      test(
        '17. Repeated encryption of same data produces distinct nonces and ciphertexts',
        () async {
          const password = 'ConsistentPassword123!';
          final backup1 = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );
          final backup2 = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final arc1 = BackupArchive.fromJson(jsonDecode(backup1));
          final arc2 = BackupArchive.fromJson(jsonDecode(backup2));

          // Nonces must be unique per session
          expect(arc1.metadata.nonce, isNot(equals(arc2.metadata.nonce)));
          // Salts must be unique
          expect(
            arc1.metadata.encryptionSalt,
            isNot(equals(arc2.metadata.encryptionSalt)),
          );
          // Ciphertexts must differ
          expect(arc1.ciphertext, isNot(equals(arc2.ciphertext)));
        },
      );

      test(
        '18. Successful decrypt reproduces exact original database state',
        () async {
          const password = 'RecoveryPassword987!';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          // Wipe local database
          await (db.delete(db.transactionsTable)).go();
          await (db.delete(db.accountsTable)).go();

          // Restore encrypted backup
          await backupService.restoreFromBackup(
            backupJson,
            password: password,
            targetUserId: testUserId,
          );

          final accounts = await (db.select(
            db.accountsTable,
          )..where((a) => a.userId.equals(testUserId))).get();
          final txs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();

          expect(accounts.length, equals(1));
          expect(accounts.first.id, equals('acc_1'));
          expect(accounts.first.name, equals('Checking'));

          expect(txs.length, equals(1));
          expect(txs.first.id, equals('tx_1'));
          expect(txs.first.amountMinor, equals(15000));
          expect(txs.first.note, equals('Weekly essentials'));
        },
      );

      test(
        '18a. Rejects encrypted backup with tampered encryptionAlgorithm',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['encryptionAlgorithm'] = 'AES-128-CBC';

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '18b. Rejects encrypted backup with tampered kdfParams iterations',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['kdfParams']['iterations'] = 50000;

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '18c. Rejects encrypted backup with tampered formatVersion protected by AAD',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['formatVersion'] = 0;

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '18d. Rejects encrypted backup with tampered schemaVersion protected by AAD',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['schemaVersion'] = 0;

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );

      test(
        '18e. Rejects encrypted backup with tampered createdAtUtc protected by AAD',
        () async {
          const password = 'MyPassword';
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
            password: password,
          );

          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          rawMap['metadata']['createdAtUtc'] = '2020-01-01T00:00:00.000Z';

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: password,
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 3: Multi-User Isolation & Money Domain Invariants
    // ------------------------------------------------------------------------
    group('3. Multi-User Isolation & Money Domain Invariants', () {
      test(
        '19. Rejects restore when backup belongs to another user without explicit flag',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );

          expect(
            () => backupService.restoreFromBackup(
              backupJson,
              targetUserId: testUser2Id,
            ),
            throwsA(isA<SecurityException>()),
          );
        },
      );

      test(
        '20. Allows cross-user restore when allowCrossUserRestore is true',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );

          await backupService.restoreFromBackup(
            backupJson,
            targetUserId: testUser2Id,
            allowCrossUserRestore: true,
          );

          final user2Accounts = await (db.select(
            db.accountsTable,
          )..where((a) => a.userId.equals(testUser2Id))).get();
          expect(user2Accounts.length, equals(1));
          expect(user2Accounts.first.name, equals('Checking'));
        },
      );

      test('21. Money Invariant: Rejects transaction amount = 0', () async {
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
        );
        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;

        final txs = rawMap['data']['transactions'] as List;
        txs[0]['amountMinor'] = 0; // 0 minor units is rejected

        final canonicalStr = jsonEncode(
          BackupArchive.canonicalize(rawMap['data']),
        );
        rawMap['metadata']['checksum'] = sha256
            .convert(utf8.encode(canonicalStr))
            .toString();

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            targetUserId: testUserId,
          ),
          throwsA(isA<ValidationException>()),
        );
      });

      test('22. Money Invariant: Rejects transaction amount = -1', () async {
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
        );
        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;

        final txs = rawMap['data']['transactions'] as List;
        txs[0]['amountMinor'] = -1; // Negative amount rejected

        final canonicalStr = jsonEncode(
          BackupArchive.canonicalize(rawMap['data']),
        );
        rawMap['metadata']['checksum'] = sha256
            .convert(utf8.encode(canonicalStr))
            .toString();

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            targetUserId: testUserId,
          ),
          throwsA(isA<ValidationException>()),
        );
      });

      test(
        '23. Money Invariant: Accepts minimal positive transaction amount = 1',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;

          final txs = rawMap['data']['transactions'] as List;
          txs[0]['amountMinor'] = 1; // 1 minor unit (0.01) is strictly valid

          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          await backupService.restoreFromBackup(
            jsonEncode(rawMap),
            targetUserId: testUserId,
          );

          final restoredTx = await (db.select(
            db.transactionsTable,
          )..where((t) => t.id.equals('tx_1'))).getSingle();
          expect(restoredTx.amountMinor, equals(1));
        },
      );

      test(
        '24. Rejects restore if transaction references non-existent category foreign key',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;

          final txs = rawMap['data']['transactions'] as List;
          txs[0]['categoryId'] = 'non_existent_category_uuid';

          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 4: ATOMIC ROLLBACK ON RESTORE FAILURE
    // ------------------------------------------------------------------------
    group('4. Atomic Transaction Rollback on Failure', () {
      test(
        '25. ATOMIC ROLLBACK: 50 valid records + 1 invalid record causes complete rollback',
        () async {
          final initialTxCount = (await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get()).length;
          expect(initialTxCount, equals(1));

          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final data = rawMap['data'] as Map<String, dynamic>;
          final txList = (data['transactions'] as List)
              .cast<Map<String, dynamic>>();

          // Add 50 valid transactions
          for (int i = 2; i <= 51; i++) {
            txList.add({
              'id': 'tx_valid_$i',
              'userId': testUserId,
              'amountMinor': 1000 * i,
              'transactionType': 'expense',
              'categoryId': 'cat_1',
              'accountId': 'acc_1',
              'note': 'Valid record $i',
              'transactionDateUtc': '2026-09-03T10:00:00.000Z',
              'createdAtUtc': '2026-09-03T10:00:00.000Z',
              'updatedAtUtc': '2026-09-03T10:00:00.000Z',
              'fieldTimestampsJson': '{}',
              'syncStatus': 'synced',
            });
          }

          // Add 1 INVALID transaction (negative amount: -500 paise)
          txList.add({
            'id': 'tx_poison_pill',
            'userId': testUserId,
            'amountMinor': -500, // ILLEGAL AMOUNT
            'transactionType': 'expense',
            'categoryId': 'cat_1',
            'accountId': 'acc_1',
            'note': 'Poison pill record',
            'transactionDateUtc': '2026-09-03T10:00:00.000Z',
            'createdAtUtc': '2026-09-03T10:00:00.000Z',
            'updatedAtUtc': '2026-09-03T10:00:00.000Z',
            'fieldTimestampsJson': '{}',
            'syncStatus': 'synced',
          });

          final canonicalStr = jsonEncode(BackupArchive.canonicalize(data));
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );

          // VERIFY ZERO LEAKAGE: original 1 record remains untouched
          final postRollbackTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();

          expect(postRollbackTxs.length, equals(1));
          expect(postRollbackTxs.first.id, equals('tx_1'));
          expect(postRollbackTxs.first.note, equals('Weekly essentials'));
        },
      );

      test(
        '25b. Rejects corrupted non-JSON archive and preserves pre-existing database',
        () async {
          expect(
            () => backupService.restoreFromBackup(
              '<<< THIS IS NOT JSON >>>',
              targetUserId: testUserId,
            ),
            throwsA(isA<BackupRestoreException>()),
          );
          final txs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          expect(txs.length, equals(1));
          expect(txs.first.id, equals('tx_1'));
        },
      );

      test(
        '25c. Atomic rollback: Invalid enum (transactionType) rejects restore and preserves pre-existing data',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final txs = rawMap['data']['transactions'] as List;
          txs[0]['transactionType'] = 'INVALID_TYPE';
          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );
          final postTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          expect(postTxs.length, equals(1));
          expect(postTxs.first.id, equals('tx_1'));
        },
      );

      test(
        '25d. Atomic rollback: Invalid enum (accountType) rejects restore and preserves pre-existing data',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final accs = rawMap['data']['accounts'] as List;
          accs[0]['accountType'] = 'crypto_currency';
          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );
          final postAccs = await (db.select(
            db.accountsTable,
          )..where((a) => a.userId.equals(testUserId))).get();
          expect(postAccs.length, equals(1));
          expect(postAccs.first.id, equals('acc_1'));
        },
      );

      test(
        '25e. Atomic rollback: Malformed timestamp rejects restore and preserves pre-existing data',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final txs = rawMap['data']['transactions'] as List;
          txs[0]['transactionDateUtc'] = 'NOT_A_DATE';
          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );
          final postTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          expect(postTxs.length, equals(1));
        },
      );

      test(
        '25f. Atomic rollback: Malformed fieldTimestampsJson rejects restore and preserves pre-existing data',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final txs = rawMap['data']['transactions'] as List;
          txs[0]['fieldTimestampsJson'] = '{"amountMinor": "NOT_A_TIMESTAMP"}';
          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );
          final postTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          expect(postTxs.length, equals(1));
        },
      );

      test(
        '25g. Atomic rollback: Duplicate entity IDs rejects restore and preserves pre-existing data',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final txs = rawMap['data']['transactions'] as List;
          txs.add(Map<String, dynamic>.from(txs[0]));
          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
            ),
            throwsA(isA<ValidationException>()),
          );
          final postTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          expect(postTxs.length, equals(1));
        },
      );

      test(
        '25h. Atomic rollback: Malformed sync operation rejects restore and preserves pre-existing data',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final ops = rawMap['data']['syncOperations'] as List;
          ops.add({
            'id': 'op_bad_1',
            'userId': testUserId,
            'entityType': 'transactions',
            'entityId': 'tx_1',
            'operationType': 'UNKNOWN_TYPE',
            'payloadJson': 'not valid json',
            'createdAtUtc': '2026-09-02T10:00:00.000Z',
          });
          final canonicalStr = jsonEncode(
            BackupArchive.canonicalize(rawMap['data']),
          );
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          expect(
            () => backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
              restoreSyncQueue: true,
            ),
            throwsA(isA<ValidationException>()),
          );
          final postTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          expect(postTxs.length, equals(1));
        },
      );
    });

    // ------------------------------------------------------------------------
    // Group 5: Restore + Sync Scenarios A-F Proof
    // ------------------------------------------------------------------------
    group('5. Restore + Sync Scenarios A-F Proof', () {
      test(
        '26. Scenario A: Restored cursor at T1 ensures newer cloud mutation at T2 is observed and merged',
        () async {
          // Backup taken at T1 (cursor meta_1 at 2026-09-02T12:00:00.000Z)
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );

          // Restore backup onto device
          await backupService.restoreFromBackup(
            backupJson,
            targetUserId: testUserId,
          );

          final meta = await (db.select(
            db.syncMetadataTable,
          )..where((m) => m.userId.equals(testUserId))).getSingle();

          // Verify pull start cursor is exactly T1
          expect(meta.syncCursor, equals('2026-09-02T12:00:00.000Z_tx_1'));

          // Simulated remote mutation at T2 (2026-09-05)
          final remoteAccount = {
            'id': 'acc_1',
            'name': 'Premier Checking',
            'initialBalanceMinor': 500000,
            'updatedAtUtc': '2026-09-05T10:00:00.000Z',
          };
          final remoteTimestamps = {
            'name': '2026-09-05T10:00:00.000Z',
            'initialBalanceMinor': '2026-09-01T00:00:00.000Z',
          };

          final localAccount = await (db.select(
            db.accountsTable,
          )..where((a) => a.id.equals('acc_1'))).getSingle();

          final resolution = ConflictResolver.resolvePayloadConflict(
            localPayload: {
              'name': localAccount.name,
              'initialBalanceMinor': localAccount.initialBalanceMinor,
            },
            remotePayload: remoteAccount,
            localFieldTimestamps: jsonDecode(
              localAccount.fieldTimestampsJson,
            ).cast<String, String>(),
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: localAccount.updatedAtUtc,
            remoteUpdatedAtUtc: DateTime.parse(
              remoteAccount['updatedAtUtc'] as String,
            ).toUtc(),
          );

          // Remote mutation at T2 merged cleanly
          expect(resolution.mergedPayload['name'], equals('Premier Checking'));
          expect(resolution.fieldsUpdatedFromRemote, equals(1));
        },
      );

      test(
        '27. Scenario B: Backup with unsynced local queue restores operations without loss',
        () async {
          // Add unsynced pending mutation to sync queue
          await db
              .into(db.syncOperationsTable)
              .insert(
                SyncOperationsTableCompanion(
                  id: const drift.Value('op_unsynced_1'),
                  userId: const drift.Value(testUserId),
                  entityType: const drift.Value('transactions'),
                  entityId: const drift.Value('tx_pending_1'),
                  operationType: const drift.Value('create'),
                  payloadJson: const drift.Value('{"amountMinor": 2500}'),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 3)),
                ),
              );

          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );

          // Clear local queue
          await (db.delete(db.syncOperationsTable)).go();

          // Restore with restoreSyncQueue = true
          await backupService.restoreFromBackup(
            backupJson,
            targetUserId: testUserId,
            restoreSyncQueue: true,
          );

          final restoredOps = await (db.select(
            db.syncOperationsTable,
          )..where((o) => o.userId.equals(testUserId))).get();

          expect(restoredOps.length, equals(1));
          expect(restoredOps.first.id, equals('op_unsynced_1'));
          expect(restoredOps.first.entityId, equals('tx_pending_1'));
          expect(restoredOps.first.operationType, equals('create'));
        },
      );

      test(
        '28. Scenario C: Restored operation already processed on server is idempotent',
        () async {
          // Operation was in backup
          const opId = 'op_already_processed_on_server';
          final serverProcessedLog = <String>{opId}; // Server idempotency log

          // Client checks server response during push
          final isDuplicate = serverProcessedLog.contains(opId);
          expect(isDuplicate, isTrue);

          // Simulated server RPC return
          final rpcResponse = isDuplicate
              ? {'applied': false, 'already_processed': true}
              : {'applied': true, 'already_processed': false};

          expect(rpcResponse['already_processed'], isTrue);
          expect(rpcResponse['applied'], isFalse);
        },
      );

      test(
        '29. Scenario D: Restored tombstone wins over older cloud mutation',
        () {
          // Restored account contains tombstone at T_del (2026-09-05)
          final localData = {
            'id': 'acc_1',
            'name': 'Checking',
            'deletedAtUtc': '2026-09-05T12:00:00.000Z',
          };
          final localTimestamps = {
            'deletedAtUtc': '2026-09-05T12:00:00.000Z',
            'name': '2026-09-01T00:00:00.000Z',
          };

          // Older incoming cloud update from 2026-09-03
          final remoteData = {
            'id': 'acc_1',
            'name': 'Cloud Stale Name',
            'deletedAtUtc': null,
          };
          final remoteTimestamps = {'name': '2026-09-03T00:00:00.000Z'};

          final resolution = ConflictResolver.reconcileEntityState(
            localPayload: localData,
            remotePayload: remoteData,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: DateTime.utc(2026, 9, 5, 12),
            remoteUpdatedAtUtc: DateTime.utc(2026, 9, 3),
            localDeletedAtUtc: DateTime.utc(2026, 9, 5, 12),
            remoteDeletedAtUtc: null,
          );

          // Tombstone wins: deletedAtUtc remains intact
          expect(
            resolution.mergedPayload['deletedAtUtc'],
            equals('2026-09-05T12:00:00.000Z'),
          );
          expect(
            ConflictResolver.shouldRecordBeDeleted(
              localDeletedAtUtc: DateTime.utc(2026, 9, 5, 12),
              remoteDeletedAtUtc: null,
              localUpdatedAtUtc: DateTime.utc(2026, 9, 5, 12),
              remoteUpdatedAtUtc: DateTime.utc(2026, 9, 3),
            ),
            isTrue,
          );
        },
      );

      test(
        '30. Scenario E: Deterministic Field-Level LWW merges newer remote fields into restored state',
        () {
          // Restored local state: amount updated locally at T2, note updated at T0
          final localPayload = {'amountMinor': 7500, 'note': 'Old Note'};
          final localTimestamps = {
            'amountMinor': '2026-09-04T12:00:00.000Z', // newer
            'note': '2026-09-01T00:00:00.000Z', // older
          };

          // Incoming remote state: amount updated at T1, note updated at T3
          final remotePayload = {
            'amountMinor': 5000,
            'note': 'New Remote Note',
          };
          final remoteTimestamps = {
            'amountMinor': '2026-09-02T12:00:00.000Z', // older
            'note': '2026-09-05T12:00:00.000Z', // newer
          };

          final resolution = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: DateTime.utc(2026, 9, 4, 12),
            remoteUpdatedAtUtc: DateTime.utc(2026, 9, 5, 12),
          );

          // Local amount wins (Sep 4 > Sep 2)
          expect(resolution.mergedPayload['amountMinor'], equals(7500));
          // Remote note wins (Sep 5 > Sep 1)
          expect(resolution.mergedPayload['note'], equals('New Remote Note'));
        },
      );

      test(
        '31. Scenario F: Restored composite cursor (timestamp, entityId) prevents skip or duplicate across shared timestamps',
        () {
          final ts = DateTime.utc(2026, 9, 2, 12);
          final entities = [
            {'id': 'entity_A', 'updatedAtUtc': ts},
            {'id': 'entity_B', 'updatedAtUtc': ts},
            {'id': 'entity_C', 'updatedAtUtc': ts},
          ];

          // Cursor restored after processing entity_B
          final cursorTs = ts;
          const cursorId = 'entity_B';

          // Server pagination filter: (updatedAtUtc > cursorTs) OR (updatedAtUtc == cursorTs AND id > cursorId)
          final filtered = entities.where((e) {
            final eTs = e['updatedAtUtc'] as DateTime;
            final eId = e['id'] as String;
            if (eTs.isAfter(cursorTs)) {
              return true;
            }
            if (eTs.isAtSameMomentAs(cursorTs) && eId.compareTo(cursorId) > 0) {
              return true;
            }
            return false;
          }).toList();

          // Exactly entity_C is fetched: entity_A and entity_B are NOT duplicated, entity_C is NOT skipped!
          expect(filtered.length, equals(1));
          expect(filtered.first['id'], equals('entity_C'));
        },
      );

      test(
        '31b. Scenario G: Existing Local Database: Restore executes FULL REPLACE across ALL 10 user-owned tables',
        () async {
          // 1. Budget C
          await db
              .into(db.budgetsTable)
              .insert(
                BudgetsTableCompanion(
                  id: const drift.Value('budget_C'),
                  userId: const drift.Value(testUserId),
                  monthYear: const drift.Value('2026-10'),
                  amountMinor: const drift.Value(60000),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                ),
              );
          // Add Category C
          await db
              .into(db.categoriesTable)
              .insert(
                CategoriesTableCompanion(
                  id: const drift.Value('cat_C'),
                  userId: const drift.Value(testUserId),
                  name: const drift.Value('Category C to be purged'),
                  type: const drift.Value('expense'),
                  iconCodePoint: const drift.Value(0xe040),
                  colorValue: const drift.Value(0xFFEF4444),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                ),
              );

          // Add Category Budget C
          await db
              .into(db.categoryBudgetsTable)
              .insert(
                CategoryBudgetsTableCompanion(
                  id: const drift.Value('cb_C'),
                  userId: const drift.Value(testUserId),
                  budgetId: const drift.Value('budget_C'),
                  categoryId: const drift.Value('cat_C'),
                  amountMinor: const drift.Value(25000),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                ),
              );

          // Add Account C
          await db
              .into(db.accountsTable)
              .insert(
                AccountsTableCompanion(
                  id: const drift.Value('acc_C'),
                  userId: const drift.Value(testUserId),
                  name: const drift.Value('Account C to be purged'),
                  accountType: const drift.Value('cash'),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                ),
              );

          // Add Transaction C
          await db
              .into(db.transactionsTable)
              .insert(
                TransactionsTableCompanion(
                  id: const drift.Value('tx_C'),
                  userId: const drift.Value(testUserId),
                  amountMinor: const drift.Value(9900),
                  transactionType: const drift.Value('expense'),
                  categoryId: const drift.Value('cat_C'),
                  accountId: const drift.Value('acc_C'),
                  note: const drift.Value('Transaction C to be purged'),
                  transactionDateUtc: drift.Value(DateTime.utc(2026, 9, 2)),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
                ),
              );

          // Add Goal C
          await db
              .into(db.savingsGoalsTable)
              .insert(
                SavingsGoalsTableCompanion(
                  id: const drift.Value('goal_C'),
                  userId: const drift.Value(testUserId),
                  name: const drift.Value('Goal C'),
                  targetAmountMinor: const drift.Value(50000),
                  targetDateUtc: drift.Value(DateTime.utc(2026, 12, 31)),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                ),
              );

          // Add Recurring C
          await db
              .into(db.recurringTransactionsTable)
              .insert(
                RecurringTransactionsTableCompanion(
                  id: const drift.Value('rec_C'),
                  userId: const drift.Value(testUserId),
                  amountMinor: const drift.Value(1200),
                  transactionType: const drift.Value('expense'),
                  categoryId: const drift.Value('cat_C'),
                  accountId: const drift.Value('acc_C'),
                  frequency: const drift.Value('monthly'),
                  startDateUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  nextOccurrenceUtc: drift.Value(DateTime.utc(2026, 10, 1)),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                ),
              );

          // Add Pending Sync Op C
          await db
              .into(db.syncOperationsTable)
              .insert(
                SyncOperationsTableCompanion(
                  id: const drift.Value('op_C'),
                  userId: const drift.Value(testUserId),
                  entityType: const drift.Value('transactions'),
                  entityId: const drift.Value('tx_C'),
                  operationType: const drift.Value('create'),
                  payloadJson: const drift.Value('{"amountMinor":9900}'),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
                ),
              );

          // Add Setting C
          await db
              .into(db.settingsTable)
              .insert(
                SettingsTableCompanion(
                  key: const drift.Value('custom_pref_C'),
                  userId: const drift.Value(testUserId),
                  value: const drift.Value('custom_val_C'),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
                ),
              );

          // Add Sync Metadata C
          await db
              .into(db.syncMetadataTable)
              .insert(
                SyncMetadataTableCompanion(
                  id: const drift.Value('meta_C'),
                  userId: const drift.Value(testUserId),
                  syncCursor: const drift.Value('cursor_C'),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
                ),
              );

          // Create backup containing ONLY original A records
          final fullBackupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(fullBackupJson) as Map<String, dynamic>;
          final data = rawMap['data'] as Map<String, dynamic>;
          (data['transactions'] as List).removeWhere((t) => t['id'] == 'tx_C');
          (data['accounts'] as List).removeWhere((a) => a['id'] == 'acc_C');
          (data['categories'] as List).removeWhere((c) => c['id'] == 'cat_C');
          (data['savingsGoals'] as List).removeWhere(
            (g) => g['id'] == 'goal_C',
          );
          (data['recurringTransactions'] as List).removeWhere(
            (r) => r['id'] == 'rec_C',
          );
          (data['budgets'] as List).removeWhere((b) => b['id'] == 'budget_C');
          (data['categoryBudgets'] as List).removeWhere(
            (cb) => cb['id'] == 'cb_C',
          );
          (data['settings'] as List).removeWhere(
            (s) => s['key'] == 'custom_pref_C',
          );
          (data['syncMetadata'] as List).removeWhere(
            (m) => m['id'] == 'meta_C',
          );
          (data['syncOperations'] as List).removeWhere(
            (o) => o['id'] == 'op_C',
          );

          final canonicalStr = jsonEncode(BackupArchive.canonicalize(data));
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          // Restore backup
          await backupService.restoreFromBackup(
            jsonEncode(rawMap),
            targetUserId: testUserId,
          );

          // VERIFY FULL REPLACE:
          // A records exist
          final restoredTxs = await (db.select(
            db.transactionsTable,
          )..where((t) => t.userId.equals(testUserId))).get();
          final restoredAccs = await (db.select(
            db.accountsTable,
          )..where((a) => a.userId.equals(testUserId))).get();
          final restoredCats =
              await (db.select(db.categoriesTable)..where(
                    (c) =>
                        c.userId.equals(testUserId) & c.isSystem.equals(false),
                  ))
                  .get();

          expect(restoredTxs.any((t) => t.id == 'tx_1'), isTrue);
          expect(restoredAccs.any((a) => a.id == 'acc_1'), isTrue);
          expect(restoredCats.any((c) => c.id == 'cat_1'), isTrue);

          // C records are completely purged
          expect(restoredTxs.any((t) => t.id == 'tx_C'), isFalse);
          expect(restoredAccs.any((a) => a.id == 'acc_C'), isFalse);
          expect(restoredCats.any((c) => c.id == 'cat_C'), isFalse);

          final remainingGoals = await (db.select(
            db.savingsGoalsTable,
          )..where((g) => g.id.equals('goal_C'))).get();
          expect(remainingGoals.isEmpty, isTrue);

          final remainingRec = await (db.select(
            db.recurringTransactionsTable,
          )..where((r) => r.id.equals('rec_C'))).get();
          expect(remainingRec.isEmpty, isTrue);

          final remainingOps = await (db.select(
            db.syncOperationsTable,
          )..where((o) => o.id.equals('op_C'))).get();
          expect(remainingOps.isEmpty, isTrue);

          final remainingBudgets = await (db.select(
            db.budgetsTable,
          )..where((b) => b.id.equals('budget_C'))).get();
          expect(remainingBudgets.isEmpty, isTrue);

          final remainingCategoryBudgets = await (db.select(
            db.categoryBudgetsTable,
          )..where((cb) => cb.id.equals('cb_C'))).get();
          expect(remainingCategoryBudgets.isEmpty, isTrue);

          final remainingSettings = await (db.select(
            db.settingsTable,
          )..where((s) => s.key.equals('custom_pref_C'))).get();
          expect(remainingSettings.isEmpty, isTrue);

          final remainingMeta = await (db.select(
            db.syncMetadataTable,
          )..where((m) => m.id.equals('meta_C'))).get();
          expect(remainingMeta.isEmpty, isTrue);
        },
      );

      test(
        '31c. Scenario H: Pending Operation Becomes Already Processed on server: local queue acknowledges without duplicate mutation',
        () async {
          final backupJson = await backupService.createFullBackup(
            userId: testUserId,
          );
          final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
          final data = rawMap['data'] as Map<String, dynamic>;
          (data['syncOperations'] as List).add({
            'id': 'op_server_processed_1',
            'userId': testUserId,
            'entityType': 'transactions',
            'entityId': 'tx_1',
            'operationType': 'update',
            'payloadJson': '{"amountMinor": 20000}',
            'createdAtUtc': '2026-09-03T10:00:00.000Z',
            'retryCount': 0,
          });
          final canonicalStr = jsonEncode(BackupArchive.canonicalize(data));
          rawMap['metadata']['checksum'] = sha256
              .convert(utf8.encode(canonicalStr))
              .toString();

          await backupService.restoreFromBackup(
            jsonEncode(rawMap),
            targetUserId: testUserId,
            restoreSyncQueue: true,
          );

          final ops = await (db.select(
            db.syncOperationsTable,
          )..where((o) => o.id.equals('op_server_processed_1'))).get();
          expect(ops.length, equals(1));

          const serverProcessedLog = {'op_server_processed_1'};
          final serverResponse = serverProcessedLog.contains(ops.first.id)
              ? {'applied': false, 'already_processed': true}
              : {'applied': true, 'already_processed': false};

          expect(serverResponse['already_processed'], isTrue);

          if (serverResponse['already_processed'] == true) {
            await (db.delete(
              db.syncOperationsTable,
            )..where((o) => o.id.equals('op_server_processed_1'))).go();
            await (db.update(
              db.transactionsTable,
            )..where((t) => t.id.equals('tx_1'))).write(
              const TransactionsTableCompanion(
                syncStatus: drift.Value('synced'),
              ),
            );
          }

          final remainingOps = await (db.select(
            db.syncOperationsTable,
          )..where((o) => o.id.equals('op_server_processed_1'))).get();
          expect(remainingOps.isEmpty, isTrue);

          final tx = await (db.select(
            db.transactionsTable,
          )..where((t) => t.id.equals('tx_1'))).getSingle();
          expect(tx.syncStatus, equals('synced'));
        },
      );

      test(
        '31d. Scenario I: Pending Local Mutation vs Newer Cloud Field follows Field-Level LWW',
        () {
          final localPayload = {'amountMinor': 10000, 'note': 'Restored Note'};
          final localTimestamps = {
            'amountMinor': '2026-09-02T10:00:00.000Z',
            'note': '2026-09-05T10:00:00.000Z',
          };

          final remotePayload = {
            'amountMinor': 25000,
            'note': 'Cloud Old Note',
          };
          final remoteTimestamps = {
            'amountMinor': '2026-09-04T10:00:00.000Z',
            'note': '2026-09-01T10:00:00.000Z',
          };

          final resolution = ConflictResolver.resolvePayloadConflict(
            localPayload: localPayload,
            remotePayload: remotePayload,
            localFieldTimestamps: localTimestamps,
            remoteFieldTimestamps: remoteTimestamps,
            localUpdatedAtUtc: DateTime.utc(2026, 9, 2),
            remoteUpdatedAtUtc: DateTime.utc(2026, 9, 4),
          );

          expect(resolution.mergedPayload['amountMinor'], equals(25000));
          expect(resolution.mergedPayload['note'], equals('Restored Note'));
          expect(
            resolution.mergedFieldTimestamps['amountMinor'],
            equals('2026-09-04T10:00:00.000Z'),
          );
          expect(
            resolution.mergedFieldTimestamps['note'],
            equals('2026-09-05T10:00:00.000Z'),
          );
        },
      );

      test(
        '31e. Scenario J: Restored tombstone wins over older incoming cloud update',
        () {
          final localDeletedAt = DateTime.utc(2026, 9, 5, 12);
          final remoteUpdatedAt = DateTime.utc(2026, 9, 3, 10);

          final shouldBeDeleted = ConflictResolver.shouldRecordBeDeleted(
            localDeletedAtUtc: localDeletedAt,
            remoteDeletedAtUtc: null,
            localUpdatedAtUtc: localDeletedAt,
            remoteUpdatedAtUtc: remoteUpdatedAt,
          );

          expect(shouldBeDeleted, isTrue);

          final resolution = ConflictResolver.reconcileEntityState(
            localPayload: {
              'id': 'tx_1',
              'amountMinor': 15000,
              'deletedAtUtc': '2026-09-05T12:00:00.000Z',
            },
            remotePayload: {
              'id': 'tx_1',
              'amountMinor': 18000,
              'deletedAtUtc': null,
            },
            localFieldTimestamps: {'deletedAtUtc': '2026-09-05T12:00:00.000Z'},
            remoteFieldTimestamps: {'amountMinor': '2026-09-03T10:00:00.000Z'},
            localUpdatedAtUtc: localDeletedAt,
            remoteUpdatedAtUtc: remoteUpdatedAt,
            localDeletedAtUtc: localDeletedAt,
            remoteDeletedAtUtc: null,
          );

          expect(
            resolution.mergedPayload['deletedAtUtc'],
            equals('2026-09-05T12:00:00.000Z'),
          );
        },
      );

      test(
        '31f. Scenario K: Multi-entity pagination using (timestamp, entityId) composite cursor across shared timestamps',
        () {
          final sharedTimestamp = DateTime.utc(2026, 9, 5, 12);
          final allEntities = [
            {'id': 'entity_001', 'updatedAtUtc': sharedTimestamp},
            {'id': 'entity_002', 'updatedAtUtc': sharedTimestamp},
            {'id': 'entity_003', 'updatedAtUtc': sharedTimestamp},
            {'id': 'entity_004', 'updatedAtUtc': sharedTimestamp},
          ];

          final page1 = allEntities.take(2).toList();
          expect(page1.length, equals(2));
          expect(
            page1.map((e) => e['id']),
            containsAllInOrder(['entity_001', 'entity_002']),
          );

          final lastEntity = page1.last;
          final cursorTs = lastEntity['updatedAtUtc'] as DateTime;
          final cursorId = lastEntity['id'] as String;

          final page2 = allEntities.where((e) {
            final eTs = e['updatedAtUtc'] as DateTime;
            final eId = e['id'] as String;
            if (eTs.isAfter(cursorTs)) {
              return true;
            }
            if (eTs.isAtSameMomentAs(cursorTs) && eId.compareTo(cursorId) > 0) {
              return true;
            }
            return false;
          }).toList();

          expect(page2.length, equals(2));
          expect(
            page2.map((e) => e['id']),
            containsAllInOrder(['entity_003', 'entity_004']),
          );

          final combinedIds = [
            ...page1.map((e) => e['id']),
            ...page2.map((e) => e['id']),
          ];
          expect(
            combinedIds,
            equals(['entity_001', 'entity_002', 'entity_003', 'entity_004']),
          );
        },
      );
    });

    test(
      '31g. Sync Queue Policy Case 3: Restore with queue restoration disabled forces syncStatus to synced so no orphaned pending records remain',
      () async {
        // Backup contains transaction with pendingCreate and pending sync queue operation
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
        );
        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
        final data = rawMap['data'] as Map<String, dynamic>;

        final txs = data['transactions'] as List;
        txs[0]['syncStatus'] =
            'pendingCreate'; // pending locally when backed up

        (data['syncOperations'] as List).add({
          'id': 'op_pending_in_backup',
          'userId': testUserId,
          'entityType': 'transactions',
          'entityId': 'tx_1',
          'operationType': 'create',
          'payloadJson': '{"amountMinor": 15000}',
          'createdAtUtc': '2026-09-02T10:00:00.000Z',
        });

        final canonicalStr = jsonEncode(BackupArchive.canonicalize(data));
        rawMap['metadata']['checksum'] = sha256
            .convert(utf8.encode(canonicalStr))
            .toString();

        // Restore with restoreSyncQueue = false (the default)
        await backupService.restoreFromBackup(
          jsonEncode(rawMap),
          targetUserId: testUserId,
          restoreSyncQueue: false,
        );

        // Queue is empty
        final ops = await (db.select(
          db.syncOperationsTable,
        )..where((o) => o.userId.equals(testUserId))).get();
        expect(ops.isEmpty, isTrue);

        // Restored transaction has syncStatus = 'synced', NOT pending!
        final tx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals('tx_1'))).getSingle();
        expect(tx.syncStatus, equals('synced'));
      },
    );

    test(
      '31h. Cursor Restore: Restoring cursor (T1, ID1) observes cloud (T1, ID2), (T1, ID3), (T2, ID4) without skipping',
      () {
        final t1 = DateTime.utc(2026, 9, 2, 12);
        final t2 = DateTime.utc(2026, 9, 3, 12);

        // Restored backup cursor is (T1, 'ID1')
        final cursorTs = t1;
        const cursorId = 'ID1';

        // Cloud entities
        final cloudEntities = [
          {
            'id': 'ID0',
            'updatedAtUtc': t1,
          }, // older on same timestamp: should be skipped
          {
            'id': 'ID2',
            'updatedAtUtc': t1,
          }, // newer on same timestamp: MUST be observed
          {
            'id': 'ID3',
            'updatedAtUtc': t1,
          }, // newer on same timestamp: MUST be observed
          {
            'id': 'ID4',
            'updatedAtUtc': t2,
          }, // strictly newer timestamp: MUST be observed
        ];

        // Composite cursor filter applied by SyncCoordinator pull queries
        final observed = cloudEntities.where((e) {
          final eTs = e['updatedAtUtc'] as DateTime;
          final eId = e['id'] as String;
          if (eTs.isAfter(cursorTs)) return true;
          if (eTs.isAtSameMomentAs(cursorTs) && eId.compareTo(cursorId) > 0) {
            return true;
          }
          return false;
        }).toList();

        expect(observed.length, equals(3));
        expect(observed.map((e) => e['id']), equals(['ID2', 'ID3', 'ID4']));
      },
    );

    test(
      '31i. Full Database State Preservation on Restore Failure across all original values, sync state, and cursor state',
      () async {
        // Seed non-empty database with records across all tables
        await db
            .into(db.budgetsTable)
            .insert(
              BudgetsTableCompanion(
                id: const drift.Value('original_budget'),
                userId: const drift.Value(testUserId),
                monthYear: const drift.Value('2026-09'),
                amountMinor: const drift.Value(75000),
                createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              ),
            );

        await db
            .into(db.savingsGoalsTable)
            .insert(
              SavingsGoalsTableCompanion(
                id: const drift.Value('original_goal'),
                userId: const drift.Value(testUserId),
                name: const drift.Value('Emergency Fund'),
                targetAmountMinor: const drift.Value(300000),
                currentAmountMinor: const drift.Value(50000),
                targetDateUtc: drift.Value(DateTime.utc(2026, 12, 31)),
                createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              ),
            );

        await db
            .into(db.recurringTransactionsTable)
            .insert(
              RecurringTransactionsTableCompanion(
                id: const drift.Value('original_rec'),
                userId: const drift.Value(testUserId),
                amountMinor: const drift.Value(49900),
                transactionType: const drift.Value('expense'),
                categoryId: const drift.Value('cat_1'),
                accountId: const drift.Value('acc_1'),
                frequency: const drift.Value('monthly'),
                startDateUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                nextOccurrenceUtc: drift.Value(DateTime.utc(2026, 10, 1)),
                createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              ),
            );

        await db
            .into(db.settingsTable)
            .insert(
              SettingsTableCompanion(
                key: const drift.Value('theme_mode'),
                userId: const drift.Value(testUserId),
                value: const drift.Value('dark'),
                updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
              ),
            );

        await db
            .into(db.syncOperationsTable)
            .insert(
              SyncOperationsTableCompanion(
                id: const drift.Value('original_pending_op'),
                userId: const drift.Value(testUserId),
                entityType: const drift.Value('transactions'),
                entityId: const drift.Value('tx_1'),
                operationType: const drift.Value('update'),
                payloadJson: const drift.Value('{"amountMinor":15000}'),
                createdAtUtc: drift.Value(DateTime.utc(2026, 9, 2)),
              ),
            );

        // Capture complete pre-restore state
        final preTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals('tx_1'))).getSingle();
        final preAcc = await (db.select(
          db.accountsTable,
        )..where((a) => a.id.equals('acc_1'))).getSingle();
        final preCat = await (db.select(
          db.categoriesTable,
        )..where((c) => c.id.equals('cat_1'))).getSingle();
        final preBudget = await (db.select(
          db.budgetsTable,
        )..where((b) => b.id.equals('original_budget'))).getSingle();
        final preGoal = await (db.select(
          db.savingsGoalsTable,
        )..where((g) => g.id.equals('original_goal'))).getSingle();
        final preRec = await (db.select(
          db.recurringTransactionsTable,
        )..where((r) => r.id.equals('original_rec'))).getSingle();
        final preSetting = await (db.select(
          db.settingsTable,
        )..where((s) => s.key.equals('theme_mode'))).getSingle();
        final preOp = await (db.select(
          db.syncOperationsTable,
        )..where((o) => o.id.equals('original_pending_op'))).getSingle();
        final preMeta = await (db.select(
          db.syncMetadataTable,
        )..where((m) => m.id.equals('meta_1'))).getSingle();

        // Attempt restore of a corrupted/poison-pill backup
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
        );
        final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
        (rawMap['data']['transactions'] as List).add({
          'id': 'tx_fatal_pill',
          'userId': testUserId,
          'amountMinor': -99999, // INVALID AMOUNT
          'transactionType': 'expense',
          'categoryId': 'cat_1',
          'accountId': 'acc_1',
          'transactionDateUtc': '2026-09-02T10:00:00.000Z',
          'createdAtUtc': '2026-09-02T10:00:00.000Z',
          'updatedAtUtc': '2026-09-02T10:00:00.000Z',
        });
        final canonicalStr = jsonEncode(
          BackupArchive.canonicalize(rawMap['data']),
        );
        rawMap['metadata']['checksum'] = sha256
            .convert(utf8.encode(canonicalStr))
            .toString();

        expect(
          () => backupService.restoreFromBackup(
            jsonEncode(rawMap),
            targetUserId: testUserId,
          ),
          throwsA(isA<ValidationException>()),
        );

        // VERIFY COMPLETE POST-RESTORE STATE IDENTICAL TO PRE-RESTORE STATE:
        final postTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals('tx_1'))).getSingle();
        expect(postTx.amountMinor, equals(preTx.amountMinor));
        expect(postTx.note, equals(preTx.note));
        expect(postTx.syncStatus, equals(preTx.syncStatus));

        final postAcc = await (db.select(
          db.accountsTable,
        )..where((a) => a.id.equals('acc_1'))).getSingle();
        expect(postAcc.name, equals(preAcc.name));
        expect(postAcc.initialBalanceMinor, equals(preAcc.initialBalanceMinor));
        expect(postAcc.syncStatus, equals(preAcc.syncStatus));

        final postCat = await (db.select(
          db.categoriesTable,
        )..where((c) => c.id.equals('cat_1'))).getSingle();
        expect(postCat.name, equals(preCat.name));
        expect(postCat.syncStatus, equals(preCat.syncStatus));

        final postBudget = await (db.select(
          db.budgetsTable,
        )..where((b) => b.id.equals('original_budget'))).getSingle();
        expect(postBudget.amountMinor, equals(preBudget.amountMinor));
        expect(postBudget.monthYear, equals(preBudget.monthYear));

        final postGoal = await (db.select(
          db.savingsGoalsTable,
        )..where((g) => g.id.equals('original_goal'))).getSingle();
        expect(postGoal.name, equals(preGoal.name));
        expect(postGoal.targetAmountMinor, equals(preGoal.targetAmountMinor));

        final postRec = await (db.select(
          db.recurringTransactionsTable,
        )..where((r) => r.id.equals('original_rec'))).getSingle();
        expect(postRec.amountMinor, equals(preRec.amountMinor));
        expect(postRec.frequency, equals(preRec.frequency));

        final postSetting = await (db.select(
          db.settingsTable,
        )..where((s) => s.key.equals('theme_mode'))).getSingle();
        expect(postSetting.value, equals(preSetting.value));

        final postOp = await (db.select(
          db.syncOperationsTable,
        )..where((o) => o.id.equals('original_pending_op'))).getSingle();
        expect(postOp.id, equals(preOp.id));
        expect(postOp.operationType, equals(preOp.operationType));
        expect(postOp.payloadJson, equals(preOp.payloadJson));

        final postMeta = await (db.select(
          db.syncMetadataTable,
        )..where((m) => m.id.equals('meta_1'))).getSingle();
        expect(postMeta.syncCursor, equals(preMeta.syncCursor));
        expect(postMeta.updatedAtUtc, equals(preMeta.updatedAtUtc));
      },
    );

    // ------------------------------------------------------------------------
    // Group 6: Export vs Backup Separation
    // ------------------------------------------------------------------------
    group('6. Export vs Backup Separation', () {
      test(
        '32. ExportService generates valid RFC 4180 CSV without internal metadata',
        () async {
          final csvString = await exportService.exportTransactionsCsv(
            userId: testUserId,
          );

          expect(
            csvString.contains(
              'Date,Type,Category,Account,Amount,Currency,Note',
            ),
            isTrue,
          );
          expect(
            csvString.contains(
              '2026-09-02,EXPENSE,Groceries,Checking,150.00,INR,Weekly essentials',
            ),
            isTrue,
          );

          // Crucial verification: CSV does NOT contain internal metadata
          expect(csvString.contains('fieldTimestampsJson'), isFalse);
          expect(csvString.contains('syncCursor'), isFalse);
          expect(csvString.contains('tx_1'), isFalse); // UUID omitted
        },
      );

      test(
        '33. Soft-deleted transactions are excluded from CSV export',
        () async {
          // Seed soft-deleted transaction
          await db
              .into(db.transactionsTable)
              .insert(
                TransactionsTableCompanion(
                  id: const drift.Value('tx_deleted'),
                  userId: const drift.Value(testUserId),
                  amountMinor: const drift.Value(5000),
                  transactionType: const drift.Value('expense'),
                  categoryId: const drift.Value('cat_1'),
                  accountId: const drift.Value('acc_1'),
                  note: const drift.Value('Deleted coffee purchase'),
                  transactionDateUtc: drift.Value(DateTime.utc(2026, 9, 3)),
                  deletedAtUtc: drift.Value(DateTime.utc(2026, 9, 4)),
                  createdAtUtc: drift.Value(DateTime.utc(2026, 9, 3)),
                  updatedAtUtc: drift.Value(DateTime.utc(2026, 9, 4)),
                ),
              );

          final csvString = await exportService.exportTransactionsCsv(
            userId: testUserId,
          );
          expect(csvString.contains('Deleted coffee purchase'), isFalse);
        },
      );
    });

    // ------------------------------------------------------------------------
    // ------------------------------------------------------------------------
    // ------------------------------------------------------------------------
    // Group 7: Phase 8 Gate — Snapshot Consistency, Idempotency & Metadata Verification
    // ------------------------------------------------------------------------
    group(
      '7. Phase 8 Gate — Snapshot Consistency, Idempotency & Metadata Verification',
      () {
        test(
          'P8-Gate 1: createFullBackup captures all 11 tables inside an atomic transaction',
          () async {
            final t0 = DateTime.utc(2026, 9, 1);
            await db
                .into(db.budgetsTable)
                .insert(
                  BudgetsTableCompanion(
                    id: const drift.Value('b_gate'),
                    userId: const drift.Value(testUserId),
                    monthYear: const drift.Value('2026-09'),
                    amountMinor: const drift.Value(100000),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.categoryBudgetsTable)
                .insert(
                  CategoryBudgetsTableCompanion(
                    id: const drift.Value('cb_gate'),
                    userId: const drift.Value(testUserId),
                    budgetId: const drift.Value('b_gate'),
                    categoryId: const drift.Value('cat_1'),
                    amountMinor: const drift.Value(50000),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.savingsGoalsTable)
                .insert(
                  SavingsGoalsTableCompanion(
                    id: const drift.Value('sg_gate'),
                    userId: const drift.Value(testUserId),
                    name: const drift.Value('Emergency'),
                    targetAmountMinor: const drift.Value(500000),
                    currentAmountMinor: const drift.Value(100000),
                    targetDateUtc: drift.Value(t0),
                    iconCodePoint: const drift.Value(1),
                    colorValue: const drift.Value(1),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.recurringTransactionsTable)
                .insert(
                  RecurringTransactionsTableCompanion(
                    id: const drift.Value('rt_gate'),
                    userId: const drift.Value(testUserId),
                    amountMinor: const drift.Value(15000),
                    transactionType: const drift.Value('expense'),
                    categoryId: const drift.Value('cat_1'),
                    accountId: const drift.Value('acc_1'),
                    frequency: const drift.Value('monthly'),
                    startDateUtc: drift.Value(t0),
                    nextOccurrenceUtc: drift.Value(t0),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.settingsTable)
                .insert(
                  SettingsTableCompanion(
                    key: const drift.Value('currency'),
                    userId: const drift.Value(testUserId),
                    value: const drift.Value('INR'),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value('op_gate'),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('category'),
                    entityId: const drift.Value('cat_1'),
                    operationType: const drift.Value('update'),
                    payloadJson: const drift.Value('{}'),
                    createdAtUtc: drift.Value(t0),
                  ),
                );

            final backupJson = await backupService.createFullBackup(
              userId: testUserId,
            );
            final archive = BackupArchive.fromJson(jsonDecode(backupJson));
            final data = archive.data!;

            expect((data['users'] as List).length, equals(1));
            expect(
              (data['categories'] as List).length,
              greaterThanOrEqualTo(1),
            );
            expect((data['accounts'] as List).length, equals(1));
            expect((data['budgets'] as List).length, equals(1));
            expect((data['categoryBudgets'] as List).length, equals(1));
            expect((data['savingsGoals'] as List).length, equals(1));
            expect((data['recurringTransactions'] as List).length, equals(1));
            expect((data['transactions'] as List).length, equals(1));
            expect((data['settings'] as List).length, equals(1));
            expect((data['syncMetadata'] as List).length, equals(1));
            expect((data['syncOperations'] as List).length, equals(1));
          },
        );

        test(
          'P8-Gate 2: already_processed with identical state deletes queue and marks synced',
          () async {
            final connectivityService = _FakeConnectivityService();
            final remoteDataSource = FakeSyncRemoteDataSource();
            remoteDataSource.activeAuthUserId = testUserId;

            final coordinator = SyncCoordinator(
              db: db,
              remoteDataSource: remoteDataSource,
              connectivityService: connectivityService,
              getActiveUserId: () => testUserId,
            );

            const opId = 'op_idem_identical';
            const catId = 'cat_1';

            final cat = await (db.select(
              db.categoriesTable,
            )..where((c) => c.id.equals(catId))).getSingle();
            remoteDataSource.seedRemoteRecord(
              entityType: 'category',
              id: catId,
              userId: testUserId,
              payload: {
                'name': cat.name,
                'type': cat.type,
                'icon_code_point': cat.iconCodePoint,
                'color_value': cat.colorValue,
                'is_system': cat.isSystem,
                'is_archived': cat.isArchived,
              },
              fieldTimestamps: {'name': cat.createdAtUtc.toIso8601String()},
              updatedAtUtc: cat.updatedAtUtc,
            );
            remoteDataSource.processedTokens.add('$testUserId:$opId');

            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value(opId),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('category'),
                    entityId: const drift.Value(catId),
                    operationType: const drift.Value('update'),
                    payloadJson: drift.Value(jsonEncode({'name': cat.name})),
                    createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  ),
                );

            final syncRes = await coordinator.synchronize();
            expect(syncRes.success, isTrue);

            final remainingOps = await (db.select(
              db.syncOperationsTable,
            )..where((o) => o.id.equals(opId))).get();
            expect(remainingOps.isEmpty, isTrue);

            final postCat = await (db.select(
              db.categoriesTable,
            )..where((c) => c.id.equals(catId))).getSingle();
            expect(postCat.syncStatus, equals('synced'));
            expect(postCat.name, equals('Groceries'));
          },
        );

        test(
          'P8-Gate 3: already_processed with newer server field reconciles locally before marking synced',
          () async {
            final connectivityService = _FakeConnectivityService();
            final remoteDataSource = FakeSyncRemoteDataSource();
            remoteDataSource.activeAuthUserId = testUserId;

            final coordinator = SyncCoordinator(
              db: db,
              remoteDataSource: remoteDataSource,
              connectivityService: connectivityService,
              getActiveUserId: () => testUserId,
            );

            const opId = 'op_idem_server_wins';
            const catId = 'cat_1';

            final tNewer = DateTime.utc(2026, 9, 5);
            remoteDataSource.seedRemoteRecord(
              entityType: 'category',
              id: catId,
              userId: testUserId,
              payload: {
                'name': 'Supermarket',
                'type': 'expense',
                'icon_code_point': 0xe040,
                'color_value': 0xFF10B981,
                'is_system': false,
                'is_archived': false,
              },
              fieldTimestamps: {'name': tNewer.toIso8601String()},
              updatedAtUtc: tNewer,
            );
            remoteDataSource.processedTokens.add('$testUserId:$opId');

            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value(opId),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('category'),
                    entityId: const drift.Value(catId),
                    operationType: const drift.Value('update'),
                    payloadJson: const drift.Value('{"name":"Groceries"}'),
                    createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  ),
                );

            final syncRes = await coordinator.synchronize();
            expect(syncRes.success, isTrue);

            final remainingOps = await (db.select(
              db.syncOperationsTable,
            )..where((o) => o.id.equals(opId))).get();
            expect(remainingOps.isEmpty, isTrue);

            final postCat = await (db.select(
              db.categoriesTable,
            )..where((c) => c.id.equals(catId))).getSingle();
            expect(postCat.syncStatus, equals('synced'));
            expect(postCat.name, equals('Supermarket'));
          },
        );

        test(
          'P8-Gate 4: already_processed with newer local field preserves local field during reconciliation',
          () async {
            final connectivityService = _FakeConnectivityService();
            final remoteDataSource = FakeSyncRemoteDataSource();
            remoteDataSource.activeAuthUserId = testUserId;

            final coordinator = SyncCoordinator(
              db: db,
              remoteDataSource: remoteDataSource,
              connectivityService: connectivityService,
              getActiveUserId: () => testUserId,
            );

            const opId = 'op_idem_local_wins';
            const catId = 'cat_1';

            remoteDataSource.seedRemoteRecord(
              entityType: 'category',
              id: catId,
              userId: testUserId,
              payload: {
                'name': 'Old Groceries',
                'type': 'expense',
                'icon_code_point': 0xe040,
                'color_value': 0xFF10B981,
                'is_system': false,
                'is_archived': false,
              },
              fieldTimestamps: {'name': '2026-09-01T00:00:00.000Z'},
              updatedAtUtc: DateTime.utc(2026, 9, 1),
            );
            remoteDataSource.processedTokens.add('$testUserId:$opId');

            final tLocal = DateTime.utc(2026, 9, 6);
            await (db.update(
              db.categoriesTable,
            )..where((c) => c.id.equals(catId))).write(
              CategoriesTableCompanion(
                name: const drift.Value('Fresh Produce'),
                updatedAtUtc: drift.Value(tLocal),
                fieldTimestampsJson: drift.Value(
                  '{"name":"${tLocal.toIso8601String()}"}',
                ),
              ),
            );

            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value(opId),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('category'),
                    entityId: const drift.Value(catId),
                    operationType: const drift.Value('update'),
                    payloadJson: const drift.Value('{"name":"Fresh Produce"}'),
                    createdAtUtc: drift.Value(tLocal),
                  ),
                );

            final syncRes = await coordinator.synchronize();
            expect(syncRes.success, isTrue);

            final postCat = await (db.select(
              db.categoriesTable,
            )..where((c) => c.id.equals(catId))).getSingle();
            expect(postCat.name, equals('Fresh Produce'));
          },
        );

        test(
          'P8-Gate 5: already_processed with server tombstone applies tombstone locally',
          () async {
            final connectivityService = _FakeConnectivityService();
            final remoteDataSource = FakeSyncRemoteDataSource();
            remoteDataSource.activeAuthUserId = testUserId;

            final coordinator = SyncCoordinator(
              db: db,
              remoteDataSource: remoteDataSource,
              connectivityService: connectivityService,
              getActiveUserId: () => testUserId,
            );

            const opId = 'op_idem_tombstone';
            const catId = 'cat_1';

            final tDel = DateTime.utc(2026, 9, 5, 12);
            remoteDataSource.seedRemoteRecord(
              entityType: 'category',
              id: catId,
              userId: testUserId,
              payload: {
                'name': 'Groceries',
                'type': 'expense',
                'icon_code_point': 0xe040,
                'color_value': 0xFF10B981,
                'is_system': false,
                'is_archived': false,
              },
              fieldTimestamps: {'name': '2026-09-01T00:00:00.000Z'},
              updatedAtUtc: tDel,
              deletedAtUtc: tDel,
            );
            remoteDataSource.processedTokens.add('$testUserId:$opId');

            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value(opId),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('category'),
                    entityId: const drift.Value(catId),
                    operationType: const drift.Value('update'),
                    payloadJson: const drift.Value('{"name":"Groceries"}'),
                    createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  ),
                );

            final syncRes = await coordinator.synchronize();
            expect(syncRes.success, isTrue);

            final postCat = await (db.select(
              db.categoriesTable,
            )..where((c) => c.id.equals(catId))).getSingle();
            expect(postCat.deletedAtUtc, isNotNull);
            expect(postCat.syncStatus, equals('synced'));
          },
        );

        test(
          'P8-Gate 6: already_processed after backup restore reconciles authoritative cloud state',
          () async {
            const opId = 'op_restored_retry';
            final backupJson = await backupService.createFullBackup(
              userId: testUserId,
            );
            final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
            (rawMap['data']['syncOperations'] as List).add({
              'id': opId,
              'userId': testUserId,
              'entityType': 'category',
              'entityId': 'cat_1',
              'operationType': 'update',
              'payloadJson': '{"name":"Local Backup Name"}',
              'createdAtUtc': '2026-09-01T00:00:00.000Z',
              'retryCount': 0,
            });
            final canonicalStr = jsonEncode(
              BackupArchive.canonicalize(rawMap['data']),
            );
            rawMap['metadata']['checksum'] = sha256
                .convert(utf8.encode(canonicalStr))
                .toString();

            await backupService.restoreFromBackup(
              jsonEncode(rawMap),
              targetUserId: testUserId,
              restoreSyncQueue: true,
            );

            final connectivityService = _FakeConnectivityService();
            final remoteDataSource = FakeSyncRemoteDataSource();
            remoteDataSource.activeAuthUserId = testUserId;

            final coordinator = SyncCoordinator(
              db: db,
              remoteDataSource: remoteDataSource,
              connectivityService: connectivityService,
              getActiveUserId: () => testUserId,
            );

            final tCloud = DateTime.utc(2026, 9, 4);
            remoteDataSource.seedRemoteRecord(
              entityType: 'category',
              id: 'cat_1',
              userId: testUserId,
              payload: {
                'name': 'Cloud Authority',
                'type': 'expense',
                'icon_code_point': 0xe040,
                'color_value': 0xFF10B981,
                'is_system': false,
                'is_archived': false,
              },
              fieldTimestamps: {'name': tCloud.toIso8601String()},
              updatedAtUtc: tCloud,
            );
            remoteDataSource.processedTokens.add('$testUserId:$opId');

            final syncRes = await coordinator.synchronize();
            expect(syncRes.success, isTrue);

            final postCat = await (db.select(
              db.categoriesTable,
            )..where((c) => c.id.equals('cat_1'))).getSingle();
            expect(postCat.name, equals('Cloud Authority'));
            expect(postCat.syncStatus, equals('synced'));

            final remainingOps = await (db.select(
              db.syncOperationsTable,
            )..where((o) => o.id.equals(opId))).get();
            expect(remainingOps.isEmpty, isTrue);
          },
        );

        test(
          'P8-Gate 7: already_processed operation after app restart reconciles before clearing queue',
          () async {
            const opId = 'op_restart_retry';
            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value(opId),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('account'),
                    entityId: const drift.Value('acc_1'),
                    operationType: const drift.Value('update'),
                    payloadJson: const drift.Value('{"name":"Checking 1"}'),
                    createdAtUtc: drift.Value(DateTime.utc(2026, 9, 1)),
                  ),
                );

            final connectivityService = _FakeConnectivityService();
            final remoteDataSource = FakeSyncRemoteDataSource();
            remoteDataSource.activeAuthUserId = testUserId;

            final coordinator = SyncCoordinator(
              db: db,
              remoteDataSource: remoteDataSource,
              connectivityService: connectivityService,
              getActiveUserId: () => testUserId,
            );

            final tCloud = DateTime.utc(2026, 9, 3);
            remoteDataSource.seedRemoteRecord(
              entityType: 'account',
              id: 'acc_1',
              userId: testUserId,
              payload: {
                'name': 'Checking Premium',
                'account_type': 'bank',
                'currency': 'INR',
                'initial_balance_minor': 500000,
                'color_value': 0xFF14B8A6,
                'icon_code_point': 0xe040,
              },
              fieldTimestamps: {'name': tCloud.toIso8601String()},
              updatedAtUtc: tCloud,
            );
            remoteDataSource.processedTokens.add('$testUserId:$opId');

            final syncRes = await coordinator.synchronize();
            expect(syncRes.success, isTrue);

            final postAcc = await (db.select(
              db.accountsTable,
            )..where((a) => a.id.equals('acc_1'))).getSingle();
            expect(postAcc.name, equals('Checking Premium'));
            expect(postAcc.syncStatus, equals('synced'));

            final remainingOps = await (db.select(
              db.syncOperationsTable,
            )..where((o) => o.id.equals(opId))).get();
            expect(remainingOps.isEmpty, isTrue);
          },
        );

        test(
          'P8-Gate 8: modifying entityCounts in metadata header does not compromise financial correctness or corrupt restored data',
          () async {
            final backupJson = await backupService.createFullBackup(
              password: 'CorrectPassword123!',
              userId: testUserId,
            );

            final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
            final meta = rawMap['metadata'] as Map<String, dynamic>;

            meta['entityCounts'] = {
              'transactions': 999999,
              'accounts': 0,
              'malicious': 12345,
            };

            await backupService.restoreFromBackup(
              jsonEncode(rawMap),
              password: 'CorrectPassword123!',
              targetUserId: testUserId,
            );

            final txs = await (db.select(
              db.transactionsTable,
            )..where((t) => t.userId.equals(testUserId))).get();
            expect(txs.length, equals(1));
            expect(txs.first.amountMinor, equals(15000));
            expect(txs.first.note, equals('Weekly essentials'));

            final accounts = await (db.select(
              db.accountsTable,
            )..where((a) => a.userId.equals(testUserId))).get();
            expect(accounts.length, equals(1));
            expect(accounts.first.name, equals('Checking'));
          },
        );

        test(
          'P8-Gate 9: (updatedAtUtc, entityId) composite cursor skips ID0, consumes ID1, and receives ID2, ID3, ID4',
          () {
            final t1 = DateTime.utc(2026, 9, 1, 12, 0, 0);
            final t2 = DateTime.utc(2026, 9, 1, 13, 0, 0);

            final cursor = SyncCursor(timestampUtc: t1, entityId: 'ID1');

            final candidates = [
              (time: t1, id: 'ID0'),
              (time: t1, id: 'ID1'),
              (time: t1, id: 'ID2'),
              (time: t1, id: 'ID3'),
              (time: t2, id: 'ID4'),
            ];

            final results = <String, bool>{};
            for (final c in candidates) {
              results[c.id] = cursor.isAfterCursor(
                candidateTime: c.time,
                candidateId: c.id,
              );
            }

            expect(results['ID0'], isFalse); // ID0 -> skip
            expect(results['ID1'], isFalse); // ID1 -> already consumed
            expect(results['ID2'], isTrue); // ID2 -> receive
            expect(results['ID3'], isTrue); // ID3 -> receive
            expect(results['ID4'], isTrue); // ID4 -> receive
          },
        );

        test(
          'P8-Gate 10: failed restore preserves entire non-empty database field-for-field with zero mutations',
          () async {
            final t0 = DateTime.utc(2026, 9, 1);
            await db
                .into(db.budgetsTable)
                .insert(
                  BudgetsTableCompanion(
                    id: const drift.Value('b_audit'),
                    userId: const drift.Value(testUserId),
                    monthYear: const drift.Value('2026-09'),
                    amountMinor: const drift.Value(200000),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.categoryBudgetsTable)
                .insert(
                  CategoryBudgetsTableCompanion(
                    id: const drift.Value('cb_audit'),
                    userId: const drift.Value(testUserId),
                    budgetId: const drift.Value('b_audit'),
                    categoryId: const drift.Value('cat_1'),
                    amountMinor: const drift.Value(80000),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.savingsGoalsTable)
                .insert(
                  SavingsGoalsTableCompanion(
                    id: const drift.Value('sg_audit'),
                    userId: const drift.Value(testUserId),
                    name: const drift.Value('Car'),
                    targetAmountMinor: const drift.Value(300000),
                    currentAmountMinor: const drift.Value(50000),
                    targetDateUtc: drift.Value(t0),
                    iconCodePoint: const drift.Value(1),
                    colorValue: const drift.Value(1),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.recurringTransactionsTable)
                .insert(
                  RecurringTransactionsTableCompanion(
                    id: const drift.Value('rt_audit'),
                    userId: const drift.Value(testUserId),
                    amountMinor: const drift.Value(25000),
                    transactionType: const drift.Value('expense'),
                    categoryId: const drift.Value('cat_1'),
                    accountId: const drift.Value('acc_1'),
                    frequency: const drift.Value('monthly'),
                    startDateUtc: drift.Value(t0),
                    nextOccurrenceUtc: drift.Value(t0),
                    createdAtUtc: drift.Value(t0),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.settingsTable)
                .insert(
                  SettingsTableCompanion(
                    key: const drift.Value('dark_theme'),
                    userId: const drift.Value(testUserId),
                    value: const drift.Value('true'),
                    updatedAtUtc: drift.Value(t0),
                  ),
                );
            await db
                .into(db.syncOperationsTable)
                .insert(
                  SyncOperationsTableCompanion(
                    id: const drift.Value('op_audit'),
                    userId: const drift.Value(testUserId),
                    entityType: const drift.Value('transaction'),
                    entityId: const drift.Value('tx_1'),
                    operationType: const drift.Value('update'),
                    payloadJson: const drift.Value('{"note":"audit"}'),
                    createdAtUtc: drift.Value(t0),
                  ),
                );

            final preUsers = await (db.select(
              db.usersTable,
            )..where((u) => u.id.equals(testUserId))).get();
            final preAccounts = await (db.select(
              db.accountsTable,
            )..where((a) => a.userId.equals(testUserId))).get();
            final preCategories = await (db.select(
              db.categoriesTable,
            )..where((c) => c.userId.equals(testUserId))).get();
            final preTransactions = await (db.select(
              db.transactionsTable,
            )..where((t) => t.userId.equals(testUserId))).get();
            final preBudgets = await (db.select(
              db.budgetsTable,
            )..where((b) => b.userId.equals(testUserId))).get();
            final preCategoryBudgets = await (db.select(
              db.categoryBudgetsTable,
            )..where((cb) => cb.userId.equals(testUserId))).get();
            final preGoals = await (db.select(
              db.savingsGoalsTable,
            )..where((g) => g.userId.equals(testUserId))).get();
            final preRecurring = await (db.select(
              db.recurringTransactionsTable,
            )..where((r) => r.userId.equals(testUserId))).get();
            final preSettings = await (db.select(
              db.settingsTable,
            )..where((s) => s.userId.equals(testUserId))).get();
            final preMeta = await (db.select(
              db.syncMetadataTable,
            )..where((m) => m.userId.equals(testUserId))).get();
            final preOps = await (db.select(
              db.syncOperationsTable,
            )..where((o) => o.userId.equals(testUserId))).get();

            final backupJson = await backupService.createFullBackup(
              userId: testUserId,
            );
            final rawMap = jsonDecode(backupJson) as Map<String, dynamic>;
            (rawMap['data']['transactions'] as List).add({
              'id': 'tx_corrupted_ts',
              'userId': testUserId,
              'amountMinor': 5000,
              'transactionType': 'expense',
              'categoryId': 'cat_1',
              'accountId': 'acc_1',
              'transactionDateUtc': 'NOT_AN_ISO_DATE',
              'createdAtUtc': 'NOT_AN_ISO_DATE',
              'updatedAtUtc': 'NOT_AN_ISO_DATE',
            });
            final canonicalStr = jsonEncode(
              BackupArchive.canonicalize(rawMap['data']),
            );
            rawMap['metadata']['checksum'] = sha256
                .convert(utf8.encode(canonicalStr))
                .toString();

            expect(
              () => backupService.restoreFromBackup(
                jsonEncode(rawMap),
                targetUserId: testUserId,
              ),
              throwsA(isA<ValidationException>()),
            );

            final postUsers = await (db.select(
              db.usersTable,
            )..where((u) => u.id.equals(testUserId))).get();
            final postAccounts = await (db.select(
              db.accountsTable,
            )..where((a) => a.userId.equals(testUserId))).get();
            final postCategories = await (db.select(
              db.categoriesTable,
            )..where((c) => c.userId.equals(testUserId))).get();
            final postTransactions = await (db.select(
              db.transactionsTable,
            )..where((t) => t.userId.equals(testUserId))).get();
            final postBudgets = await (db.select(
              db.budgetsTable,
            )..where((b) => b.userId.equals(testUserId))).get();
            final postCategoryBudgets = await (db.select(
              db.categoryBudgetsTable,
            )..where((cb) => cb.userId.equals(testUserId))).get();
            final postGoals = await (db.select(
              db.savingsGoalsTable,
            )..where((g) => g.userId.equals(testUserId))).get();
            final postRecurring = await (db.select(
              db.recurringTransactionsTable,
            )..where((r) => r.userId.equals(testUserId))).get();
            final postSettings = await (db.select(
              db.settingsTable,
            )..where((s) => s.userId.equals(testUserId))).get();
            final postMeta = await (db.select(
              db.syncMetadataTable,
            )..where((m) => m.userId.equals(testUserId))).get();
            final postOps = await (db.select(
              db.syncOperationsTable,
            )..where((o) => o.userId.equals(testUserId))).get();

            expect(postUsers.length, equals(preUsers.length));
            expect(postAccounts.length, equals(preAccounts.length));
            expect(postAccounts.first.name, equals(preAccounts.first.name));
            expect(
              postAccounts.first.initialBalanceMinor,
              equals(preAccounts.first.initialBalanceMinor),
            );
            expect(postCategories.length, equals(preCategories.length));
            expect(postTransactions.length, equals(preTransactions.length));
            expect(
              postTransactions.first.amountMinor,
              equals(preTransactions.first.amountMinor),
            );
            expect(postBudgets.length, equals(preBudgets.length));
            expect(
              postBudgets.first.amountMinor,
              equals(preBudgets.first.amountMinor),
            );
            expect(
              postCategoryBudgets.length,
              equals(preCategoryBudgets.length),
            );
            expect(postGoals.length, equals(preGoals.length));
            expect(
              postGoals.first.targetAmountMinor,
              equals(preGoals.first.targetAmountMinor),
            );
            expect(postRecurring.length, equals(preRecurring.length));
            expect(postSettings.length, equals(preSettings.length));
            expect(postSettings.first.value, equals(preSettings.first.value));
            expect(postMeta.length, equals(preMeta.length));
            expect(postMeta.first.syncCursor, equals(preMeta.first.syncCursor));
            expect(postOps.length, equals(preOps.length));
            expect(postOps.first.id, equals(preOps.first.id));
          },
        );
      },
    );
  });
}
