import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/id_generator.dart';
import 'package:expense_tracker/domain/entities/enums.dart';
import 'package:expense_tracker/domain/entities/transaction_entity.dart';

void main() {
  group('Offline-First Architecture & Entity Verification', () {
    test('Local UUID generation without network dependencies', () {
      final id = IdGenerator.generateUuid();
      expect(id, isNotEmpty);
      expect(id.length, equals(36));
    });

    test(
      'Transaction entity created offline defaults to pendingCreate syncStatus',
      () {
        final now = DateTime.now().toUtc();
        final tx = TransactionEntity(
          id: IdGenerator.generateUuid(),
          userId: 'local_guest_user',
          amount: 25000, // ?250.00
          type: TransactionType.expense,
          categoryId: 'cat_food',
          accountId: 'acc_cash',
          note: 'Coffee and snacks',
          date: now,
          createdAt: now,
          updatedAt: now,
        );

        expect(tx.syncStatus, equals(SyncStatus.pendingCreate));
        expect(tx.isDeleted, isFalse);
        expect(tx.amount, equals(25000));
      },
    );

    test(
      'Soft-deletion applies deletedAt timestamp and switches to pendingDelete',
      () {
        final now = DateTime.now().toUtc();
        final tx = TransactionEntity(
          id: IdGenerator.generateUuid(),
          userId: 'local_guest_user',
          amount: 15000,
          type: TransactionType.expense,
          categoryId: 'cat_travel',
          accountId: 'acc_cash',
          note: 'Cab ride',
          date: now,
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.synced,
        );

        final deletedTx = tx.copyWith(
          deletedAt: now,
          syncStatus: SyncStatus.pendingDelete,
        );

        expect(deletedTx.isDeleted, isTrue);
        expect(deletedTx.syncStatus, equals(SyncStatus.pendingDelete));
      },
    );
  });
}
