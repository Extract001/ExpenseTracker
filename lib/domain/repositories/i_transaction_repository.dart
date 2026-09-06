import '../entities/enums.dart';
import '../entities/transaction_entity.dart';

abstract class ITransactionRepository {
  Stream<List<TransactionEntity>> watchRecentTransactions({int limit = 20});

  Future<List<TransactionEntity>> getTransactionsCursor({
    DateTime? cursorDate,
    String? cursorId,
    int limit = 50,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? minAmount,
    int? maxAmount,
    String? searchQuery,
  });

  Future<TransactionEntity?> getTransactionById(String id);
  Future<void> createTransaction(TransactionEntity transaction);
  Future<void> updateTransaction(TransactionEntity transaction);
  Future<void> softDeleteTransaction(String id);
  Future<int> getTotalIncome(DateTime startDateUtc, DateTime endDateUtc);
  Future<int> getTotalExpense(DateTime startDateUtc, DateTime endDateUtc);
}
