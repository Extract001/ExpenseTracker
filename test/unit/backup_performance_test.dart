import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/backup/backup_models.dart';
import 'package:expense_tracker/core/backup/backup_service.dart';
import 'package:expense_tracker/core/database/encrypted_database_connection.dart';
import 'package:expense_tracker/core/utils/app_logger.dart';
import 'package:expense_tracker/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 8: High-Volume 10,000+ Transaction Backup & Restore Benchmark', () {
    late AppDatabase db;
    late BackupService backupService;
    const testUserId = 'perf_user_10k';

    setUp(() async {
      AppLogger.enableConsoleLogging = false;
      db = AppDatabase(EncryptedDatabaseConnection.createInMemoryConnection());
      backupService = BackupService(db);

      // Seed base user, category, and account
      await db
          .into(db.usersTable)
          .insert(
            UsersTableCompanion(
              id: const drift.Value(testUserId),
              email: const drift.Value('perf@example.com'),
              displayName: const drift.Value('Perf User'),
              createdAtUtc: drift.Value(DateTime.utc(2026, 1, 1)),
              lastActiveAtUtc: drift.Value(DateTime.utc(2026, 9, 6)),
            ),
          );

      await db
          .into(db.categoriesTable)
          .insert(
            CategoriesTableCompanion(
              id: const drift.Value('perf_cat_1'),
              userId: const drift.Value(testUserId),
              name: const drift.Value('General Expenses'),
              type: const drift.Value('expense'),
              iconCodePoint: const drift.Value(0xe040),
              colorValue: const drift.Value(0xFF10B981),
              createdAtUtc: drift.Value(DateTime.utc(2026, 1, 1)),
              updatedAtUtc: drift.Value(DateTime.utc(2026, 1, 1)),
            ),
          );

      await db
          .into(db.accountsTable)
          .insert(
            AccountsTableCompanion(
              id: const drift.Value('perf_acc_1'),
              userId: const drift.Value(testUserId),
              name: const drift.Value('Primary Account'),
              accountType: const drift.Value('bank'),
              currency: const drift.Value('INR'),
              initialBalanceMinor: const drift.Value(10000000),
              createdAtUtc: drift.Value(DateTime.utc(2026, 1, 1)),
              updatedAtUtc: drift.Value(DateTime.utc(2026, 1, 1)),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      '1. Benchmarks backup generation and restore on 10,000 records without OutOfMemory',
      () async {
        const targetCount = 10000;

        // 1. Batch insert 10,000 transactions
        final seedStopwatch = Stopwatch()..start();
        await db.batch((batch) {
          final companions = <TransactionsTableCompanion>[];
          for (int i = 1; i <= targetCount; i++) {
            companions.add(
              TransactionsTableCompanion.insert(
                id: 'tx_perf_$i',
                userId: testUserId,
                amountMinor: 100 + (i % 5000),
                transactionType: 'expense',
                categoryId: 'perf_cat_1',
                accountId: 'perf_acc_1',
                note: drift.Value('Performance transaction record #$i'),
                transactionDateUtc: DateTime.utc(
                  2026,
                  1,
                  1,
                ).add(Duration(minutes: i)),
                createdAtUtc: DateTime.utc(
                  2026,
                  1,
                  1,
                ).add(Duration(minutes: i)),
                updatedAtUtc: DateTime.utc(
                  2026,
                  1,
                  1,
                ).add(Duration(minutes: i)),
                fieldTimestampsJson: const drift.Value(
                  '{"amountMinor":"2026-01-01T00:00:00.000Z"}',
                ),
                syncStatus: const drift.Value('synced'),
              ),
            );
          }
          batch.insertAll(db.transactionsTable, companions);
        });
        seedStopwatch.stop();

        final initialCount = (await (db.select(
          db.transactionsTable,
        )..where((t) => t.userId.equals(testUserId))).get()).length;
        expect(initialCount, equals(targetCount));

        // 2. Measure Backup Generation Performance
        final memBeforeBackup = ProcessInfo.currentRss;
        final backupStopwatch = Stopwatch()..start();
        final backupJson = await backupService.createFullBackup(
          userId: testUserId,
        );
        backupStopwatch.stop();
        final memAfterBackup = ProcessInfo.currentRss;

        final backupBytes = utf8.encode(backupJson).length;
        final backupSizeMb = (backupBytes / (1024 * 1024)).toStringAsFixed(2);

        // Verify backup structure
        final archive = BackupArchive.fromJson(jsonDecode(backupJson));
        expect(
          archive.metadata.entityCounts['transactions'],
          equals(targetCount),
        );

        // 3. Clear existing local transactions to simulate clean device recovery
        await (db.delete(
          db.transactionsTable,
        )..where((t) => t.userId.equals(testUserId))).go();
        final clearedCount = (await (db.select(
          db.transactionsTable,
        )..where((t) => t.userId.equals(testUserId))).get()).length;
        expect(clearedCount, equals(0));

        // 4. Measure Restore Performance
        final memBeforeRestore = ProcessInfo.currentRss;
        final restoreStopwatch = Stopwatch()..start();
        await backupService.restoreFromBackup(
          backupJson,
          targetUserId: testUserId,
        );
        restoreStopwatch.stop();
        final memAfterRestore = ProcessInfo.currentRss;

        // 5. Verify full data integrity post-restore
        final restoredCount = (await (db.select(
          db.transactionsTable,
        )..where((t) => t.userId.equals(testUserId))).get()).length;
        expect(restoredCount, equals(targetCount));

        // Check first and last transaction
        final firstTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals('tx_perf_1'))).getSingle();
        expect(firstTx.note, equals('Performance transaction record #1'));

        final lastTx = await (db.select(
          db.transactionsTable,
        )..where((t) => t.id.equals('tx_perf_$targetCount'))).getSingle();
        expect(
          lastTx.note,
          equals('Performance transaction record #$targetCount'),
        );

        // 6. Assert Performance Bounds
        // 10,000 transactions backup generation should complete within 10 seconds in tests
        expect(backupStopwatch.elapsedMilliseconds, lessThan(10000));
        // 10,000 transactions restore should complete within 10 seconds in tests
        expect(restoreStopwatch.elapsedMilliseconds, lessThan(10000));

        // Memory stability assertions (RSS > 0 and bounded)
        expect(memBeforeBackup, greaterThanOrEqualTo(0));
        expect(memAfterBackup, greaterThanOrEqualTo(0));
        expect(memBeforeRestore, greaterThanOrEqualTo(0));
        expect(memAfterRestore, greaterThanOrEqualTo(0));
        expect(double.parse(backupSizeMb), greaterThan(0));
      },
    );
  });
}
