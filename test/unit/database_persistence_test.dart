import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Database Lifecycle & Persistence Verification', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('expense_db_test_');
      dbFile = File('${tempDir.path}${Platform.pathSeparator}test_records.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Database write, close, reopen, and read persistence lifecycle', () {
      // 1. Initial creation and write
      var db = sqlite3.open(dbFile.path);
      db.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          amount INTEGER NOT NULL,
          type TEXT NOT NULL,
          category_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          note TEXT NOT NULL,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL
        );
      ''');

      db.execute('''
        INSERT INTO transactions VALUES (
          'tx_101',
          'local_guest_user',
          12550,
          'expense',
          'cat_food',
          'acc_bank',
          'Grocery shopping',
          '2026-09-06T10:00:00.000Z',
          '2026-09-06T10:00:00.000Z',
          '2026-09-06T10:00:00.000Z',
          'pendingCreate'
        );
      ''');

      // Close the database to simulate app termination
      db.dispose();

      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));

      // 2. Reopen the database after app restart
      final reopenedDb = sqlite3.open(dbFile.path);
      final results = reopenedDb.select(
        'SELECT * FROM transactions WHERE id = ?;',
        ['tx_101'],
      );

      expect(results.length, equals(1));
      final record = results.first;
      expect(record['id'], equals('tx_101'));
      expect(record['user_id'], equals('local_guest_user'));
      expect(record['amount'], equals(12550));
      expect(record['note'], equals('Grocery shopping'));
      expect(record['sync_status'], equals('pendingCreate'));

      reopenedDb.dispose();
    });
  });
}
