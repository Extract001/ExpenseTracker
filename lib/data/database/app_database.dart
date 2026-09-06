import 'package:drift/drift.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/default_categories.dart';
import '../../core/database/encrypted_database_connection.dart';
import 'tables/users_table.dart';
import 'tables/categories_table.dart';
import 'tables/accounts_table.dart';
import 'tables/transactions_table.dart';
import 'tables/budgets_table.dart';
import 'tables/category_budgets_table.dart';
import 'tables/savings_goals_table.dart';
import 'tables/recurring_transactions_table.dart';
import 'tables/settings_table.dart';
import 'tables/sync_operations_table.dart';
import 'tables/sync_metadata_table.dart';
import 'tables/exchange_rates_table.dart';
import 'daos/transaction_dao.dart';
import 'daos/account_dao.dart';
import 'daos/category_dao.dart';
import 'daos/budget_dao.dart';
import 'daos/goal_dao.dart';
import 'daos/recurring_transaction_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/sync_metadata_dao.dart';
import 'daos/exchange_rates_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    UsersTable,
    CategoriesTable,
    AccountsTable,
    TransactionsTable,
    BudgetsTable,
    CategoryBudgetsTable,
    SavingsGoalsTable,
    RecurringTransactionsTable,
    SettingsTable,
    SyncOperationsTable,
    SyncMetadataTable,
    ExchangeRatesTable,
  ],
  daos: [
    TransactionDao,
    AccountDao,
    CategoryDao,
    BudgetDao,
    GoalDao,
    RecurringTransactionDao,
    SettingsDao,
    SyncQueueDao,
    SyncMetadataDao,
    ExchangeRatesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ?? EncryptedDatabaseConnection.createEncryptedConnection(),
      );

  @override
  int get schemaVersion => AppConstants.databaseSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _seedDefaultData();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Step-by-step schema migrations for future version upgrades
        // Example: if (from < 2) { await m.addColumn(transactionsTable, transactionsTable.newColumn); }
      },
      beforeOpen: (OpeningDetails details) async {
        // Enforce SQLite Foreign Key constraints
        await customStatement('PRAGMA foreign_keys = ON;');
      },
    );
  }

  /// Seeds default guest user, default categories, and base accounts upon initial creation.
  Future<void> _seedDefaultData() async {
    final nowUtc = DateTime.now().toUtc();

    // 1. Seed default local guest user
    await into(usersTable).insert(
      UsersTableCompanion(
        id: const Value(AppConstants.defaultUserId),
        displayName: const Value('Local User'),
        createdAtUtc: Value(nowUtc),
        lastActiveAtUtc: Value(nowUtc),
      ),
    );

    // 2. Seed default categories
    for (final cat in DefaultCategories.expenses) {
      await into(categoriesTable).insert(
        CategoriesTableCompanion(
          id: Value(cat.id),
          userId: const Value(AppConstants.defaultUserId),
          name: Value(cat.name),
          type: const Value('expense'),
          iconCodePoint: Value(cat.iconCodePoint),
          colorValue: Value(cat.colorValue),
          isSystem: const Value(true),
          createdAtUtc: Value(nowUtc),
          updatedAtUtc: Value(nowUtc),
          syncStatus: const Value('synced'),
        ),
      );
    }

    for (final cat in DefaultCategories.incomes) {
      await into(categoriesTable).insert(
        CategoriesTableCompanion(
          id: Value(cat.id),
          userId: const Value(AppConstants.defaultUserId),
          name: Value(cat.name),
          type: const Value('income'),
          iconCodePoint: Value(cat.iconCodePoint),
          colorValue: Value(cat.colorValue),
          isSystem: const Value(true),
          createdAtUtc: Value(nowUtc),
          updatedAtUtc: Value(nowUtc),
          syncStatus: const Value('synced'),
        ),
      );
    }

    // 3. Seed default accounts (Cash and Bank)
    await into(accountsTable).insert(
      AccountsTableCompanion(
        id: const Value('acc_cash_default'),
        userId: const Value(AppConstants.defaultUserId),
        name: const Value('Cash'),
        accountType: const Value('cash'),
        currency: const Value('INR'),
        initialBalanceMinor: const Value(0),
        colorValue: const Value(0xFF10B981), // Green
        iconCodePoint: const Value(0xe040),
        createdAtUtc: Value(nowUtc),
        updatedAtUtc: Value(nowUtc),
        syncStatus: const Value('synced'),
      ),
    );

    await into(accountsTable).insert(
      AccountsTableCompanion(
        id: const Value('acc_bank_default'),
        userId: const Value(AppConstants.defaultUserId),
        name: const Value('Bank Account'),
        accountType: const Value('bank'),
        currency: const Value('INR'),
        initialBalanceMinor: const Value(0),
        colorValue: const Value(0xFF3B82F6), // Blue
        iconCodePoint: const Value(0xe040),
        createdAtUtc: Value(nowUtc),
        updatedAtUtc: Value(nowUtc),
        syncStatus: const Value('synced'),
      ),
    );
  }
}
