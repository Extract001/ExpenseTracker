import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/accounts_table.dart';
import '../tables/transactions_table.dart';

part 'account_dao.g.dart';

@DriftAccessor(tables: [AccountsTable, TransactionsTable])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  Stream<List<AccountData>> watchAllAccounts(String userId) {
    return (select(accountsTable)
          ..where((a) => a.userId.equals(userId) & a.deletedAtUtc.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.name)]))
        .watch();
  }

  Future<List<AccountData>> getAllAccounts(String userId) {
    return (select(accountsTable)
          ..where((a) => a.userId.equals(userId) & a.deletedAtUtc.isNull())
          ..orderBy([(a) => OrderingTerm.asc(a.name)]))
        .get();
  }

  Future<AccountData?> getAccountById(String id) {
    return (select(
      accountsTable,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertAccount(AccountsTableCompanion entry) {
    return into(accountsTable).insert(entry);
  }

  Future<bool> updateAccount(AccountsTableCompanion entry) {
    return update(accountsTable).replace(entry);
  }

  Future<int> softDeleteAccount({
    required String id,
    required DateTime deletedAtUtc,
    String syncStatus = 'pendingDelete',
  }) {
    return (update(accountsTable)..where((a) => a.id.equals(id))).write(
      AccountsTableCompanion(
        deletedAtUtc: Value(deletedAtUtc),
        updatedAtUtc: Value(deletedAtUtc),
        syncStatus: Value(syncStatus),
      ),
    );
  }

  /// Calculates individual account balance by combining initial balance, incomes, expenses, and transfers.
  Future<int> getAccountBalance({
    required String userId,
    required String accountId,
  }) async {
    final account = await getAccountById(accountId);
    if (account == null) return 0;

    // Income to this account
    final incomeSum = transactionsTable.amountMinor.sum();
    final incomeQuery = selectOnly(transactionsTable)
      ..addColumns([incomeSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.accountId.equals(accountId) &
            transactionsTable.transactionType.equals('income') &
            transactionsTable.deletedAtUtc.isNull(),
      );
    final income =
        (await incomeQuery.map((r) => r.read(incomeSum)).getSingleOrNull()) ??
        0;

    // Expense from this account
    final expenseSum = transactionsTable.amountMinor.sum();
    final expenseQuery = selectOnly(transactionsTable)
      ..addColumns([expenseSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.accountId.equals(accountId) &
            transactionsTable.transactionType.equals('expense') &
            transactionsTable.deletedAtUtc.isNull(),
      );
    final expense =
        (await expenseQuery.map((r) => r.read(expenseSum)).getSingleOrNull()) ??
        0;

    // Transfers sent from this account
    final transferOutSum = transactionsTable.amountMinor.sum();
    final transferOutQuery = selectOnly(transactionsTable)
      ..addColumns([transferOutSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.accountId.equals(accountId) &
            transactionsTable.transactionType.equals('transfer') &
            transactionsTable.deletedAtUtc.isNull(),
      );
    final transferOut =
        (await transferOutQuery
            .map((r) => r.read(transferOutSum))
            .getSingleOrNull()) ??
        0;

    // Transfers received into this account
    final transferInSum = transactionsTable.amountMinor.sum();
    final transferInQuery = selectOnly(transactionsTable)
      ..addColumns([transferInSum])
      ..where(
        transactionsTable.userId.equals(userId) &
            transactionsTable.toAccountId.equals(accountId) &
            transactionsTable.transactionType.equals('transfer') &
            transactionsTable.deletedAtUtc.isNull(),
      );
    final transferIn =
        (await transferInQuery
            .map((r) => r.read(transferInSum))
            .getSingleOrNull()) ??
        0;

    return account.initialBalanceMinor +
        income -
        expense -
        transferOut +
        transferIn;
  }

  /// Calculates total net worth across all active accounts.
  Future<int> getTotalNetWorth(String userId) async {
    final accounts = await getAllAccounts(userId);
    int total = 0;
    for (final acc in accounts) {
      total += await getAccountBalance(userId: userId, accountId: acc.id);
    }
    return total;
  }
}
