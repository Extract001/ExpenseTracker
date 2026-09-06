import '../entities/recurring_transaction_entity.dart';

abstract class IRecurringTransactionRepository {
  Stream<List<RecurringTransactionEntity>> watchAllRecurring();
  Future<List<RecurringTransactionEntity>> getDueRecurringTransactions(
    DateTime nowUtc,
  );
  Future<void> createRecurring(RecurringTransactionEntity entity);
  Future<void> updateRecurring(RecurringTransactionEntity entity);
  Future<void> updateNextExecutionDate(
    String id,
    DateTime nextDate,
    DateTime lastExecutedDate,
  );
  Future<void> toggleActive(String id, bool isActive);
  Future<void> softDeleteRecurring(String id);
  Future<int> processDueRecurringRules(DateTime nowUtc);
}
