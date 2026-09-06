import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/database/encrypted_database_connection.dart';
import 'package:expense_tracker/data/database/app_database.dart';

void main() {
  group('Database Schema Versioning & Migration Tests', () {
    test(
      'Schema version is properly defined and database initializes with version 1',
      () async {
        final db = AppDatabase(
          EncryptedDatabaseConnection.createInMemoryConnection(),
        );

        expect(db.schemaVersion, equals(1));

        // Verify all tables are created and accessible without error
        final categories = await db.categoryDao.getAllCategories(
          userId: 'test',
        );
        expect(categories, isA<List>());

        final accounts = await db.accountDao.getAllAccounts('test');
        expect(accounts, isA<List>());

        await db.close();
      },
    );
  });
}
