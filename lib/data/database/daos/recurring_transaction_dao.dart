import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/recurring_transactions_table.dart';

part 'recurring_transaction_dao.g.dart';

@DriftAccessor(tables: [RecurringTransactionsTable])
class RecurringTransactionDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringTransactionDaoMixin {
  RecurringTransactionDao(super.db);

  Stream<List<RecurringTransactionData>> watchAllRecurring(String userId) {
    return (select(recurringTransactionsTable)
          ..where((r) => r.userId.equals(userId) & r.deletedAtUtc.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.nextOccurrenceUtc)]))
        .watch();
  }

  Future<List<RecurringTransactionData>> getDueRecurringTransactions({
    required String userId,
    required DateTime nowUtc,
  }) {
    return (select(recurringTransactionsTable)..where(
          (r) =>
              r.userId.equals(userId) &
              r.isActive.equals(true) &
              r.deletedAtUtc.isNull() &
              r.nextOccurrenceUtc.isSmallerOrEqualValue(nowUtc),
        ))
        .get();
  }

  Future<int> insertRecurring(RecurringTransactionsTableCompanion entry) {
    return into(recurringTransactionsTable).insert(entry);
  }

  Future<bool> updateRecurring(RecurringTransactionsTableCompanion entry) {
    return update(recurringTransactionsTable).replace(entry);
  }

  Future<int> updateNextExecutionDate({
    required String id,
    required DateTime nextOccurrenceUtc,
    required DateTime lastExecutedDateUtc,
    required DateTime updatedAtUtc,
  }) {
    return (update(
      recurringTransactionsTable,
    )..where((r) => r.id.equals(id))).write(
      RecurringTransactionsTableCompanion(
        nextOccurrenceUtc: Value(nextOccurrenceUtc),
        lastExecutedDateUtc: Value(lastExecutedDateUtc),
        updatedAtUtc: Value(updatedAtUtc),
        syncStatus: const Value('pendingUpdate'),
      ),
    );
  }

  Future<int> toggleActive({
    required String id,
    required bool isActive,
    required DateTime updatedAtUtc,
  }) {
    return (update(
      recurringTransactionsTable,
    )..where((r) => r.id.equals(id))).write(
      RecurringTransactionsTableCompanion(
        isActive: Value(isActive),
        updatedAtUtc: Value(updatedAtUtc),
        syncStatus: const Value('pendingUpdate'),
      ),
    );
  }

  Future<int> softDeleteRecurring({
    required String id,
    required DateTime deletedAtUtc,
  }) {
    return (update(
      recurringTransactionsTable,
    )..where((r) => r.id.equals(id))).write(
      RecurringTransactionsTableCompanion(
        deletedAtUtc: Value(deletedAtUtc),
        updatedAtUtc: Value(deletedAtUtc),
        syncStatus: const Value('pendingDelete'),
      ),
    );
  }
}
