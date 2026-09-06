import '../entities/account_entity.dart';

abstract class IAccountRepository {
  Stream<List<AccountEntity>> watchAllAccounts();
  Future<List<AccountEntity>> getAllAccounts();
  Future<AccountEntity?> getAccountById(String id);
  Future<void> createAccount(AccountEntity account);
  Future<void> updateAccount(AccountEntity account);
  Future<void> softDeleteAccount(String id);
  Future<int> getAccountBalance(String accountId);
  Future<int> getTotalNetWorth();
  Future<void> transferFunds({
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    DateTime? date,
  });
}
