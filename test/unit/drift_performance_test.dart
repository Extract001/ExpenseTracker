import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/constants/app_constants.dart';
import 'package:expense_tracker/core/database/encrypted_database_connection.dart';
import 'package:expense_tracker/data/database/app_database.dart';

void main() {
  group('10,000+ Transaction Scale & Performance Verification', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(EncryptedDatabaseConnection.createInMemoryConnection());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Inserts 10,000 transactions and tests database-side cursor pagination & aggregations',
      () async {
        const count = 10000;
        final baseDate = DateTime(2026, 1, 1, 0, 0, 0).toUtc();

        final stopwatch = Stopwatch()..start();

        // Bulk insert 10,000 records inside a single atomic database transaction
        await db.transaction(() async {
          for (int i = 0; i < count; i++) {
            final txDate = baseDate.add(Duration(minutes: i * 30));
            await db
                .into(db.transactionsTable)
                .insert(
                  TransactionsTableCompanion.insert(
                    id: 'tx_bulk_$i',
                    userId: AppConstants.defaultUserId,
                    amountMinor: (i % 100 + 1) * 1000,
                    transactionType: i % 5 == 0 ? 'income' : 'expense',
                    categoryId: i % 2 == 0 ? 'cat_food' : 'cat_travel',
                    accountId: 'acc_cash_default',
                    note: Value('Bulk transaction $i'),
                    transactionDateUtc: txDate,
                    createdAtUtc: txDate,
                    updatedAtUtc: txDate,
                    syncStatus: const Value('synced'),
                  ),
                );
          }
        });

        stopwatch.stop();

        // 1. Cursor pagination test: fetch first page of 50 items
        final page1Stopwatch = Stopwatch()..start();
        final page1 = await db.transactionDao.getTransactionsCursor(
          userId: AppConstants.defaultUserId,
          limit: 50,
        );
        page1Stopwatch.stop();

        expect(page1.length, equals(50));
        expect(page1.first.id, equals('tx_bulk_9999')); // newest
        expect(page1Stopwatch.elapsedMilliseconds, lessThan(200));

        // 2. Cursor pagination test: fetch second page using cursor
        final page2Stopwatch = Stopwatch()..start();
        final page2 = await db.transactionDao.getTransactionsCursor(
          userId: AppConstants.defaultUserId,
          cursorDate: page1.last.transactionDateUtc,
          cursorId: page1.last.id,
          limit: 50,
        );
        page2Stopwatch.stop();

        expect(page2.length, equals(50));
        expect(page2.first.id, isNot(equals(page1.last.id)));
        expect(page2Stopwatch.elapsedMilliseconds, lessThan(200));

        // 3. Database aggregation performance test: SUM over 10,000 records
        final aggStopwatch = Stopwatch()..start();
        final totalExpense = await db.transactionDao.getTotalExpense(
          userId: AppConstants.defaultUserId,
          startDateUtc: baseDate,
          endDateUtc: baseDate.add(const Duration(days: 365)),
        );
        aggStopwatch.stop();

        expect(totalExpense, greaterThan(0));
        // Database query should complete in well under 500ms
        expect(aggStopwatch.elapsedMilliseconds, lessThan(500));
      },
    );
  });
}
