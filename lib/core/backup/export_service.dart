import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../utils/money_utils.dart';

/// Service dedicated to exporting user-readable financial data for spreadsheets.
///
/// CRITICAL ARCHITECTURAL DISTINCTION:
/// CSV Export is strictly for human consumption and spreadsheet analysis.
/// It MUST NOT be used or confused with system recovery backups because it
/// omits entity UUIDs, foreign key links, field timestamps, tombstones,
/// and sync engine cursors.
class ExportService {
  final AppDatabase _db;

  ExportService(this._db);

  /// Exports all non-deleted transactions for [userId] as a RFC 4180 compliant CSV string.
  Future<String> exportTransactionsCsv({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // 1. Fetch transactions, accounts, and categories for human-readable mapping
    final accounts = await (_db.select(
      _db.accountsTable,
    )..where((a) => a.userId.equals(userId))).get();
    final categories = await (_db.select(
      _db.categoriesTable,
    )..where((c) => c.userId.equals(userId))).get();

    final accountMap = {for (final a in accounts) a.id: a.name};
    final currencyMap = {for (final a in accounts) a.id: a.currency};
    final categoryMap = {for (final c in categories) c.id: c.name};

    var query = _db.select(_db.transactionsTable)
      ..where((t) => t.userId.equals(userId) & t.deletedAtUtc.isNull());

    if (startDate != null) {
      query = query
        ..where(
          (t) => t.transactionDateUtc.isBiggerOrEqualValue(startDate.toUtc()),
        );
    }
    if (endDate != null) {
      query = query
        ..where(
          (t) => t.transactionDateUtc.isSmallerOrEqualValue(endDate.toUtc()),
        );
    }

    query = query..orderBy([(t) => OrderingTerm.desc(t.transactionDateUtc)]);

    final transactions = await query.get();

    // 2. Build CSV rows
    final rows = <List<dynamic>>[
      // Header row
      ['Date', 'Type', 'Category', 'Account', 'Amount', 'Currency', 'Note'],
    ];

    for (final tx in transactions) {
      final dateStr = tx.transactionDateUtc.toIso8601String().substring(0, 10);
      final typeStr = tx.transactionType.toUpperCase();
      final catName = categoryMap[tx.categoryId] ?? 'Unknown Category';
      final accName = accountMap[tx.accountId] ?? 'Unknown Account';
      final currency = currencyMap[tx.accountId] ?? 'INR';
      final formattedAmount = MoneyUtils.formatPlain(tx.amountMinor);

      rows.add([
        dateStr,
        typeStr,
        catName,
        accName,
        formattedAmount,
        currency,
        tx.note,
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }
}
