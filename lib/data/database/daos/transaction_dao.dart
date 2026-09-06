import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions_table.dart';
import '../tables/categories_table.dart';
import '../tables/accounts_table.dart';

part 'transaction_dao.g.dart';

@DriftAccessor(tables: [TransactionsTable, CategoriesTable, AccountsTable])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// Streams recent active (non-deleted) transactions for a given user.
  Stream<List<TransactionData>> watchRecentTransactions({
    required String userId,
    int limit = 20,
  }) {
    return (select(transactionsTable)
          ..where((t) => t.userId.equals(userId) & t.deletedAtUtc.isNull())
          ..orderBy([
            (t) => OrderingTerm.desc(t.transactionDateUtc),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit))
        .watch();
  }

  /// Keyset/Cursor pagination query for 10,000+ transaction scale.
  Future<List<TransactionData>> getTransactionsCursor({
    required String userId,
    DateTime? cursorDate,
    String? cursorId,
    int limit = 50,
    String? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? minAmountMinor,
    int? maxAmountMinor,
    String? searchQuery,
  }) {
    final query = select(transactionsTable)
      ..where((t) => t.userId.equals(userId) & t.deletedAtUtc.isNull());

    if (cursorDate != null && cursorId != null) {
      query.where(
        (t) =>
            t.transactionDateUtc.isSmallerThanValue(cursorDate) |
            (t.transactionDateUtc.equals(cursorDate) &
                t.id.isSmallerThanValue(cursorId)),
      );
    }

    if (type != null) {
      query.where((t) => t.transactionType.equals(type));
    }

    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }

    if (accountId != null) {
      query.where(
        (t) => t.accountId.equals(accountId) | t.toAccountId.equals(accountId),
      );
    }

    if (startDate != null) {
      query.where((t) => t.transactionDateUtc.isBiggerOrEqualValue(startDate));
    }

    if (endDate != null) {
      query.where((t) => t.transactionDateUtc.isSmallerOrEqualValue(endDate));
    }

    if (minAmountMinor != null) {
      query.where((t) => t.amountMinor.isBiggerOrEqualValue(minAmountMinor));
    }

    if (maxAmountMinor != null) {
      query.where((t) => t.amountMinor.isSmallerOrEqualValue(maxAmountMinor));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      query.where((t) => t.note.like('%${searchQuery.trim()}%'));
    }

    query.orderBy([
      (t) => OrderingTerm.desc(t.transactionDateUtc),
      (t) => OrderingTerm.desc(t.id),
    ]);

    query.limit(limit);
    return query.get();
  }

  Future<TransactionData?> getTransactionById(String id) {
    return (select(
      transactionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertTransaction(TransactionsTableCompanion entry) {
    return into(transactionsTable).insert(entry);
  }

  Future<bool> updateTransaction(TransactionsTableCompanion entry) {
    return update(transactionsTable).replace(entry);
  }

  Future<int> softDeleteTransaction({
    required String id,
    required DateTime deletedAtUtc,
    String syncStatus = 'pendingDelete',
  }) {
    return (update(transactionsTable)..where((t) => t.id.equals(id))).write(
      TransactionsTableCompanion(
        deletedAtUtc: Value(deletedAtUtc),
        updatedAtUtc: Value(deletedAtUtc),
        syncStatus: Value(syncStatus),
      ),
    );
  }

  /// Calculates total income in minor units using database-level SUM.
  Future<int> getTotalIncome({
    required String userId,
    required DateTime startDateUtc,
    required DateTime endDateUtc,
  }) async {
    final amountSum = transactionsTable.amountMinor.sum();
    final query = selectOnly(transactionsTable)
      ..addColumns([amountSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.deletedAtUtc.isNull() &
            transactionsTable.transactionType.equals('income') &
            transactionsTable.transactionDateUtc.isBiggerOrEqualValue(
              startDateUtc,
            ) &
            transactionsTable.transactionDateUtc.isSmallerOrEqualValue(
              endDateUtc,
            ),
      );

    final result = await query
        .map((row) => row.read(amountSum))
        .getSingleOrNull();
    return result ?? 0;
  }

  /// Calculates total expenses in minor units using database-level SUM.
  Future<int> getTotalExpense({
    required String userId,
    required DateTime startDateUtc,
    required DateTime endDateUtc,
  }) async {
    final amountSum = transactionsTable.amountMinor.sum();
    final query = selectOnly(transactionsTable)
      ..addColumns([amountSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.deletedAtUtc.isNull() &
            transactionsTable.transactionType.equals('expense') &
            transactionsTable.transactionDateUtc.isBiggerOrEqualValue(
              startDateUtc,
            ) &
            transactionsTable.transactionDateUtc.isSmallerOrEqualValue(
              endDateUtc,
            ),
      );

    final result = await query
        .map((row) => row.read(amountSum))
        .getSingleOrNull();
    return result ?? 0;
  }
}
